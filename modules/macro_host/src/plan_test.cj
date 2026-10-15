package macro_host

import std.collection.*
import std.env.getTempDirectory
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.*
import loupe.hir.macroBuildPlan
import loupe.vfs.{FileId, PathInterner, VfsPath}
import platform.sharedLibrarySuffix
import rope.Rope

/**
 * A `cjc` that writes what a build of a package writes last, the package named by the directory of its sources; and
 * the directory each build wrote to.
 */
class PlanToolchain <: Toolchain {
    let calls = ArrayList<Array<String>>()

    PlanToolchain(private let names: HashMap<String, String>) {}

    public func compile(arguments: Array<String>): (Int64, String) {
        calls.add(arguments)
        let name = names[arguments[1]]
        let out = Path(argumentOf(arguments, "--output-dir=").getOrThrow())
        let file = if (arguments.contains("--compile-macro")) {
            "lib-macro_${name}${sharedLibrarySuffix()}"
        } else {
            "lib${name}.a"
        }
        File.writeTo(out.join(file), [])
        (0, "")
    }

    /**
     * Where each build of the package of sources `dir` wrote.
     */
    func outputsOf(dir: Path): Array<String> {
        calls.toArray().filter {call => call[1] == spelled(dir)}.map {
            call => argumentOf(call, "--output-dir=").getOrThrow()
        }
    }
}

/**
 * `path` as the analysis spells it (`VfsPath.file`), as a build is given the directory of a package's sources.
 */
func spelled(path: Path): String {
    VfsPath.file(path).filePath.getOrThrow().toString()
}

func argumentOf(arguments: Array<String>, prefix: String): ?String {
    arguments.iterator().filter {a => a.startsWith(prefix)}.next().map {a => a[prefix.size..]}
}

/**
 * Projects in one workspace, each a directory under `root` holding one module, whose packages are a directory of one
 * file each; and where each project's macros are built, `<project>/.cache/macro-build`, as its server's directory
 * would have it.
 */
class Projects {
    let root = Directory.createTemp(getTempDirectory())
    private let paths = PathInterner()
    private let modules = ArrayList<ModuleModel>()
    private let texts = ArrayList<(FileId, String)>()
    // by the directory of its sources as the analysis spells it, which a build is given
    let names = HashMap<String, String>()
    private let projects = ArrayList<String>()
    // that of the last build: a package is an entity of one database
    private var built: ?AnalysisDatabase = None

    /**
     * The module `name` of the project at `<root>/<project>`, with `packages`, each its name, its directory and its
     * text.
     */
    func module(project: String, name: String, packages: Array<(String, String, String)>, deps!: Array<String> = []):
        Projects {
        let at = root.join(project)
        if (!projects.contains(project)) {
            projects.add(project)
        }
        let models = ArrayList<PackageModel>()
        for ((pkg, dir, text) in packages) {
            let file = VfsPath.file(at.join(dir).join("${dir}.cj"))
            texts.add((paths.intern(file), text))
            names[spelled(at.join(dir))] = pkg
            models.add(PackageModel(pkg, VfsPath.file(at.join(dir)), [file]))
        }
        modules.add(ModuleModel(name, VfsPath.file(at), models.toArray(), deps: deps))
        this
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

    func outOf(project: String): Path {
        root.join(project).join(".cache").join("macro-build")
    }

    /**
     * The directory the macros of a package are built into: its project's. Through `VfsPath`, which spells a path
     * as the analysis does: a drive, or a short name of Windows, as `root` may not.
     */
    func outs(db: AnalysisDatabase): (Package) -> ?Path {
        {
            pkg: Package => projects.iterator().filter {
                project => pkg.dir(db).isUnder(VfsPath.file(root.join(project)))
            }.next().map {project => outOf(project)}
        }
    }

    func build(toolchain!: PlanToolchain = PlanToolchain(names)): BuiltPlan {
        let db = database()
        built = db
        buildPlan(db, macroBuildPlan(db), outs(db), "cjc 1", toolchain)
    }

    /**
     * The library the macro package of sources `<root>/<project>/<dir>` got in the last build.
     */
    func libraryOf(result: BuiltPlan, project: String, dir: String): ?Path {
        let db = built.getOrThrow()
        let wanted = VfsPath.file(root.join(project).join(dir))
        for ((pkg, library) in result.libraries) {
            if (pkg.dir(db) == wanted && let Built(path, _) <- library) {
                return path
            }
        }
        None
    }
}

func macroPackage(name: String, imports!: String = ""): String {
    "macro package ${name}\n${imports}import std.ast.*\npublic macro M(input: Tokens): Tokens { input }\n"
}

func libraryIn(out: Path, module: String, pkg: String): ?Path {
    out.join(module).join("lib-macro_${pkg}${sharedLibrarySuffix()}")
}

@Test
class BuildPlanTest {
    @TestCase
    func eachProjectsMacroPackagesAreBuiltIntoItsOwnDirectory() {
        // arrange
        let projects = Projects().module("a", "a", [("a.ms", "ms", macroPackage("a.ms"))]).module("b", "b",
            [("b.ms", "ms", macroPackage("b.ms"))])

        // act
        let built = projects.build()

        // assert
        @Expect(built.held.size, 0)
        @Expect(projects.libraryOf(built, "a", "ms"), libraryIn(projects.outOf("a"), "a", "a.ms"))
        @Expect(projects.libraryOf(built, "b", "ms"), libraryIn(projects.outOf("b"), "b", "b.ms"))
    }

