package project_model

import std.collection.*
import std.env.getTempDirectory
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import fjson.*
import loupe.db.*
import loupe.hir.{defMap, PackageRef}
import loupe.vfs.{readFiles, Vfs, VfsPath}

/**
 * A directory of its own under the temporary one, holding `files` (paths relative to it, with `/`
 * between names, and their text).
 */
func tree(files: Array<(String, String)>): VfsPath {
    let dir = Directory.createTemp(getTempDirectory())
    for ((relative, text) in files) {
        let path = relative.split("/").fold(dir) {parent, name => parent.join(name)}
        if (!exists(path.parent)) {
            Directory.create(path.parent, recursive: true)
        }
        File.writeTo(path, text.toArray())
    }
    VfsPath.file(dir)
}

func removeTree(dir: VfsPath): Unit {
    remove(dir.filePath.getOrThrow(), recursive: true)
}

/**
 * An environment with `CANGJIE_HOME` at `/sdk` and nothing else.
 */
func sdkEnv(name: String): ?String {
    if (name == "CANGJIE_HOME") {
        getTempDirectory().join("sdk").toString()
    } else {
        None
    }
}

func noEnv(_: String): ?String {
    None
}

let LINUX = Cfg([("os", "Linux"), ("arch", "x86_64"), ("backend", "cjnative")])

/**
 * Every package of `model` as `module: package=file,file`, its files relative to `dir`.
 */
func packagesOf(model: ProjectModel, dir: VfsPath): Array<String> {
    let out = ArrayList<String>()
    for (module in model.modules) {
        for (pkg in module.packages) {
            out.add("${module.name}: ${pkg.name}=${String.join(pkg.files.map {file => relative(file, dir)}, delimiter: ",")}")
        }
    }
    out.toArray()
}

@Test
class DeclaresMainTest {
    @TestCase[sample in [
        ("main(): Int64 {\n    0\n}\n", true),
        ("/** doc */\n@When[os == \"Linux\"]\nmain() {}", true),
        ("func main() {}", true),
        ("class C {\n    func main() {}\n}\n", false),
        ("let domain = 1\nlet s = \"main\"\nlet t = \"\${ { => main }() }\"\n", false),
        ("let r = #\"main\"#\n// main()\n/* main() /* main */ */\n", false),
        ("func f(x!: Int64 = main) {}", false),
        ("", false)
    ]]
    func aMainIsTheKeywordOutsideEveryBracketAndString(sample: (String, Bool)) {
        // act
        let found = declaresMain(sample[0].toArray())

        // assert
        @Expect(found, sample[1])
    }

    @TestCase
    func aTextThatIsNoUtf8DeclaresNothing() {
        // act
        let found = declaresMain("main() {}".toArray().concat([0xFFu8]))

        // assert
        @Expect(found, false)
    }
}

@Test
class PackageHeaderTest {
    @TestCase[sample in [
        ("package a.b\n", Some("a.b")),
        ("// a comment\n/* a /* nested */ one */\nmacro package m.macros\nimport x", Some("m.macros")),
        ("protected package org::a . b", Some("org::a.b")),
        ("package `type`.ä", Some("type.ä")),
        ("import std.collection.*\n", None),
        ("", None),
        ("package", None)
    ]]
    func theNameIsWhatThePackageLineSays(sample: (String, ?String)) {
        // act
        let name = packageHeader(sample[0].toArray())

        // assert
        @Expect(name, sample[1])
    }
}

@Test
class ProjectJsonTest {
    @TestCase
    func aModuleWithoutPackagesHasOnePerDirectoryNamedAsCjpmNamesThem() {
        // arrange
        let dir = tree([("libs/std/std.cj", ""), ("libs/std/collection/list.cj", ""),
            ("libs/std/collection/map.cj", ""), ("libs/std/empty/README.md", ""), ("libs/std/target/x.cj", "")])
        let json = ProjectJson(modules: [ModuleJson(name: "std", root: "libs/std")])

        // act
        let model = lowerProjectJson(json, dir, env: sdkEnv, cfg: LINUX)
        removeTree(dir)

        // assert - a module named `std` is std: none from the SDK
        @Expect(packagesOf(model, dir), [
            "std: std=libs/std/std.cj",
            "std: std.collection=libs/std/collection/list.cj,libs/std/collection/map.cj"
        ])
        @Expect(model.binaries.size, 0)
        @Expect(model.modules[0].member)
    }

