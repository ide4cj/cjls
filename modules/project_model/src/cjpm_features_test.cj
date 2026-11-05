package project_model

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.definitionAt
import loupe.db.*
import loupe.fixture.FixtureException
import loupe.vfs.{Vfs, VfsPath, readFiles}

/**
 * A module declaring one optional feature and a common-to-specialized source chain.
 */
func featureModule(
    name: String,
    mapping!: String = "",
    always!: String = "",
    deps!: String = ""
): String {
    """
    [package]
    name = "${name}"
    always-enabled-features = [${always}]
    [profile]
    experimental = true
    [[feature]]
    name = "user.${name}.fast"
    mapping = [${mapping}]
    [[source-set]]
    src-dir = "src/common"
    features = []
    [[source-set]]
    src-dir = "src/fast"
    features = ["user.${name}.fast"]
    [dependencies]
    ${deps}
    """
}

/**
 * The dependency is listed first to expose lowering that fixes its chain before the consumer.
 */
func featureWorkspace(): VfsPath {
    tree(
        [
            ("cjpm.toml", "[workspace]\nmembers = [\"dep\", \"app\"]\n"),
            (
                "app/cjpm.toml",
                featureModule(
                    "app",
                    always: "\"user.app.fast\"",
                    mapping: "\"user.dep.fast\"",
                    deps: "dep = {path = \"../dep\"}"
                )
            ),
            (
                "app/src/common/a.cj",
                "@NonProduct\nfeatures {}\npackage app\nimport dep.*\npublic func use(): Int64 { chosen() }\n"
            ),
            ("app/src/fast/a.cj", "features { user.app.fast }\npackage app\n"),
            ("dep/cjpm.toml", featureModule("dep")),
            (
                "dep/src/common/a.cj",
                "@NonProduct\nfeatures {}\npackage dep\npublic common func chosen(): Int64\n"
            ),
            (
                "dep/src/fast/a.cj",
                "features { user.dep.fast }\npackage dep\npublic specific func chosen(): Int64 { 1 }\n"
            )
        ]
    )
}

@Test
class CjpmFeaturePropagationTest {
    @TestCase
    func aLaterConsumerEnablesAnAlreadyDiscoveredWorkspaceDependency(): Unit {
        // arrange
        let dir = featureWorkspace()

        // act
        let load =
            loadCjpmProject(dir.join("cjpm.toml"), env: noEnv, cfg: LINUX) ??
                throw FixtureException("expected cjpm project")
        removeTree(dir)

        // assert
        @Expect(packagesOf(load.model, dir), [
            "dep: dep=dep/src/common/a.cj,dep/src/fast/a.cj",
            "app: app=app/src/common/a.cj,app/src/fast/a.cj"
        ])
        @Expect(inactiveOf(load.model, dir), Array<String>())
    }

    @TestCase
    func theReferenceInTheConsumerFindsTheEnabledSpecific(): Unit {
        // arrange
        let dir = featureWorkspace()
        let load =
            loadCjpmProject(dir.join("cjpm.toml"), env: noEnv, cfg: LINUX) ??
                throw FixtureException("expected fixture value")
        let db = AnalysisDatabase()
        let vfs = Vfs()
        db.setProject(load.model, vfs.paths)
        for ((path, text) in readFiles(load.model.files()).files) {
            vfs.setFileContents(path, text)
        }
        db.applyChanges(vfs, vfs.takeChanges())
        let file =
            vfs.paths.lookup(dir.join("app/src/common/a.cj")) ??
                throw FixtureException("expected fixture value")
        let offset =
            "@NonProduct\nfeatures {}\npackage app\nimport dep.*\npublic func use(): Int64 { ".size
        // act
        let targets = definitionAt(db, file, offset)
        removeTree(dir)

        // assert
        @Expect(targets.map { target => relative(vfs.paths.path(target.fileId), dir) }, ["dep/src/fast/a.cj", "dep/src/common/a.cj"])
    }
}

/**
 * Two nested source sets whose selection is independent of traversal order.
 */
func featureFiles(name: String, manifest: String): Array<(String, String)> {
    [
        ("${name}/cjpm.toml", manifest),
        ("${name}/src/common/a.cj", "features {}\npackage ${name}\n"),
        ("${name}/src/fast/a.cj", "features { user.${name}.fast }\npackage ${name}\n")
    ]
}

