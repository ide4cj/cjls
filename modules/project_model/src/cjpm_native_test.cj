package project_model

import std.collection.ArrayList
import std.fs.File
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.*
import loupe.hir.macroBuildPlan

@Test
class CjpmNativeTest {
    @TestCase[mode in [BuildMode.Debug, BuildMode.Release]]
    func nativeInputsSelectProfilesAndWorkspaceBasesWithoutAddingImports(mode: BuildMode): Unit {
        // arrange
        let host = cjpmTriple(hostCfg()).getOrThrow()
        let chosen = if (mode == BuildMode.Debug) { "debug" } else { "release" }
        let dir = tree(
            [
                (
                    "cjpm.toml",
                    """
[workspace]
members = ["app"]
[ffi.c]
workspace = {path = "native"}
shared = {path = "workspace-shared"}
[target.${host}.ffi.c]
target = {path = "target"}
[target.${host}.debug.ffi.c]
profile = {path = "debug"}
[target.${host}.release.ffi.c]
profile = {path = "release"}
"""
                ),
                (
                    "app/cjpm.toml",
                    """
[package]
name = "app"
output-type = "dynamic"
[ffi.c]
shared = {path = "\${NATIVE_ROOT}"}
[dependencies]
helper = {path = "../helper", output-type = "static"}
[target.${host}.ffi.c]
shared = {path = "common"}
[target.${host}.debug.ffi.c]
shared = {path = "debug"}
[target.${host}.release.ffi.c]
shared = {path = "release"}
[target.unselected.ffi.c]
ignored = {path = "\${UNSET_NATIVE}"}
"""
                ),
                ("app/src/main.cj", dependencyImportSource("app", "helper")),
                (
                    "helper/cjpm.toml",
                    """
[package]
name = "helper"
output-type = "executable"
[ffi.c]
private = {path = "native"}
"""
                ),
                ("helper/src/lib.cj", "package helper\npublic class Helper {}")
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
            let app = load.model.modules.filter { m => m.name == "app" }[0]
            let helper = load.model.modules.filter { m => m.name == "helper" }[0]
            let problems = ArrayList<String>()
            let configured = withPackageCfgs(load.model, problems)
            let projected = lowerProjectJson(
                toProjectJson(load.model, dir),
                dir,
                env: sdkEnv,
                cfg: LINUX
            )
            let merged = ProjectModel.merge([load.model, load.model], LINUX)
            let (db, vfs) = testDependencyDatabase(load.model)
            // assert
            @Expect(load.problems, [])
            @Expect(problems.isEmpty())
            @Expect(app.deps, ["helper"])
            @Expect(app.nativeLibraries, [
                NativeLibrary("profile", dir.join(chosen)),
                NativeLibrary("shared", dir.join("app/${chosen}")),
                NativeLibrary("target", dir.join("target")),
                NativeLibrary("workspace", dir.join("native"))
            ])
            @Expect(helper.nativeLibraries, [NativeLibrary("private", dir.join("helper/native"))])
            @Expect(configured, load.model)
            @Expect(projected, load.model)
            @Expect(merged, load.model)
            @Expect(!load.model.binaries.any { b => b.name == "shared" })
            expectDependencyImport(
                db,
                vfs,
                dir,
                "app/src/main.cj",
                "app",
                "helper",
                "helper/src/lib.cj"
            )
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func nativeLibrariesFollowTransitiveMacroImports(): Unit {
        // arrange
        let dir = tree(
            [
                (
                    "cjpm.toml",
                    """
[package]
name = "app"
[dependencies]
helper = {path = "helper", output-type = "dynamic"}
[ffi.c]
own = {path = "own"}
"""
                ),
                (
                    "src/lib.cj",
                    "macro package app\nimport helper.*\npublic macro M(input: Tokens): Tokens { input }"
                ),
                (
                    "helper/cjpm.toml",
                    """
[package]
name = "helper"
[ffi.c]
foreign = {path = "native"}
"""
                ),
                ("helper/src/lib.cj", "package helper\npublic class Helper {}")
            ]
        )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()
            let (db, vfs) = testDependencyDatabase(load.model)
            let plan = macroBuildPlan(db)
            // assert
            @Expect(load.problems, [])
            @Expect(plan.map { u => u.pkg.name(db) }, ["helper", "app"])
            @Expect(plan[1].nativeLibraries, [NativeLibrary("foreign", dir.join("helper/native")), NativeLibrary("own", dir.join("own"))])
            // act
            File.writeTo(
                dir.join("helper/cjpm.toml").filePath.getOrThrow(),
                """
[package]
name = "helper"
[ffi.c]
foreign = {path = "changed"}
""".toArray()
            )
            let reloaded = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX)
                .getOrThrow()
            db.setProject(reloaded.model, vfs.paths)
            let reloadedPlan = macroBuildPlan(db)

            // assert
            @Expect(reloaded.problems, [])
            @Expect(reloadedPlan[1].nativeLibraries[0], NativeLibrary("foreign", dir.join("helper/changed")))
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func macroNativeInputsUseHostTablesWhileAnalysisUsesTheCompilationTarget(): Unit {
        // arrange
        let host = cjpmTriple(hostCfg()).getOrThrow()
        let cross = Cfg([("os", "Linux"), ("arch", "aarch64"), ("backend", "cjnative")])
        let dir = tree(
            [
                (
                    "cjpm.toml",
                    """
[package]
name = "app"
[ffi.c]
common = {path = "\${NATIVE_ROOT}"}
[target.${host}.ffi.c]
selected = {path = "host"}
[target.aarch64-unknown-linux-gnu.ffi.c]
selected = {path = "cross"}
"""
                ),
                ("src/lib.cj", "package app")
            ]
        )
        try {
            let env =
                {
                    name: String =>
                    if (name == "NATIVE_ROOT") {
                        Some(dir.join("native").toString())
                    } else {
                        sdkEnv(name)
                    }
                }
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: env, cfg: cross).getOrThrow()
            // assert
            @Expect(load.problems, [])
            @Expect(load.model.cfg, cross)
            @Expect(load.model.modules[0].nativeLibraries, [NativeLibrary("common", dir.join("native")), NativeLibrary("selected", dir.join("host"))])
        } finally {
            removeTree(dir)
        }
    }
}
