package project_model

import std.collection.ArrayList
import std.fs.File
import std.unittest.*
import std.unittest.testmacro.*
import fjson.*
import loupe.db.*

@Test
class CjpmBuildModeTest {
    @TestCase[mode in [BuildMode.Debug, BuildMode.Release], discovery in ["root", "linked", "found"]]
    func modesSelectSourceAndTestGraphsIncludingWorkspaceInheritance(
        mode: BuildMode,
        discovery: String
    ): Unit {
        // arrange
        let chosen = if (mode == BuildMode.Debug) { "debug" } else { "release" }
        let source = dependencyImportSource("app", "helper")
        let dir = tree(
            [
                (
                    "cjpm.toml",
                    """
[workspace]
members = ["app"]
[target.x86_64-unknown-linux-gnu.debug.dependencies]
helper = {path = "debug"}
[target.x86_64-unknown-linux-gnu.release.dependencies]
helper = {path = "release"}
[target.x86_64-unknown-linux-gnu.debug.test-dependencies]
checks = {path = "checks-debug"}
[target.x86_64-unknown-linux-gnu.release.test-dependencies]
checks = {path = "checks-release"}
[target.aarch64-apple-darwin.debug.dependencies]
unselected = {path = "missing"}
"""
                ),
                ("app/cjpm.toml", "[package]\nname = \"app\"\n"),
                ("app/src/main.cj", source),
                ("app/src/main_test.cj", dependencyImportSource("app", "checks")),
                ("app/build.cj", "main(): Int64 { 0 }"),
                ("debug/cjpm.toml", "[package]\nname = \"helper\"\n"),
                ("debug/src/lib.cj", "package helper\npublic class Helper {}"),
                ("release/cjpm.toml", "[package]\nname = \"helper\"\n"),
                ("release/src/lib.cj", "package helper\npublic class Helper {}"),
                ("checks-debug/cjpm.toml", "[package]\nname = \"checks\"\n"),
                ("checks-debug/src/lib.cj", "package checks\npublic class Helper {}"),
                ("checks-release/cjpm.toml", "[package]\nname = \"checks\"\n"),
                ("checks-release/src/lib.cj", "package checks\npublic class Helper {}")
            ]
        )
        try {
            // act
            let loads =
                match (discovery) {
                    case "linked" =>
                        findProjects([], [dir], env: sdkEnv, cfg: LINUX, buildMode: mode)
                    case "found" =>
                        findProjects([], [], env: sdkEnv, cfg: LINUX, buildMode: mode, found: [dir])
                    case _ => findProjects([dir], [], env: sdkEnv, cfg: LINUX, buildMode: mode)
                }
            let load = loads[0]
            let cfgProblems = ArrayList<String>()
            let configured = withPackageCfgs(load.model, cfgProblems)
            let (db, vfs) = testDependencyDatabase(configured)
            let app = load.model.modules.filter { m => m.name == "app" }[0]
            let script = load.model.modules.filter { m => m.name == "default" }[0]
            let projected = lowerProjectJson(
                toProjectJson(load.model, dir),
                dir,
                env: sdkEnv,
                cfg: LINUX
            )

            // assert
            @Expect(load.problems, [])
            @Expect(cfgProblems.isEmpty())
            @Expect(configured, load.model)
            @Expect(load.model.cfg, LINUX)
            @Expect(app.deps, ["helper"])
            @Expect(app.testDeps, ["checks"])
            @Expect(script.deps, Array<String>())
            @Expect(projected.modules.filter { m => m.name == "app" }[0].testDeps, ["checks"])
            expectDependencyImport(
                db,
                vfs,
                dir,
                "app/src/main.cj",
                "app",
                "helper",
                "${chosen}/src/lib.cj"
            )
            expectDependencyImport(
                db,
                vfs,
                dir,
                "app/src/main_test.cj",
                "app",
                "checks",
                "checks-${chosen}/src/lib.cj"
            )
        } finally {
            removeTree(dir)
        }
    }

