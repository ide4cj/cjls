package cjls.macro_host

import std.collection.*
import std.env.getTempDirectory
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.*
import loupe.hir.macroBuildPlan
import loupe.vfs.{FileId, PathInterner, VfsPath}
import rope.Rope
import cjls.server.tryLockCacheDir

/**
 * A `cjc` that writes what a build of a package writes last, named as the `package` line of its file says.
 */
class PackageToolchain <: Toolchain {
    let calls = ArrayList<Array<String>>()

    public func compile(arguments: Array<String>): (Int64, String) {
        calls.add(arguments)
        let dir = Path(arguments[1])
        let out = Path(argumentOf(arguments, "--output-dir=").getOrThrow())
        let text = String.fromUtf8(File.readFrom(dir.join("${dir.fileName}.cj")))
        let line = text.lines().next().getOrThrow()
        let name = line[line.indexOf("package ").getOrThrow() + "package ".size..]
        let file = if (arguments.contains("--compile-macro")) {
            "lib-macro_${name}${LIBRARY_SUFFIX}"
        } else {
            "lib${name}.a"
        }
        File.writeTo(out.join(file), [])
        (0, "")
    }

    /**
     * Where each build of the package in `dir` wrote.
     */
    func outputsOf(dir: Path): Array<String> {
        calls.toArray().filter {call => call[1] == dir.toString()}.map {
            call => argumentOf(call, "--output-dir=").getOrThrow()
        }
    }
}

func argumentOf(arguments: Array<String>, prefix: String): ?String {
    arguments.iterator().filter {a => a.startsWith(prefix)}.next().map {a => a[prefix.size..]}
}

/**
 * Projects on disk, each a module whose packages are a directory of one file each.
 */
class Workspace {
    let root = Directory.createTemp(getTempDirectory())
    private let paths = PathInterner()
    private let modules = ArrayList<ModuleModel>()
    private let texts = ArrayList<(FileId, String)>()

    /**
     * The module `name` at `<root>/<dir>` with `packages`, each its name, its directory and its text.
     */
    func module(dir: String, name: String, packages: Array<(String, String, String)>, deps!: Array<String> = []): Unit {
        let at = root.join(dir)
        let models = ArrayList<PackageModel>()
        for ((pkg, sub, text) in packages) {
            Directory.create(at.join(sub), recursive: true)
            let file = at.join(sub).join("${sub}.cj")
            File.writeTo(file, text.toArray())
            texts.add((paths.intern(VfsPath.file(file)), text))
            models.add(PackageModel(pkg, VfsPath.file(at.join(sub)), [VfsPath.file(file)]))
        }
        modules.add(ModuleModel(name, VfsPath.file(at), models.toArray(), deps: deps))
    }

    func database(): AnalysisDatabase {
        let db = AnalysisDatabase()
        db.setProject(ProjectModel(Cfg([]), modules.toArray()), paths)
        db.batch {
            for ((id, text) in texts) {
                db.setFileText(id, Rope(text))
            }
        }
        db
    }

    /**
     * The `macro-build` of the project at `<root>/<dir>`.
     */
    func outOf(dir: String): Path {
        root.join(dir).join(".cache").join("macro-build")
    }

    /**
     * Each package's project's `macro-build`, by the first directory under the root it is in.
     */
    func outs(db: AnalysisDatabase): (Package) -> ?Path {
        {
            pkg: Package =>
            let dir = pkg.dir(db).filePath.getOrThrow()
            var project = dir
            while (project.parent.toString() != root.toString()) {
                project = project.parent
            }
            Some(outOf(project.fileName))
        }
    }
}

func macroPackage(name: String, imports!: String = ""): String {
    "macro package ${name}\nimport std.ast.*\n${imports}public macro M(input: Tokens): Tokens { input }\n"
}

func libraryIn(results: HashMap<VfsPath, GroupResult>, dir: Path): ?Path {
    match (results.get(VfsPath.file(dir))?.library) {
        case Some(Built(library, _)) => library
        case _ => None
    }
}