    @TestCase
    func packagesListedAreAllThereIsWithTheirFilesAndHowTheyAreBuilt() {
        // arrange
        let dir = tree([("std/core/a.cj", ""), ("std/core/b.cj", ""), ("std/collection/list.cj", "")])
        let json = ProjectJson(
            cfg: HashMap<String, String>([("env", "ohos")]),
            modules: [ModuleJson(name: "std", root: "std", packages: [
                PackageJson(name: "std.core", files: ["a.cj"], noPrelude: true),
                PackageJson(name: "std.extra", dir: "std/collection")
            ], cfg: HashMap<String, String>([("os", "Windows")]))]
        )

        // act
        let model = lowerProjectJson(json, dir, env: noEnv, cfg: LINUX)
        removeTree(dir)

        // assert
        @Expect(packagesOf(model, dir), ["std: std.core=std/core/a.cj", "std: std.extra=std/collection/list.cj"])
        @Expect(model.modules[0].packages[0].noPrelude)
        @Expect(model.cfg.get("env"), Some("ohos"))
        @Expect(model.cfg.get("os"), Some("Linux"))
        @Expect(model.modules[0].cfg.flatMap {cfg => cfg.get("os")}, Some("Windows"))
        @Expect(model.modules[0].cfg.flatMap {cfg => cfg.get("env")}, Some("ohos"))
    }

    @TestCase
    func stdHasTheSourcesCangjieSrcNamesAPackagePerDirectory() {
        // arrange
        let src = tree([("std/std.cj", ""), ("std/collection/array_list.cj", ""), ("std/collection/CMakeLists.txt", "")])
        let env = {name: String => if (name == "CANGJIE_SRC") {
            src.toString()
        } else {
            sdkEnv(name)
        }}

        // act
        let model = lowerProjectJson(ProjectJson(), src, Loading(env, LINUX))
        let without = lowerProjectJson(ProjectJson(), src, Loading(sdkEnv, LINUX))
        removeTree(src)

        // assert
        let sources = model.binaries[0].sources.getOrThrow()
        @Expect(sources.dir, src.join("std"))
        @Expect(sources.packages.map {pkg => pkg.name}, ["std", "std.collection"])
        @Expect(sources.packages[1].files, [src.join("std/collection/array_list.cj")])
        @Expect(without.binaries[0].sources.isNone())
    }

    @TestCase
    func aBinaryOfTheProjectFileNamesItsSourcesRelativeToIt() {
        // arrange
        let dir = tree([("libs/stdx/stdx.cj", ""), ("libs/stdx/net/http.cj", "")])
        let json = ProjectJson(binaries: [BinaryJson(name: "stdx", paths: ["bin"], sources: "libs/stdx")])

        // act
        let model = lowerProjectJson(json, dir, Loading(sdkEnv, LINUX))
        let written = toProjectJson(model, dir)
        removeTree(dir)

        // assert
        let stdx = model.binaries[1]
        @Expect(stdx.sources.map {sources => sources.packages.map {pkg => pkg.name}}, Some(["stdx", "stdx.net"]))
        @Expect(written.binaries.getOrThrow()[1].sources, Some("libs/stdx"))
    }

