package project_model

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import fjson.*
import loupe.{definitionAt, diagnostics}
import loupe.db.*
import loupe.vfs.{readFiles, Vfs, VfsPath}

let MACOS =
    Cfg(
        [
            ("os", "macOS"),
            ("arch", "aarch64"),
            ("env", ""),
            ("backend", "cjnative"),
            ("test", "true")
        ]
    )

let WINDOWS =
    Cfg(
        [
            ("os", "Windows"),
            ("arch", "x86_64"),
            ("env", "gnu"),
            ("backend", "cjnative"),
            ("test", "true")
        ]
    )

/**
 * A workspace of a multiplatform module `plat`, its sets `common` → `posix` → `linux` or
 * `darwin`, and `windows`, as cjpm 1.3.0-alpha.20261002 builds it, and a module `app` using it.
 */
func platWorkspace(): VfsPath {
    tree(
        [
            ("cjpm.toml", "[workspace]\nmembers = [\"plat\", \"app\"]\n"),
            (
                "plat/cjpm.toml",
                #"
            [package]
            name = "plat"
            [profile]
            experimental = true
            [[feature]]
            name = "user.plat.posix"
            mapping = []
            [[feature]]
            name = "os.linux"
            mapping = ["user.plat.posix"]
            [[feature]]
            name = "os.darwin"
            mapping = ["user.plat.posix"]
            [[source-set]]
            name = "common"
            src-dir = "./src/common"
            features = []
            [[source-set]]
            name = "posix"
            src-dir = "./src/posix"
            features = ["user.plat.posix"]
            [[source-set]]
            name = "linux"
            src-dir = "./src/linux"
            features = ["user.plat.posix", "os.linux"]
            [[source-set]]
            name = "darwin"
            src-dir = "./src/darwin"
            features = ["user.plat.posix", "os.darwin"]
            [[source-set]]
            name = "windows"
            src-dir = "./src/windows"
            features = ["os.windows"]
            "#
            ),
            (
                "plat/src/common/plat.cj",
                "@NonProduct\nfeatures {}\npackage plat\n\npublic common func separator(): Rune\n\n" +
                    "public common class Host {\n    public common init()\n    public common func name(): String\n}\n"
            ),
            (
                "plat/src/common/util/util.cj",
                "@NonProduct\nfeatures {}\npackage plat.util\n\npublic func helper() {}\n"
            ),
            (
                "plat/src/posix/posix.cj",
                "@NonProduct\nfeatures { user.plat.posix }\npackage plat\n\npublic specific func separator(): Rune { r'/' }\n"
            ),
            (
                "plat/src/linux/linux.cj",
                "features { user.plat.posix, os.linux }\npackage plat\n\npublic specific class Host {\n" +
                    "    public specific init() {}\n    public specific func name(): String { \"linux\" }\n}\n"
            ),
            (
                "plat/src/darwin/darwin.cj",
                "features { user.plat.posix, os.darwin }\npackage plat\n\npublic specific class Host {\n" +
                    "    public specific init() {}\n    public specific func name(): String { \"darwin\" }\n}\n"
            ),
            (
                "plat/src/windows/windows.cj",
                "features { os.windows }\npackage plat\n\npublic specific func separator(): Rune { r'\\\\' }\n\n" +
                    "public specific class Host {\n    public specific init() {}\n" +
                    "    public specific func name(): String { \"windows\" }\n}\n"
            ),
            (
                "app/cjpm.toml",
                "[package]\nname = \"app\"\n[dependencies]\nplat = { path = \"../plat\" }\n"
            ),
            (
                "app/src/main.cj",
                "package app\n\nimport plat.*\n\nmain(): Int64 {\n    println(Host().name())\n    0\n}\n"
            )
        ]
    )
}

/**
 * The inactive files of every module of `model` as `module: file`, relative to `dir`.
 */
func inactiveOf(model: ProjectModel, dir: VfsPath): Array<String> {
    model.modules |>
        flatMap {
            module: ModuleModel =>
            module.inactive.map { file => "${module.name}: ${relative(file.path, dir)}" }
        } |>
        collectArray
}

