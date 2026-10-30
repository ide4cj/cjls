package project_model

import std.unittest.*
import std.unittest.testmacro.*

@Test
class CjpmWorkspaceDependenciesTest {
    @TestCase[targetSpecific in [false, true]]
    func membersInheritSourceAndTestDependencies(targetSpecific: Bool) {
        // arrange
        let prefix = if (targetSpecific) { "target.x86_64-unknown-linux-gnu." } else { "" }
        let source = dependencyImportSource("app", "helper")
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[workspace]\nmembers = [\"app\", \"other\"]\n[${prefix}test-dependencies]\nhelper = {path = \"helper\"}\n[${prefix}dependencies]\nleaf = {path = \"leaf\"}\n"
                    ),
                    ("app/cjpm.toml", "[package]\nname = \"app\"\n"),
                    ("app/src/main.cj", source),
                    ("app/src/main_test.cj", source),
                    ("other/cjpm.toml", "[package]\nname = \"other\"\n"),
                    ("other/src/lib.cj", dependencyImportSource("other", "leaf")),
                    ("helper/cjpm.toml", "[package]\nname = \"helper\"\n"),
                    ("helper/src/lib.cj", "package helper\npublic class Helper {}\n"),
                    ("leaf/cjpm.toml", "[package]\nname = \"leaf\"\n"),
                    ("leaf/src/lib.cj", "package leaf\npublic class Helper {}\n")
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()
            let (db, vfs) = testDependencyDatabase(load.model)

            // assert
            @Expect(load.problems, [])
            for (module in load.model.modules) {
                if (module.member) {
                    @Expect(module.deps, ["leaf"])
                    @Expect(module.testDeps, ["helper"])
                } else {
                    @Expect(module.deps, Array<String>())
                    @Expect(module.testDeps, Array<String>())
                }
            }
            expectDependencyImport(
                db,
                vfs,
                dir,
                "other/src/lib.cj",
                "other",
                "leaf",
                "leaf/src/lib.cj"
            )
            expectDependencyImport(db, vfs, dir, "app/src/main.cj", "app", "helper", None)
            expectDependencyImport(
                db,
                vfs,
                dir,
                "app/src/main_test.cj",
                "app",
                "helper",
                "helper/src/lib.cj"
            )
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func scriptsInheritOnlyWorkspaceScriptDependencies() {
        // arrange
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[workspace]\nmembers = [\"app\"]\n[script-dependencies]\nhelper = {path = \"helper\"}\n"
                    ),
                    ("build.cj", "main(): Int64 { 0 }\n"),
                    ("app/cjpm.toml", "[package]\nname = \"app\"\n"),
                    ("app/src/main.cj", "package app\n"),
                    ("app/build.cj", "main(): Int64 { 0 }\n"),
                    ("helper/cjpm.toml", "[package]\nname = \"helper\"\n"),
                    ("helper/src/lib.cj", "package helper\n")
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()

            // assert
            @Expect(load.problems, [])
            @Expect(load.model.modules.filter { m => m.name == "app" }[0].deps, Array<String>())
            let scripts = load.model.modules.filter { m => m.name == "default" }
            @Expect(scripts.size, 2)
            for (script in scripts) {
                @Expect(script.deps, ["helper"])
            }
        } finally {
            removeTree(dir)
        }
    }

    @TestCase[workspaceLocal in [false, true]]
    func localDeclarationsTakePrecedenceOverSharedRegistryRequirements(workspaceLocal: Bool) {
        // arrange
        let shared = if (workspaceLocal) { "{path = \"helper\"}" } else { "\"1.0.0\"" }
        let member = if (workspaceLocal) { "\"1.0.0\"" } else { "{path = \"../helper\"}" }
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[workspace]\nmembers = [\"app\"]\n[dependencies]\nhelper = ${shared}\n"
                    ),
                    (
                        "app/cjpm.toml",
                        "[package]\nname = \"app\"\n[dependencies]\nhelper = ${member}\n"
                    ),
                    ("app/src/main.cj", "package app\n"),
                    ("helper/cjpm.toml", "[package]\nname = \"helper\"\n"),
                    ("helper/src/lib.cj", "package helper\n")
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()

            // assert
            @Expect(load.problems, [])
            @Expect(load.model.modules.filter { m => m.name == "app" }[0].deps, ["helper"])
            @Expect(load.model.modules.filter { m => m.name == "helper" }[0].root, dir.join("helper/src"))
        } finally {
            removeTree(dir)
        }
    }

    @TestCase[section in ["dependencies", "test-dependencies"]]
    func sharedTargetDeclarationsDoNotSilentlyReplaceCommonSources(section: String) {
        // arrange
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[workspace]\nmembers = [\"app\"]\n[${section}]\nhelper = {path = \"first\"}\n[target.x86_64-unknown-linux-gnu.${section}]\nhelper = {path = \"second\"}\n"
                    ),
                    ("app/cjpm.toml", "[package]\nname = \"app\"\n"),
                    ("app/src/main.cj", "package app\n"),
                    ("first/cjpm.toml", "[package]\nname = \"helper\"\n"),
                    ("first/src/lib.cj", "package helper\n"),
                    ("second/cjpm.toml", "[package]\nname = \"helper\"\n"),
                    ("second/src/lib.cj", "package helper\n")
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()

            // assert
            @Expect(load.problems.size, 1)
            @Expect(load.problems[0].contains("Conflicting ordinary/test dependency `helper`"))
            @Expect(load.model.modules.filter { m => m.name == "helper" }[0].root, dir.join("first/src"))
        } finally {
            removeTree(dir)
        }
    }

    @TestCase[samePath in [false, true], section in ["dependencies", "test-dependencies", "script-dependencies"]]
    func duplicateDeclarationsKeepTheirManifestBaseAndReportConflicts(
        samePath: Bool,
        section: String
    ) {
        // arrange
        let tests = section == "test-dependencies"
        let scripts = section == "script-dependencies"
        let path = if (samePath) { "../shared" } else { "local" }
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[workspace]\nmembers = [\"app\"]\n[${section}]\nhelper = {path = \"shared\"}\n"
                    ),
                    (
                        "app/cjpm.toml",
                        "[package]\nname = \"app\"\n[${section}]\nhelper = {path = \"${path}\"}\n"
                    ),
                    ("app/src/main.cj", "package app\n"),
                    ("app/build.cj", "main(): Int64 { 0 }\n"),
                    ("app/local/cjpm.toml", "[package]\nname = \"helper\"\n"),
                    ("app/local/src/lib.cj", "package helper\n"),
                    ("shared/cjpm.toml", "[package]\nname = \"helper\"\n"),
                    ("shared/src/lib.cj", "package helper\n")
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()

            // assert
            @Expect(load.problems.size, if (samePath) { 0 } else { 1 })
            if (!samePath) {
                let scope = if (scripts) { "build-script" } else { "ordinary/test" }
                @Expect(load.problems[0].contains("Conflicting ${scope} dependency `helper`"))
            }
            let app = load.model.modules.filter { m => m.name == "app" }[0]
            @Expect(app.deps, if (tests || scripts) { Array<String>() } else { ["helper"] })
            @Expect(app.testDeps, if (tests) { ["helper"] } else { Array<String>() })
            if (scripts) {
                @Expect(load.model.modules.filter { m => m.name == "default" }[0].deps, ["helper"])
            }
        } finally {
            removeTree(dir)
        }
    }
}