    @TestCase[mode in [BuildMode.Debug, BuildMode.Release]]
    func scriptDependencyModulesUseTheirOwnModeWithoutLeakingToRuntime(mode: BuildMode): Unit {
        // arrange
        let chosen = if (mode == BuildMode.Debug) { "debug" } else { "release" }
        let dir = tree(
            [
                (
                    "cjpm.toml",
                    """
[package]
name = "app"
[script-dependencies]
tools = {path = "tools"}
"""
                ),
                ("src/app.cj", "package app"),
                ("build.cj", "main(): Int64 { 0 }"),
                (
                    "tools/cjpm.toml",
                    """
[package]
name = "tools"
[target.x86_64-unknown-linux-gnu.debug.dependencies]
helper = {path = "../debug"}
[target.x86_64-unknown-linux-gnu.release.dependencies]
helper = {path = "../release"}
"""
                ),
                ("tools/src/lib.cj", dependencyImportSource("tools", "helper")),
                ("debug/cjpm.toml", "[package]\nname = \"helper\"\n"),
                ("debug/src/lib.cj", "package helper\npublic class Helper {}"),
                ("release/cjpm.toml", "[package]\nname = \"helper\"\n"),
                ("release/src/lib.cj", "package helper\npublic class Helper {}")
            ]
        )
        try {
            // act
            let load = loadCjpmProject(
                dir.join("cjpm.toml"),
                env: sdkEnv,
                cfg: LINUX,
                buildMode: mode
            )
                .getOrThrow()
            let cfgProblems = ArrayList<String>()
            let configured = withPackageCfgs(load.model, cfgProblems)
            let helper = configured.modules.filter { m => m.name == "helper" }[0]
            let app = configured.modules.filter { m => m.name == "app" }[0]

            // assert
            @Expect(load.problems, [])
            @Expect(cfgProblems.isEmpty())
            @Expect(configured, load.model)
            @Expect(helper.root, dir.join("${chosen}/src"))
            @Expect(!helper.resolutionScope.isEmpty())
            @Expect(app.deps, Array<String>())
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func modeDependenciesAddToCommonDeclarationsAndRetainSourceConflicts(): Unit {
        // arrange
        let dir = tree(
            [
                (
                    "cjpm.toml",
                    """
[package]
name = "app"
[dependencies]
helper = {path = "common"}
[target.x86_64-unknown-linux-gnu.dependencies]
base = {path = "base"}
[target.x86_64-unknown-linux-gnu.debug.dependencies]
helper = {path = "debug"}
[target.x86_64-unknown-linux-gnu.release.dependencies]
extra = {path = "extra"}
"""
                ),
                ("src/main.cj", "package app"),
                ("common/cjpm.toml", "[package]\nname = \"helper\"\n"),
                ("common/src/lib.cj", "package helper"),
                ("debug/cjpm.toml", "[package]\nname = \"helper\"\n"),
                ("debug/src/lib.cj", "package helper"),
                ("base/cjpm.toml", "[package]\nname = \"base\"\n"),
                ("base/src/lib.cj", "package base"),
                ("extra/cjpm.toml", "[package]\nname = \"extra\"\n"),
                ("extra/src/lib.cj", "package extra")
            ]
        )
        try {
            // act
            let release = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX)
                .getOrThrow()
            let debug = loadCjpmProject(
                dir.join("cjpm.toml"),
                env: sdkEnv,
                cfg: LINUX,
                buildMode: BuildMode.Debug
            )
                .getOrThrow()

            // assert
            @Expect(release.problems, [])
            @Expect(release.model.modules.filter { m => m.name == "app" }[0].deps, ["base", "extra", "helper"])
            @Expect(debug.problems.size, 1)
            @Expect(debug.problems[0].contains("Conflicting"))
            @Expect(debug.model.modules.filter { m => m.name == "app" }[0].deps, ["base", "helper"])
        } finally {
            removeTree(dir)
        }
    }

    @TestCase[mode in [BuildMode.Debug, BuildMode.Release]]
    func binaryPriorityIsPerPackageAndKeepsDirectoryWatches(mode: BuildMode): Unit {
        // arrange
        let chosen = if (mode == BuildMode.Debug) { "debug" } else { "release" }
        let dir = tree(
            [
                (
                    "cjpm.toml",
                    """
[package]
name = "app"
[target.x86_64-unknown-linux-gnu.bin-dependencies]
path-option = ["common/helper"]
[target.x86_64-unknown-linux-gnu.bin-dependencies.package-option]
"helper.selected" = "common-explicit/helper.selected.cjo"
[target.x86_64-unknown-linux-gnu.debug.bin-dependencies]
path-option = ["debug/artifacts"]
[target.x86_64-unknown-linux-gnu.debug.bin-dependencies.package-option]
"helper.explicit" = "debug-explicit/helper.explicit.cjo"
[target.x86_64-unknown-linux-gnu.release.bin-dependencies]
path-option = ["release/helper"]
[target.x86_64-unknown-linux-gnu.release.bin-dependencies.package-option]
"helper.explicit" = "release-explicit/helper.explicit.cjo"
"""
                ),
                ("src/main.cj", "package app"),
                ("common/helper/helper.selected.cjo", ""),
                ("common/helper/helper.retained.cjo", ""),
                ("common-explicit/helper.selected.cjo", ""),
                ("debug/artifacts/helper.selected.cjo", ""),
                ("debug/artifacts/helper.explicit.cjo", ""),
                ("release/helper/helper.selected.cjo", ""),
                ("release/helper/helper.explicit.cjo", ""),
                ("debug-explicit/helper.explicit.cjo", ""),
                ("release-explicit/helper.explicit.cjo", "")
            ]
        )
        try {
            // act
            let load = loadCjpmProject(
                dir.join("cjpm.toml"),
                env: sdkEnv,
                cfg: LINUX,
                buildMode: mode
            )
                .getOrThrow()
            let helper = load.model.binaries.filter { b => b.name == "helper" }[0]
            let modeDir =
                if (mode == BuildMode.Debug) { "debug/artifacts" } else { "release/helper" }
            let files = load.model.cjoFiles().filter { f => f.binary == "helper" }
            let encoded = toJsonBytes(toProjectJson(load.model, dir))
            let decoded = fromJsonBytes<ProjectJson>(encoded)
            let projected = lowerProjectJson(decoded, dir, env: sdkEnv, cfg: LINUX)
            let projectedFiles = projected.cjoFiles().filter { f => f.binary == "helper" }

            // assert
            @Expect(load.problems, [])
            @Expect(load.model.binaries.map { b => b.name }, ["std", "helper"])
            @Expect(helper.paths, [dir.join(modeDir), dir.join("common/helper")])
            @Expect(!helper.discoverPackages)
            @Expect(projectedFiles, files)
            @Expect(files.map { f => f.name }, ["helper.explicit", "helper.retained", "helper.selected"])
            @Expect(files.map { f => f.path }, [dir.join("${chosen}-explicit/helper.explicit.cjo"), dir.join("common/helper/helper.retained.cjo"), dir.join(modeDir).join("helper.selected.cjo")])

            // act: a newly built package in an arbitrarily named directory is rediscovered.
            let added = dir.join(modeDir).join("second.cjo")
            File.writeTo(added.filePath.getOrThrow(), Array<UInt8>())
            let reloaded = loadCjpmProject(
                dir.join("cjpm.toml"),
                env: sdkEnv,
                cfg: LINUX,
                buildMode: mode
            )
                .getOrThrow()
            let newFiles = reloaded.model.cjoFiles().filter { f => f.name == "second" }

            // assert
            @Expect(newFiles.size, 1)
            @Expect(newFiles[0].binary, "second")
            @Expect(newFiles[0].path, added)
        } finally {
            removeTree(dir)
        }
    }
}