@Test
class SourceSetChainTest {
    @TestCase
    func theHostsFeatureMappedThroughFeaturesPicksTheChain() {
        // arrange
        let sets =
            [
                SourceSet(name: "common", srcDir: "common", featureNames: []),
                SourceSet(
                    name: "linux",
                    srcDir: "linux",
                    featureNames: ["user.p.posix", "os.linux"]
                ),
                SourceSet(name: "posix", srcDir: "posix", featureNames: ["user.p.posix"]),
                SourceSet(name: "windows", srcDir: "windows", featureNames: ["os.windows"])
            ]
        let features =
            [
                Feature(name: "user.p.posix", mapping: []),
                Feature(name: "os.linux", mapping: ["user.p.posix"])
            ]

        // act
        let picked = sourceSetChain(sets, features, LINUX)

        // assert
        @Expect(picked.chain.map {set => set.label}, ["common", "posix", "linux"])
        @Expect(picked.left.map {left => left[1]},
            ["source set `windows` needs os.windows, which the target does not enable (it enables os.linux, user.p.posix)"])
        @Expect(picked.problems.size, 0)
    }

    @TestCase
    func twoSetsOfNoCommonParentLeaveTheLaterOutAndSaySo() {
        // arrange
        let sets =
            [
                SourceSet(srcDir: "common", featureNames: []),
                SourceSet(srcDir: "a", featureNames: ["user.m.a"]),
                SourceSet(srcDir: "b", featureNames: ["user.m.b"])
            ]
        let features = [Feature(name: "os.linux", mapping: ["user.m.a", "user.m.b"])]

        // act
        let picked = sourceSetChain(sets, features, LINUX)

        // assert - as cjpm, which rejects the build
        @Expect(picked.chain.map {set => set.label}, ["common", "a"])
        @Expect(picked.left.map {left => left[1]}, ["source set `b` is not on the chain of `common`, `a` the target takes"])
        @Expect(picked.problems.size, 1)
        @Expect(picked.problems[0].contains("without common parent source set"))
    }
}

@Test
class CjpmSourceSetTest {
    @TestCase
    func aMultiplatformPackageIsTheFilesOfTheChainAndTheRestInactive() {
        // arrange
        let dir = platWorkspace()

        // act
        let linux = loadCjpmProject(dir.join("cjpm.toml"), env: noEnv, cfg: LINUX).getOrThrow()
        let macos = loadCjpmProject(dir.join("cjpm.toml"), env: noEnv, cfg: MACOS).getOrThrow()
        let windows = loadCjpmProject(dir.join("cjpm.toml"), env: noEnv, cfg: WINDOWS).getOrThrow()
        removeTree(dir)

        // assert
        @Expect(packagesOf(linux.model, dir), [
            "plat: plat=plat/src/common/plat.cj,plat/src/posix/posix.cj,plat/src/linux/linux.cj",
            "plat: plat.util=plat/src/common/util/util.cj",
            "app: app=app/src/main.cj"
        ])
        @Expect(linux.model.modules[0].root, dir.join("plat/src/common"))
        @Expect(linux.model.modules[0].packages[0].dir, dir.join("plat/src/common"))
        @Expect(inactiveOf(linux.model, dir), ["plat: plat/src/darwin/darwin.cj", "plat: plat/src/windows/windows.cj"])
        @Expect(linux.model.modules[0].inactive[1].reason,
            "source set `windows` needs os.windows, which the target does not enable (it enables os.linux, user.plat.posix)")
        @Expect(packagesOf(macos.model, dir)[0],
            "plat: plat=plat/src/common/plat.cj,plat/src/posix/posix.cj,plat/src/darwin/darwin.cj")
        @Expect(packagesOf(windows.model, dir)[0], "plat: plat=plat/src/common/plat.cj,plat/src/windows/windows.cj")
        @Expect(inactiveOf(windows.model, dir),
            ["plat: plat/src/posix/posix.cj", "plat: plat/src/linux/linux.cj", "plat: plat/src/darwin/darwin.cj"])
        @Expect(linux.problems.size, 1) // no SDK
    }