@Test
class CjpmFeatureConfigurationTest {
    @TestCase
    func transitiveMappingsReachAFixedPointEvenWithFeatureCycles(): Unit {
        // arrange
        let files = ArrayList<(String, String)>(
            [("cjpm.toml", "[workspace]\nmembers = [\"leaf\", \"bridge\", \"app\"]\n")]
        )
        files.add(
            all: featureFiles(
                "app",
                featureModule(
                    "app",
                    always: "\"user.app.fast\"",
                    mapping: "\"user.bridge.fast\"",
                    deps: "bridge = {path = \"../bridge\"}"
                )
            )
        )
        files.add(
            all: featureFiles(
                "bridge",
                featureModule(
                    "bridge",
                    mapping: "\"user.leaf.fast\"",
                    deps: "leaf = {path = \"../leaf\"}"
                )
            )
        )
        files.add(all: featureFiles("leaf", featureModule("leaf", mapping: "\"user.app.fast\"")))
        let dir = tree(files.toArray())

        // act
        let load =
            loadCjpmProject(dir.join("cjpm.toml"), env: noEnv, cfg: LINUX) ??
                throw FixtureException("expected cjpm project")
        removeTree(dir)

        // assert
        @Expect(inactiveOf(load.model, dir), Array<String>())
        @Expect(load.problems.filter { problem => problem.contains("feature") }, Array<String>())
    }

    @TestCase
    func twoConsumersUnifyTheirRequestsInASharedDependency(): Unit {
        // arrange
        let files = ArrayList<(String, String)>(
            [("cjpm.toml", "[workspace]\nmembers = [\"left\", \"right\"]\n")]
        )
        files.add(
            all: featureFiles(
                "left",
                featureModule(
                    "left",
                    always: "\"user.dep.fast\"",
                    deps: "dep = {path = \"../dep\"}"
                )
            )
        )
        files.add(
            all: featureFiles(
                "right",
                featureModule(
                    "right",
                    always: "\"user.dep.extra\"",
                    deps: "dep = {path = \"../dep\"}"
                )
            )
        )
        let extra =
            "\n[[feature]]\nname = \"user.dep.extra\"\n[[source-set]]\nsrc-dir = \"src/both\"\nfeatures = [\"user.dep.fast\", \"user.dep.extra\"]\n"
        files.add(all: featureFiles("dep", "${featureModule("dep")}${extra}"))
        files.add(
            ("dep/src/both/a.cj", "features { user.dep.fast, user.dep.extra }\npackage dep\n")
        )
        let dir = tree(files.toArray())

        // act
        let load =
            loadCjpmProject(dir.join("cjpm.toml"), env: noEnv, cfg: LINUX) ??
                throw FixtureException("expected cjpm project")
        removeTree(dir)

        // assert
        let dep = featureModuleOf(load.model, "dep")
        @Expect(dep.packages[0].files.map { path => relative(path, dir) },
            ["dep/src/common/a.cj", "dep/src/fast/a.cj", "dep/src/both/a.cj"])
        @Expect(dep.inactive.size, 0)
    }

    @TestCase
    func testOnlyFeatureRequestsUseTheExplicitBuildConfiguration(): Unit {
        // arrange
        let files = ArrayList<(String, String)>(
            [
                (
                    "cjpm.toml",
                    "[package]\nname = \"app\"\n[dependencies]\ndep = {path = \"dep\"}\n[test-dependencies]\nchecks = {path = \"checks\"}\n"
                ),
                ("src/a.cj", "package app\n")
            ]
        )
        files.add(all: featureFiles("dep", featureModule("dep")))
        files.add(all: featureFiles("checks", featureModule("checks", always: "\"user.dep.fast\"")))
        let dir = tree(files.toArray())

        // act
        let build = findProject(dir, env: noEnv, cfg: LINUX)
        let test = findProject(dir, env: noEnv, cfg: LINUX, includeTestFeatures: true)
        removeTree(dir)

        // assert
        let buildDep = featureModuleOf(build.model, "dep")
        let testDep = featureModuleOf(test.model, "dep")
        @Expect(buildDep.inactive.size, 1)
        @Expect(testDep.inactive.size, 0)
        @Expect(build.model.modules.iterator().any { module => module.name == "checks" })
        @Expect(featureModuleOf(test.model, "app").testDeps, ["checks"])
    }

