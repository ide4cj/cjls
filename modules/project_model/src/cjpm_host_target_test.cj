package project_model

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.*
import loupe.vfs.VfsPath

@Test
class CjpmHostTargetTest {
    @TestCase[mode in [BuildMode.Debug, BuildMode.Release], discovery in ["root", "linked", "found"]]
    func scriptSourceTablesAndFeatureRequestsFollowTheHost(
        mode: BuildMode,
        discovery: String
    ): Unit {
        // arrange
        let host = cjpmTriple(hostCfg()).getOrThrow()
        let crossCfg = if (hostCfg().get("os") == Some("Windows")) { LINUX } else { WINDOWS }
        let cross = cjpmTriple(crossCfg).getOrThrow()
        let chosen = if (mode == BuildMode.Debug) { "debug" } else { "release" }
        let dir = hostSourceTree(host, cross, chosen)
        try {
            // act
            let loads =
                match (discovery) {
                    case "linked" =>
                        findProjects([], [dir], env: sdkEnv, cfg: crossCfg, buildMode: mode)
                    case "found" =>
                        findProjects(
                            [],
                            [],
                            env: sdkEnv,
                            cfg: crossCfg,
                            buildMode: mode,
                            found: [dir]
                        )
                    case _ => findProjects([dir], [], env: sdkEnv, cfg: crossCfg, buildMode: mode)
                }
            let load = loads[0]

            // assert
            @Expect(load.problems, [])
            @Expect(load.model.cfg, crossCfg)
            for (name in ["bridge", "leaf", "tip"]) {
                let modules = load.model.modules.filter { m => m.name == name }
                @Expect(modules.size, 2)
                for (module in modules) {
                    let side = if (module.resolutionScope.isEmpty()) { "cross" } else { "host" }
                    if (name == "bridge") {
                        @Expect(module.root, dir.join("bridge/src"))
                        @Expect(module.deps, ["leaf"])
                    } else if (name == "leaf") {
                        @Expect(module.root, dir.join("${side}-leaf/src"))
                        @Expect(module.deps, ["tip"])
                    } else {
                        @Expect(module.root, dir.join("${side}-tip/src/common"))
                        @Expect(module.inactive.size, 0)
                    }
                    @Expect(module.testDeps, Array<String>())
                }
            }
            @Expect(load.model.modules.filter { m => m.name == "app" }[0].testDeps, ["checks"])
        } finally {
            removeTree(dir)
        }
    }