    @TestCase
    func aFeatureDeclaredByNamesMapsNothingAsInCjpm() {
        // arrange
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        #"
                [package]
                name = "m"
                [profile]
                experimental = true
                [[feature]]
                names = ["user.m.x", "user.m.posix"]
                mapping = ["user.m.posix"]
                [[feature]]
                name = "os.linux"
                mapping = ["user.m.x"]
                [[source-set]]
                name = "common"
                src-dir = "./src/common"
                features = []
                [[source-set]]
                name = "x"
                src-dir = "./src/x"
                features = ["user.m.x"]
                [[source-set]]
                name = "posix"
                src-dir = "./src/posix"
                features = ["user.m.posix"]
                "#
                    ),
                    ("src/common/a.cj", "@NonProduct\nfeatures {}\npackage m\n"),
                    ("src/x/b.cj", "features { user.m.x }\npackage m\n"),
                    ("src/posix/c.cj", "features { user.m.posix }\npackage m\n")
                ]
            )

        // act
        let model =
            loadCjpmProject(dir.join("cjpm.toml"), env: noEnv, cfg: LINUX).getOrThrow().model
        removeTree(dir)

        // assert - `user.m.x` mapping no `user.m.posix`, the chain cjpm builds
        @Expect(packagesOf(model, dir), ["m: m=src/common/a.cj,src/x/b.cj"])
        @Expect(model.modules[0].inactive.map {file => file.reason},
            ["source set `posix` needs user.m.posix, which the target does not enable (it enables os.linux, user.m.x)"])
    }

    @TestCase
    func anAlwaysEnabledFeatureAndThoseItMapsTakeTheirSet() {
        // arrange
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        #"
                [package]
                name = "m"
                always-enabled-features = ["user.m.nightly"]
                [profile]
                experimental = true
                [[feature]]
                name = "user.m.nightly"
                mapping = ["user.m.x11"]
                [[feature]]
                name = "user.m.x11"
                [[source-set]]
                name = "common"
                src-dir = "./src/common"
                features = []
                [[source-set]]
                name = "nightly"
                src-dir = "./src/nightly"
                features = ["user.m.nightly", "user.m.x11"]
                "#
                    ),
                    ("src/common/a.cj", "@NonProduct\nfeatures {}\npackage m\n"),
                    ("src/nightly/b.cj", "features { user.m.nightly, user.m.x11 }\npackage m\n")
                ]
            )

        // act
        let model =
            loadCjpmProject(dir.join("cjpm.toml"), env: noEnv, cfg: LINUX).getOrThrow().model
        removeTree(dir)

        // assert - as cjpm, which builds `nightly` on every target
        @Expect(packagesOf(model, dir), ["m: m=src/common/a.cj,src/nightly/b.cj"])
        @Expect(model.modules[0].inactive.size, 0)
    }

    @TestCase
    func aDependentModulesReferenceToACommonClassGoesToItsSpecificOnTheHost() {
        // arrange
        let dir = platWorkspace()
        let load = loadCjpmProject(dir.join("cjpm.toml"), env: noEnv, cfg: LINUX).getOrThrow()
        let db = AnalysisDatabase()
        let vfs = Vfs()
        db.setProject(load.model, vfs.paths)
        for ((path, text) in readFiles(load.model.files()).files) {
            vfs.setFileContents(path, text)
        }
        // an inactive file opened
        let windows = dir.join("plat/src/windows/windows.cj")
        for ((path, text) in readFiles([windows]).files) {
            vfs.setFileContents(path, text)
        }
        db.applyChanges(vfs, vfs.takeChanges())
        removeTree(dir)
        let mainFile = vfs.paths.lookup(dir.join("app/src/main.cj")).getOrThrow()
        let offset = "package app\n\nimport plat.*\n\nmain(): Int64 {\n    println(".size

        // act
        let targets = definitionAt(db, mainFile, offset)
        let inactive = diagnostics(db, vfs.paths.lookup(windows).getOrThrow())

        // assert - the specific, then the common
        @Expect(targets.map {target => vfs.paths.path(target.fileId).name}, ["linux.cj", "plat.cj"])
        @Expect(inactive.size, 1)
        @Expect(inactive[0].message.startsWith("code is inactive: source set `windows` needs os.windows"))
        for (path in load.model.files()) {
            let fileId = vfs.paths.lookup(path).getOrThrow()
            @Expect(diagnostics(db, fileId).map {one => one.message}, Array<String>())
        }
    }

    @TestCase
    func theProjectWrittenOutListsTheChainAndTheFilesLeftOutAndReadsBackTheSame() {
        // arrange
        let dir = platWorkspace()
        let model =
            loadCjpmProject(dir.join("cjpm.toml"), env: noEnv, cfg: LINUX).getOrThrow().model

        // act
        let text = prettyProjectJson(toProjectJson(model, dir))
        let again =
            lowerProjectJson(
                fromJsonBytes<ProjectJson>(text.toArray()),
                dir,
                env: noEnv,
                cfg: LINUX
            )
        removeTree(dir)

        // assert
        @Expect(again.modules, model.modules)
        @Expect(text.contains("\"../posix/posix.cj\""))
        @Expect(text.contains("\"../linux/linux.cj\""))
        @Expect(text.contains("\"file\": \"plat/src/windows/windows.cj\""))
    }
}