    @TestCase
    func explicitFlagsAndDeductionSwitchReachRootLinkedAndFoundProjects(): Unit {
        // arrange
        let mapping = "\n[[feature]]\nname = \"os.linux\"\nmapping = [\"user.dep.fast\"]\n"
        let files = featureFiles("dep", "${featureModule("dep")}${mapping}")
        let dir = tree(files)
        let depDir = dir.join("dep")

        // act
        let implicit = findProject(depDir, env: noEnv, cfg: LINUX)
        let none = findProject(depDir, env: noEnv, cfg: LINUX, deduceFeatures: false)
        let roots = findProjects(
            [depDir],
            [],
            env: noEnv,
            cfg: LINUX,
            enabledFeatures: [" user . dep . fast "],
            deduceFeatures: false
        )
        let linked = findProjects(
            [dir],
            [depDir],
            env: noEnv,
            cfg: LINUX,
            enabledFeatures: ["user.dep.fast"],
            deduceFeatures: false
        )
        let found = findProjects(
            [],
            [],
            env: noEnv,
            cfg: LINUX,
            found: [depDir],
            enabledFeatures: ["user.dep.fast"],
            deduceFeatures: false
        )
        removeTree(dir)

        // assert
        @Expect(implicit.model.modules[0].inactive.size, 0)
        @Expect(none.model.modules[0].inactive.size, 1)
        for (load in roots.concat(linked).concat(found)) {
            @Expect(load.model.modules[0].inactive.size, 0)
        }
    }

    @TestCase
    func ordinaryFeatureRequestsAndCliFlagsDoNotEnterScriptDependencies(): Unit {
        // arrange
        let files = ArrayList<(String, String)>(
            [
                (
                    "cjpm.toml",
                    "[package]\nname = \"app\"\nalways-enabled-features = [\"user.dep.fast\"]\n[dependencies]\ndep = {path = \"dep\"}\n[script-dependencies]\ndep = {path = \"dep\"}\n"
                ),
                ("src/a.cj", "package app\n"),
                ("build.cj", "main(): Int64 { 0 }\n")
            ]
        )
        files.add(all: featureFiles("dep", featureModule("dep")))
        let dir = tree(files.toArray())

        // act
        let load =
            loadCjpmProject(
                dir.join("cjpm.toml"),
                env: noEnv,
                cfg: LINUX,
                enabledFeatures: ["user.dep.fast"]
            ) ??
                throw FixtureException("expected fixture value")
        removeTree(dir)

        // assert
        let deps = load.model.modules.filter { module => module.name == "dep" }
        @Expect(deps.size, 2)
        @Expect(deps[0].resolutionScope, "")
        @Expect(deps[0].inactive.size, 0)
        @Expect(deps[1].resolutionScope.isEmpty(), false)
        @Expect(deps[1].inactive.size, 1)
    }

    @TestCase
    func scriptMappingsUseHostDeductionAndPropagateWithinTheirOwnGraph(): Unit {
        // arrange
        let files = ArrayList<(String, String)>(
            [
                (
                    "cjpm.toml",
                    "[package]\nname = \"app\"\n[script-dependencies]\nbridge = {path = \"bridge\"}\n"
                ),
                ("src/a.cj", "package app\n"),
                ("build.cj", "main(): Int64 { 0 }\n")
            ]
        )
        let host = hostFeature(hostCfg()) ?? throw FixtureException("expected fixture value")
        let mapping = "\n[[feature]]\nname = \"${host}\"\nmapping = [\"user.bridge.fast\"]\n"
        let bridge = featureModule(
            "bridge",
            mapping: "\"user.dep.fast\"",
            deps: "dep = {path = \"../dep\"}"
        )
        files.add(all: featureFiles("bridge", "${bridge}${mapping}"))
        files.add(all: featureFiles("dep", featureModule("dep")))
        let dir = tree(files.toArray())

        // act
        let load =
            loadCjpmProject(
                dir.join("cjpm.toml"),
                env: noEnv,
                cfg: WINDOWS,
                deduceFeatures: false
            ) ??
                throw FixtureException("expected fixture value")
        removeTree(dir)

        // assert
        for (module in load.model.modules where module.name == "bridge" || module.name == "dep") {
            @Expect(module.inactive.size, 0)
            @Expect(module.resolutionScope.isEmpty(), false)
        }
    }