@Test
class BuildPlanTest {
    @TestCase
    func eachProjectsMacroPackagesAreBuiltIntoItsOwnDirectory() {
        // arrange
        let workspace = Workspace()
        workspace.module("a", "a", [("a.ms", "ms", macroPackage("a.ms"))])
        workspace.module("b", "b", [("b.ms", "ms", macroPackage("b.ms"))])
        let db = workspace.database()

        // act
        let (results, all) = buildPlan(db, macroBuildPlan(db), workspace.outs(db), "cjc 1", PackageToolchain())

        // assert
        @Expect(all)
        @Expect(libraryIn(results, workspace.root.join("a").join("ms")),
            Some(workspace.outOf("a").join("a").join("lib-macro_a.ms${LIBRARY_SUFFIX}")))
        @Expect(libraryIn(results, workspace.root.join("b").join("ms")),
            Some(workspace.outOf("b").join("b").join("lib-macro_b.ms${LIBRARY_SUFFIX}")))
    }

    @TestCase
    func aSourcePackageOfAnotherProjectIsBuiltIntoTheImportersDirectoryToo() {
        // arrange
        let workspace = Workspace()
        workspace.module("a", "a",
            [("a.util", "util", "package a.util\npublic func f() {}\n"),
                ("a.ms", "ms", macroPackage("a.ms", imports: "import a.util.*\n"))])
        workspace.module("b", "b", [("b.ms", "ms", macroPackage("b.ms", imports: "import a.util.*\n"))], deps: ["a"])
        let db = workspace.database()
        let toolchain = PackageToolchain()

        // act
        let (_, all) = buildPlan(db, macroBuildPlan(db), workspace.outs(db), "cjc 1", toolchain)

        // assert
        @Expect(all)
        @Expect(toolchain.outputsOf(workspace.root.join("a").join("util")),
            [workspace.outOf("a").join("a").toString(), workspace.outOf("b").join("a").toString()])
    }

    @TestCase
    func twoProjectsNamingTheirModuleAndMacroPackageAlikeGetALibraryEach() {
        // arrange
        let workspace = Workspace()
        workspace.module("a", "demo", [("demo.ms", "ms", macroPackage("demo.ms"))])
        workspace.module("b", "demo", [("demo.ms", "ms", macroPackage("demo.ms"))])
        let db = workspace.database()

        // act
        let (results, _) = buildPlan(db, macroBuildPlan(db), workspace.outs(db), "cjc 1", PackageToolchain())

        // assert
        @Expect(libraryIn(results, workspace.root.join("a").join("ms")),
            Some(workspace.outOf("a").join("demo").join("lib-macro_demo.ms${LIBRARY_SUFFIX}")))
        @Expect(libraryIn(results, workspace.root.join("b").join("ms")),
            Some(workspace.outOf("b").join("demo").join("lib-macro_demo.ms${LIBRARY_SUFFIX}")))
    }

    @TestCase
    func aDirectoryAnotherServerHoldsIsLeftTheOtherBuiltAndItIsBuiltOnceFree() {
        // arrange
        let workspace = Workspace()
        workspace.module("a", "a", [("a.ms", "ms", macroPackage("a.ms"))])
        workspace.module("b", "b", [("b.ms", "ms", macroPackage("b.ms"))])
        let db = workspace.database()
        Directory.create(workspace.outOf("a"), recursive: true)
        let held = tryLockCacheDir(workspace.outOf("a")).getOrThrow()

        // act
        let (whileHeld, allWhileHeld) = buildPlan(db, macroBuildPlan(db), workspace.outs(db), "cjc 1",
            PackageToolchain())
        held.close()
        let (once, allOnce) = buildPlan(db, macroBuildPlan(db), workspace.outs(db), "cjc 1", PackageToolchain())

        // assert
        @Expect(!allWhileHeld)
        @Expect(libraryIn(whileHeld, workspace.root.join("a").join("ms")), None)
        @Expect(libraryIn(whileHeld, workspace.root.join("b").join("ms")).isSome())
        @Expect(allOnce)
        @Expect(libraryIn(once, workspace.root.join("a").join("ms")).isSome())
    }
}