    @TestCase[profile in ["common", "debug", "release"], owner in ["bridge", "leaf"]]
    func scriptBinariesKeepHostPackagesAndSearchPathsSeparate(
        profile: String,
        owner: String
    ): Unit {
        // arrange
        let host = cjpmTriple(hostCfg()).getOrThrow()
        let crossCfg = if (hostCfg().get("os") == Some("Windows")) { LINUX } else { WINDOWS }
        let cross = cjpmTriple(crossCfg).getOrThrow()
        let mode = if (profile == "debug") { BuildMode.Debug } else { BuildMode.Release }
        let modeTable = if (profile == "common") { "" } else { ".${profile}" }
        let dir = hostBinaryTree(host, cross, modeTable, owner)
        try {
            // act
            let load = findProject(dir, env: sdkEnv, cfg: crossCfg, buildMode: mode)
            let projected = lowerProjectJson(
                toProjectJson(load.model, dir),
                dir,
                env: sdkEnv,
                cfg: crossCfg
            )

            // assert
            @Expect(load.problems, [])
            @Expect(projected.cjoFiles(), load.model.cjoFiles())
            let bridges = load.model.modules.filter { m => m.name == owner }
            @Expect(bridges.size, 2)
            @Expect(bridges[0].deps.filter { dep => bridges[1].deps.contains(dep) }, Array<String>())
            for (bridge in bridges) {
                let side = if (bridge.resolutionScope.isEmpty()) { "cross" } else { "host" }
                let binaries = load.model.binaries.filter { b => bridge.deps.contains(b.name) }
                let selected = load.model.cjoFiles().filter { f => bridge.deps.contains(f.binary) }
                @Expect(selected.size, 2)
                @Expect(selected.filter { f => f.name == "marker.selected" }[0].path, dir.join("${owner}/${side}/marker.selected.cjo"))
                @Expect(selected.filter { f => f.name == "helper" }[0].path, dir.join("${owner}/${side}/search/helper.cjo"))
                @Expect(binaries.iterator().any { b => b.paths.contains(dir.join("${owner}/${side}/search")) })
            }
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func hostTableConflictsRemainRecoverable(): Unit {
        // arrange
        let host = cjpmTriple(hostCfg()).getOrThrow()
        let crossCfg = if (hostCfg().get("os") == Some("Windows")) { LINUX } else { WINDOWS }
        let cross = cjpmTriple(crossCfg).getOrThrow()
        let dir = hostConflictTree(host, cross)
        try {
            // act
            let load = findProject(dir, env: sdkEnv, cfg: crossCfg)
            let leaf = load.model.modules.filter { m => m.name == "leaf" }[0]

            // assert
            @Expect(load.problems.size, 1)
            @Expect(load.problems[0].contains("Conflicting build-script dependency"))
            @Expect(load.problems[0].contains(dir.join("host").toString()))
            @Expect(!load.problems[0].contains(dir.join("cross").toString()))
            @Expect(leaf.root, dir.join("common/src"))
            @Expect(!leaf.resolutionScope.isEmpty())
        } finally {
            removeTree(dir)
        }
    }
}

private func hostSourceTree(host: String, cross: String, chosen: String): VfsPath {
    let files = ArrayList<(String, String)>(
        [
            (
                "cjpm.toml",
                """
[workspace]
members = ["app"]
[dependencies]
bridge = {path = "bridge"}
[test-dependencies]
checks = {path = "checks"}
[script-dependencies]
bridge = {path = "bridge"}
"""
            ),
            (
                "app/cjpm.toml",
                """
[package]
name = "app"
"""
            ),
            ("app/src/app.cj", "package app"),
            ("app/build.cj", "main(): Int64 { 0 }"),
            (
                "checks/cjpm.toml",
                """
[package]
name = "checks"
[dependencies]
bridge = {path = "../bridge"}
"""
            ),
            ("checks/src/check.cj", "package checks"),
            (
                "bridge/cjpm.toml",
                """
[package]
name = "bridge"
[target.${host}.dependencies]
leaf = {path = "../host-leaf"}
[target.${cross}.dependencies]
leaf = {path = "../cross-leaf"}
"""
            ),
            ("bridge/src/lib.cj", "package bridge")
        ]
    )
    files.add(all: hostGraphFiles(host, cross, chosen))
    tree(files.toArray())
}

private func hostLeafManifest(triple: String, other: String, chosen: String, side: String): String {
    """
[package]
name = "leaf"
[[feature]]
name = "user.leaf.fast"
mapping = ["user.tip.fast"]
[[feature]]
name = "os.linux"
mapping = ["user.leaf.fast"]
[[feature]]
name = "os.windows"
mapping = ["user.leaf.fast"]
[[feature]]
name = "os.darwin"
mapping = ["user.leaf.fast"]
[target.${triple}.${chosen}.dependencies]
tip = {path = "../${side}-tip"}
[target.${other}.${chosen}.dependencies]
wrong = {path = "../missing"}
"""
}

private func hostBinaryTree(
    host: String,
    cross: String,
    modeTable: String,
    owner: String
): VfsPath {
    let files = ArrayList<(String, String)>(
        [
            (
                "cjpm.toml",
                """
[package]
name = "app"
[dependencies]
bridge = {path = "bridge"}
[script-dependencies]
bridge = {path = "bridge"}
"""
            ),
            ("src/app.cj", "package app"),
            ("build.cj", "main(): Int64 { 0 }"),
            ("${owner}/src/lib.cj", "package ${owner}"),
            (
                "${owner}/cjpm.toml",
                """
[package]
name = "${owner}"
[target.${host}${modeTable}.bin-dependencies]
path-option = ["host/search"]
[target.${host}${modeTable}.bin-dependencies.package-option]
"marker.selected" = "host/marker.selected.cjo"
[target.${cross}${modeTable}.bin-dependencies]
path-option = ["cross/search"]
[target.${cross}${modeTable}.bin-dependencies.package-option]
"marker.selected" = "cross/marker.selected.cjo"
"""
            )
        ]
    )
    if (owner != "bridge") {
        files.add(
            (
                "bridge/cjpm.toml",
                """
[package]
name = "bridge"
[dependencies]
leaf = {path = "../leaf"}
"""
            )
        )
        files.add(("bridge/src/lib.cj", "package bridge"))
    }
    for (side in ["host", "cross"]) {
        files.add(("${owner}/${side}/search/helper.cjo", ""))
        files.add(("${owner}/${side}/marker.selected.cjo", ""))
    }
    tree(files.toArray())
}

private func hostGraphFiles(host: String, cross: String, chosen: String): Array<(String, String)> {
    let files = ArrayList<(String, String)>()
    for (side in ["host", "cross"]) {
        let triple = if (side == "host") { host } else { cross }
        let other = if (side == "host") { cross } else { host }
        files.add(("${side}-leaf/cjpm.toml", hostLeafManifest(triple, other, chosen, side)))
        files.add(("${side}-leaf/src/lib.cj", "package leaf"))
        files.add(
            (
                "${side}-tip/cjpm.toml",
                """
[package]
name = "tip"
[[feature]]
name = "user.tip.fast"
[[source-set]]
src-dir = "src/common"
features = []
[[source-set]]
src-dir = "src/fast"
features = ["user.tip.fast"]
"""
            )
        )
        files.add(("${side}-tip/src/common/lib.cj", "package tip"))
        files.add(("${side}-tip/src/fast/fast.cj", "package tip"))
    }
    files.toArray()
}

private func hostConflictTree(host: String, cross: String): VfsPath {
    tree(
        [
            (
                "cjpm.toml",
                """
[package]
name = "app"
[script-dependencies]
bridge = {path = "bridge"}
"""
            ),
            ("src/app.cj", "package app"),
            ("build.cj", "main(): Int64 { 0 }"),
            (
                "bridge/cjpm.toml",
                """
[package]
name = "bridge"
[dependencies]
leaf = {path = "../common"}
[target.${host}.dependencies]
leaf = {path = "../host"}
[target.${cross}.dependencies]
leaf = {path = "../cross"}
"""
            ),
            ("bridge/src/lib.cj", "package bridge"),
            (
                "common/cjpm.toml",
                """
[package]
name = "leaf"
"""
            ),
            ("common/src/lib.cj", "package leaf"),
            (
                "host/cjpm.toml",
                """
[package]
name = "leaf"
"""
            ),
            ("host/src/lib.cj", "package leaf"),
            (
                "cross/cjpm.toml",
                """
[package]
name = "leaf"
"""
            ),
            ("cross/src/lib.cj", "package leaf")
        ]
    )
}