    @TestCase
    func malformedAndUndeclaredFeatureInputsAreRecoverableButUnknownOwnersAreAccepted(): Unit {
        // arrange
        let dir = tree(featureFiles("dep", featureModule("dep")))

        // act
        let load =
            loadCjpmProject(
                dir.join("dep/cjpm.toml"),
                env: noEnv,
                cfg: LINUX,
                enabledFeatures: ["bad", "user.dep.absent", "user.unknown.fast"]
            ) ??
                throw FixtureException("expected fixture value")
        removeTree(dir)

        // assert
        @Expect(load.model.modules.size, 1)
        @Expect(load.problems.filter { problem => problem.contains("feature") || problem.contains("Feature") }, [
            "Invalid CJMP feature `bad`: expected an OS feature or `user.packageName.name`.",
            "Feature `user.dep.absent` is not declared by dependency `dep`."
        ])
    }

    @TestCase
    func namesDeclareIndependentDependencyFlagsAndIgnoreTheirSiblingMapping(): Unit {
        // arrange
        let files = ArrayList<(String, String)>(
            [
                (
                    "cjpm.toml",
                    "[package]\nname = \"app\"\nalways-enabled-features = [\"user.dep.fast\"]\n[dependencies]\ndep = {path = \"dep\"}\n"
                ),
                ("src/a.cj", "package app\n")
            ]
        )
        let depManifest =
            #"
[package]
name = "dep"
[[feature]]
names = ["user.dep.fast"]
mapping = ["user.dep.ignored"]
[[source-set]]
src-dir = "src/common"
features = []
[[source-set]]
src-dir = "src/fast"
features = ["user.dep.fast"]
"#
        files.add(all: featureFiles("dep", depManifest))
        let dir = tree(files.toArray())

        // act
        let load =
            loadCjpmProject(dir.join("cjpm.toml"), env: noEnv, cfg: LINUX) ??
                throw FixtureException("expected cjpm project")
        removeTree(dir)

        // assert
        @Expect(featureModuleOf(load.model, "dep").inactive.size, 0)
        @Expect(load.problems.filter { problem => problem.contains("feature") || problem.contains("Feature") }, Array<String>())
    }

    @TestCase
    func aTestOnlyOwnerIsAbsentFromTheBuildFeatureNamespace(): Unit {
        // arrange
        let files = ArrayList<(String, String)>(
            [
                (
                    "cjpm.toml",
                    "[package]\nname = \"app\"\n[test-dependencies]\nchecks = {path = \"checks\"}\n"
                ),
                ("src/a.cj", "package app\n")
            ]
        )
        files.add(all: featureFiles("checks", featureModule("checks")))
        let dir = tree(files.toArray())

        // act
        let build = findProject(
            dir,
            env: noEnv,
            cfg: LINUX,
            enabledFeatures: ["user.checks.absent"]
        )
        let test = findProject(
            dir,
            env: noEnv,
            cfg: LINUX,
            enabledFeatures: ["user.checks.absent"],
            includeTestFeatures: true
        )
        removeTree(dir)

        // assert
        @Expect(build.problems.filter { problem => problem.contains("Feature") }, Array<String>())
        @Expect(test.problems.filter { problem => problem.contains("Feature") },
            ["Feature `user.checks.absent` is not declared by dependency `checks`."])
    }

    @TestCase
    func foreignOwnerMappingDeclarationsDoNotFireInAConsumer(): Unit {
        // arrange
        let files = ArrayList<(String, String)>(
            [("cjpm.toml", "[workspace]\nmembers = [\"app\"]\n")]
        )
        let foreignMapping =
            "\n[[feature]]\nname = \"user.dep.fast\"\nmapping = [\"user.app.fast\"]\n"
        let app = featureModule("app", deps: "dep = {path = \"../dep\"}")
        files.add(all: featureFiles("app", "${app}${foreignMapping}"))
        files.add(all: featureFiles("dep", featureModule("dep")))
        let dir = tree(files.toArray())

        // act
        let load =
            loadCjpmProject(
                dir.join("cjpm.toml"),
                env: noEnv,
                cfg: LINUX,
                enabledFeatures: ["user.dep.fast"]
            ) ??
                throw FixtureException("expected fixture value")
        removeTree(dir)

        // assert
        @Expect(featureModuleOf(load.model, "app").inactive.size, 1)
        @Expect(load.problems.iterator().any { problem => problem.contains("must belong to `user.app.`") })
    }
}

/**
 * Find the ordinary module with a fixture failure explaining a missing model entry.
 */
func featureModuleOf(model: ProjectModel, name: String): ModuleModel {
    model
        .modules
        .iterator()
        .filter { module => module.name == name && module.resolutionScope.isEmpty() }
        .next() ??
        throw FixtureException("expected ordinary module `${name}`")
}