    @TestCase
    func stdComesFromTheSdkAndVariablesFromTheEnvironment() {
        // arrange
        let dir = tree([("app/main.cj", "")])
        let json = ProjectJson(modules: [ModuleJson(name: "app", root: "app", deps: ["stdx"], member: false)],
            binaries: [BinaryJson(name: "stdx", paths: ["\${CANGJIE_HOME}/stdx", "\${NOWHERE}/x"])])

        // act
        let loading = Loading(sdkEnv, LINUX)
        let model = lowerProjectJson(json, dir, loading)
        removeTree(dir)

        // assert
        let sdk = VfsPath.file(getTempDirectory().join("sdk"))
        @Expect(model.binaries.map {binary => binary.name}, ["std", "stdx"])
        @Expect(model.binaries[0].paths, [sdk.join("modules/linux_x86_64_cjnative/std")])
        @Expect(model.binaries[1].paths, [sdk.join("stdx"), dir.join("\${NOWHERE}/x")])
        @Expect(loading.problems.size, 1)
        @Expect(model.modules[0].deps, ["stdx"])
        @Expect(!model.modules[0].member)
    }

    @TestCase
    func aModelWrittenOutReadsBackTheSame() {
        // arrange
        let dir = tree([("src/a.cj", ""), ("src/sub/b.cj", "")])
        let model = lowerProjectJson(ProjectJson(modules: [ModuleJson(name: "app", root: "src", deps: ["stdx"])],
            binaries: [BinaryJson(name: "stdx", paths: ["/opt/stdx"], packages: HashMap<String, String>([("stdx.a", "a.cjo")]))]),
            dir, env: sdkEnv, cfg: LINUX)

        // act
        let text = prettyProjectJson(toProjectJson(model, dir))
        let again = lowerProjectJson(fromJsonBytes<ProjectJson>(text.toArray()), dir, env: sdkEnv, cfg: hostCfg())
        removeTree(dir)

        // assert - the cfg written out wins over the host's
        @Expect(again, model)
        @Expect(text.contains("\n  \"modules\": [\n"))
        @Expect(text.contains("\"root\": \"src\""))
    }
}