    @TestCase
    func aMacroPackagesDirectoryDoesNotMoveWhenTheModulesAreReordered() {
        // arrange
        let first = Projects()
        first.module("a", "a", [("a.ms", "ms", macroPackage("a.ms"))]).module("b", "b",
            [("b.ms", "ms", macroPackage("b.ms"))])
        let reordered = Projects()
        reordered.module("b", "b", [("b.ms", "ms", macroPackage("b.ms"))]).module("a", "a",
            [("a.ms", "ms", macroPackage("a.ms"))])

        // act
        let before = first.build()
        let after = reordered.build()

        // assert
        @Expect(first.libraryOf(before, "b", "ms"), libraryIn(first.outOf("b"), "b", "b.ms"))
        @Expect(reordered.libraryOf(after, "a", "ms"), libraryIn(reordered.outOf("a"), "a", "a.ms"))
    }

    @TestCase
    func aSourcePackageOfAnotherProjectIsBuiltIntoTheImportersDirectoryToo() {
        // arrange
        let projects = Projects().module("a", "a", [("a.util", "util", "package a.util\npublic func f() {}\n"),
            ("a.ms", "ms", macroPackage("a.ms", imports: "import a.util.*\n"))]).module("b", "b",
                [("b.ms", "ms", macroPackage("b.ms", imports: "import a.util.*\n"))], deps: ["a"])
        let toolchain = PlanToolchain(projects.names)

        // act
        let built = projects.build(toolchain: toolchain)

        // assert
        @Expect(toolchain.outputsOf(projects.root.join("a").join("util")),
            [projects.outOf("a").join("a").toString(), projects.outOf("b").join("a").toString()])
        @Expect(projects.libraryOf(built, "b", "ms"), libraryIn(projects.outOf("b"), "b", "b.ms"))
    }

    @TestCase
    func twoProjectsNamingTheirModuleAndMacroPackageAlikeGetALibraryEach() {
        // arrange
        let projects = Projects().module("a", "demo", [("demo.ms", "ms", macroPackage("demo.ms"))]).module("b", "demo",
            [("demo.ms", "ms", macroPackage("demo.ms"))])

        // act
        let built = projects.build()

        // assert
        @Expect(built.libraries.size, 2)
        @Expect(projects.libraryOf(built, "a", "ms"), libraryIn(projects.outOf("a"), "demo", "demo.ms"))
        @Expect(projects.libraryOf(built, "b", "ms"), libraryIn(projects.outOf("b"), "demo", "demo.ms"))
    }

    @TestCase
    func aDirectoryAnotherServerHoldsIsLeftAndTheOtherProjectsBuilt() {
        // arrange
        let projects = Projects().module("a", "a", [("a.ms", "ms", macroPackage("a.ms"))]).module("b", "b",
            [("b.ms", "ms", macroPackage("b.ms"))])
        let held = tryLockCacheDir(projects.outOf("a")).getOrThrow()

        // act
        let built = try {
            projects.build()
        } finally {
            held.close()
        }

        // assert
        @Expect(built.held, [projects.outOf("a")])
        @Expect(projects.libraryOf(built, "a", "ms"), None)
        @Expect(projects.libraryOf(built, "b", "ms"), libraryIn(projects.outOf("b"), "b", "b.ms"))
    }
}