@Test
class CjpmProjectTest {
    @TestCase
    func aWorkspaceIsItsMembersAndThePathDependenciesTheyReach() {
        // arrange
        let dir = tree([
            ("ws/cjpm.toml", "[workspace]\nmembers = [\"a\", \"b\"]\n" +
                "[target.x86_64-unknown-linux-gnu.bin-dependencies]\npath-option = [\"\${CANGJIE_HOME}/stdx\"]\n" +
                "[target.aarch64-apple-darwin.bin-dependencies]\npath-option = [\"/mac/stdx\"]\n"),
            ("ws/a/cjpm.toml", "[package]\nname = \"a\"\n[dependencies]\nb = { path = \"../b\" }\n" +
                "dep = { path = \"../../dep\" }\nremote = { git = \"https://example.com/r.git\" }\n"),
            ("ws/a/src/main.cj", ""),
            ("ws/a/build.cj", ""),
            ("ws/b/cjpm.toml", "[package]\nname = \"b\"\norganization = \"org\"\nsrc-dir = \"lib\"\n"),
            ("ws/b/lib/b.cj", ""),
            ("ws/b/lib/x/y/c.cj", ""),
            ("dep/cjpm.toml", "[package]\nname = \"dep\"\n"),
            ("dep/src/d.cj", ""),
            ("ws/build.cj", "main(): Int64 { 0 }")
        ])

        // act
        let load = loadCjpmProject(dir.join("ws/cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()
        removeTree(dir)

        // assert
        let model = load.model
        @Expect(packagesOf(model, dir), [
            "org::b: org::b=ws/b/lib/b.cj",
            "org::b: org::b.x.y=ws/b/lib/x/y/c.cj",
            "dep: dep=dep/src/d.cj",
            "a: a=ws/a/src/main.cj",
            "default: default=ws/a/build.cj",
            "default: default=ws/build.cj"
        ])
        @Expect(model.modules.map {module => module.member}, [true, false, true, true, true])
        @Expect(model.modules[4].root, dir.join("ws"))
        @Expect(model.modules[2].deps, ["org::b", "dep", "stdx"])
        @Expect(model.modules[1].deps, Array<String>())
        @Expect(model.binaries.map {binary => binary.name}, ["std", "stdx"])
        @Expect(load.problems.size, 1)
        @Expect(load.problems[0].contains("`remote`"))
    }

    @TestCase
    func noManifestIsNoProjectAndABrokenOneThrows() {
        // arrange
        let dir = tree([("cjpm.toml", "[package\n")])

        // act, assert
        @Expect(loadCjpmProject(dir.join("none/cjpm.toml"), env: noEnv).isNone())
        @AssertThrows[ProjectException](loadCjpmProject(dir.join("cjpm.toml"), env: noEnv))
        removeTree(dir)
    }
}

@Test
class FindProjectTest {
    @TestCase
    func aProjectFileComesBeforeTheManifest() {
        // arrange
        let dir = tree([(PROJECT_JSON, "{\"modules\": [{\"name\": \"p\", \"root\": \"src\"}]}"),
            ("cjpm.toml", "[package]\nname = \"m\"\n"), ("src/a.cj", "")])

        // act
        let load = findProject(dir, env: noEnv)
        removeTree(dir)

        // assert
        @Expect(load.source.toString(), "${PROJECT_JSON} at ${dir.join(PROJECT_JSON)}")
        @Expect(load.model.modules.map {module => module.name}, ["p"])
    }

    @TestCase
    func aBrokenProjectFileIsToldAndTheManifestTaken() {
        // arrange
        let dir = tree([(PROJECT_JSON, "{\"modules\": 1}"), ("cjpm.toml", "[package]\nname = \"m\"\n"), ("src/a.cj", "")])

        // act
        let load = findProject(dir, env: sdkEnv)
        removeTree(dir)

        // assert
        @Expect(load.model.modules.map {module => module.name}, ["m"])
        @Expect(load.problems.size, 1)
        @Expect(load.problems[0].contains(PROJECT_JSON))
    }

    @TestCase
    func looseFilesMakeAPackagePerPackageLineAndAModulePerRootPackage() {
        // arrange
        let dir = tree([("a.cj", "package app\n"), ("x/b.cj", "// b\npackage app.util"), ("x/c.cj", "package app.util\n"),
            ("y/d.cj", "main() {}"), ("z/e.cj", "macro package other.m")])

        // act
        let load = findProject(dir, env: noEnv)
        removeTree(dir)

        // assert
        @Expect(load.source.toString(), "loose files under ${dir}")
        @Expect(packagesOf(load.model, dir), [
            "app: app=a.cj", "app: app.util=x/b.cj,x/c.cj", "default: default=y/d.cj", "other: other.m=z/e.cj"
        ])
        @Expect(load.model.modules.iterator().all {module => module.root == dir})
        @Expect(load.problems.size, 1) // no CANGJIE_HOME
        // modules of one root are as many after a merge
        @Expect(packagesOf(ProjectModel.merge([load.model], LINUX), dir), packagesOf(load.model, dir))
    }

    @TestCase
    func looseFilesStopAtTheBudget() {
        // arrange
        let dir = tree([("a.cj", "package a"), ("b.cj", "package bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")])

        // act
        let load = looseProject(dir, env: sdkEnv, budget: 20)
        removeTree(dir)

        // assert
        @Expect(packagesOf(load.model, dir), ["a: a=a.cj"])
        @Expect(load.problems.size, 1)
    }

    @TestCase
    func looseFilesWithAMainEachAreAProgramEachWithTheFilesWithoutMainOfTheirDirectory() {
        // arrange
        let dir = tree([("a.cj", "let my_const = 1\nmain() {}\n"), ("b.cj", "let my_const = 2\nmain() {}\n"),
            ("util.cj", "func helper() {}\n"), ("sub/c.cj", "main() {}\n"), ("lib/d.cj", "func d() {}\n"),
            ("e.cj", "package app\nmain() {}\n")])

        // act
        let load = findProject(dir, env: noEnv)
        removeTree(dir)

        // assert
        @Expect(packagesOf(load.model, dir), [
            "app: app=e.cj", "default: default=lib/d.cj", "default: default=a.cj,util.cj",
            "default: default=b.cj,util.cj", "default: default=sub/c.cj"
        ])
        @Expect(load.model.modules.map {module => relative(module.root, dir)}, [".", ".", "a.cj", "b.cj", "sub/c.cj"])
        // the files of the project are read once
        @Expect(load.model.files().size, 6)
    }

    @TestCase
    func looseFilesWithOneMainAmongThemAreOneProgram() {
        // arrange
        let dir = tree([("a.cj", "main() {\n    helper()\n}\n"), ("b.cj", "func helper() {}\n"),
            ("x/c.cj", "let c = \"main()\"\n")])

        // act
        let load = findProject(dir, env: noEnv)
        removeTree(dir)

        // assert
        @Expect(packagesOf(load.model, dir), ["default: default=a.cj,b.cj,x/c.cj"])
        @Expect(load.model.modules.iterator().all {module => module.root == dir})
    }

    @TestCase
    func aMainPastTheHeaderMakesAProgram() {
        // arrange
        let comment = "// ${"x" * HEADER_BYTES}\n"
        let dir = tree([("a.cj", "${comment}main() {}\n"), ("b.cj", "main() {}\n")])

        // act
        let load = findProject(dir, env: noEnv)
        removeTree(dir)

        // assert
        @Expect(packagesOf(load.model, dir), ["default: default=a.cj", "default: default=b.cj"])
    }

    @TestCase
    func programsOfOneDirectoryRedefineNothingOfEachOther() {
        // arrange
        let dir = tree([("a.cj", "let my_const = 1\nmain() {}\n"), ("b.cj", "let my_const = 2\nmain() {}\n"),
            ("util.cj", "func helper() {}\n")])
        let load = findProject(dir, env: noEnv)
        let db = AnalysisDatabase()
        let vfs = Vfs()
        db.setProject(load.model, vfs.paths)
        for ((path, text) in readFiles(load.model.files()).files) {
            vfs.setFileContents(path, text)
        }
        db.applyChanges(vfs, vfs.takeChanges())
        removeTree(dir)

        // act
        let packages = db.project().getOrThrow().modules(db).map {module => module.packages(db)[0]}
        let maps = packages.map {pkg => defMap(db, PackageRef.Source(pkg))}

        // assert
        @Expect(maps.size, 2)
        @Expect(maps.map {map => map.errors.size}, [0, 0])
        @Expect(maps.map {map => map.names.contains("helper")}, [true, true])
    }

    @TestCase
    func aBuildScriptIsAModuleOfItsOwnWithItsScriptDependencies() {
        // arrange
        let dir = tree([
            ("cjpm.toml", "[package]\nname = \"app\"\n[script-dependencies]\ntool = { path = \"tool\" }\n" +
                "remote = \"1.0.0\"\n"),
            ("build.cj", "main(): Int64 { 0 }"),
            ("src/main.cj", ""),
            ("tool/cjpm.toml", "[package]\nname = \"tool\"\n"),
            ("tool/src/t.cj", "")
        ])

        // act
        let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()
        removeTree(dir)

        // assert - the script sees `tool`, the module it builds does not
        let model = load.model
        @Expect(packagesOf(model, dir), ["app: app=src/main.cj", "tool: tool=tool/src/t.cj", "default: default=build.cj"])
        @Expect(model.modules[0].deps, Array<String>())
        @Expect(model.modules[2].deps, ["tool"])
        @Expect(model.modules[2].root, dir)
        @Expect(!model.modules[1].member)
        @Expect(load.problems.size, 1)
        @Expect(load.problems[0].contains("`remote`"))
    }

    @TestCase
    func aBuildScriptAmongTheSourcesIsNoneOfThem() {
        // arrange
        let dir = tree([
            ("cjpm.toml", "[package]\nname = \"app\"\nsrc-dir = \".\"\n"),
            ("build.cj", "main(): Int64 { 0 }"),
            ("main.cj", "package app"),
            ("util/build.cj", "package app.util")
        ])

        // act
        let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()
        removeTree(dir)

        // assert - only the script beside the manifest is left out, into a module of its own
        @Expect(packagesOf(load.model, dir), ["app: app=main.cj", "app: app.util=util/build.cj", "default: default=build.cj"])
        @Expect(load.model.modules.map {module => module.root}, [dir, dir])
    }
}
