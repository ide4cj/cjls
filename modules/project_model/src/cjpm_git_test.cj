package project_model

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.vfs.VfsPath

let GIT_COMMIT = "1234567890abcdef1234567890abcdef12345678"
let GIT_URL = "https://example.invalid/dep.git"

@Test
class CjpmGitTest {
    @TestCase[version in [0, 1]]
    func lockedGitDependenciesAndTheirPathsAreLoaded(version: Int64) {
        // arrange
        let entry = if (version == 0) {
            "git = \"${GIT_URL}\", commitId = \"${GIT_COMMIT}\", branch = \"feature/one\""
        } else {
            "source = \"git+${GIT_URL}?branch=feature%2Fone#${GIT_COMMIT}\""
        }
        let dir = tree([
            ("app/cjpm.toml", "[package]\nname = \"app\"\n[dependencies]\n" +
                "dep = {git = \"${GIT_URL}\", branch = \"feature/one\"}\n"),
            ("app/src/main.cj", "import dep.*\n"),
            ("app/cangjie-repo.toml", "[repository.cache]\npath = \"../cache\"\n"),
            ("app/cjpm.lock", "version = ${version}\n[requires]\ndep = { ${entry} }\n"),
            ("cache/git/dep/${GIT_COMMIT}/cjpm.toml", "[package]\nname = \"dep\"\n[dependencies]\n" +
                "leaf = {path = \"leaf\"}\nremote = {git = \"https://example.invalid/remote\"}\n"),
            ("cache/git/dep/${GIT_COMMIT}/src/lib.cj", "package dep\npublic class Remote {}\n"),
            ("cache/git/dep/${GIT_COMMIT}/leaf/cjpm.toml", "[package]\nname = \"leaf\"\n"),
            ("cache/git/dep/${GIT_COMMIT}/leaf/src/lib.cj", "package leaf\n"),
            ("cache/git/remote/${GIT_COMMIT}/cjpm.toml", "[package]\nname = \"remote\"\n"),
            ("cache/git/remote/${GIT_COMMIT}/src/lib.cj", "package remote\n")
        ])
        let remote = if (version == 0) {
            "git = \"https://example.invalid/remote\", commitId = \"${GIT_COMMIT}\""
        } else {
            "source = \"git+https://example.invalid/remote#${GIT_COMMIT}\""
        }
        File.writeTo(dir.join("app/cjpm.lock").filePath.getOrThrow(),
            "version = ${version}\n[requires]\ndep = { ${entry} }\nremote = { ${remote} }\n".toArray())
        // An upstream checkout's own lock must not override the entry project's selection.
        File.writeTo(dir.join("cache/git/dep/${GIT_COMMIT}/cjpm.lock").filePath.getOrThrow(), "broken".toArray())
        try {
            // act
            let load = loadCjpmProject(dir.join("app/cjpm.toml"), env: sdkEnv).getOrThrow()

            // assert
            @Expect(load.problems, [])
            @Expect(load.model.modules.map {it => it.name}, ["leaf", "remote", "dep", "app"])
            @Expect(load.model.modules.map {it => it.member}, [false, false, false, true])
            @Expect(load.model.modules[2].deps, ["leaf", "remote"])
            @Expect(load.model.modules[3].deps, ["dep"])
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func scriptsHaveTheirOwnLockedTransitiveSelections() {
        // arrange
        let dir = tree([
            ("cjpm.toml", "[package]\nname = \"app\"\n[script-dependencies]\n" +
                "tool = {git = \"https://example.invalid/tool\"}\n"),
            ("build.cj", "main() {}\n"),
            ("src/main.cj", ""),
            ("cangjie-repo.toml", "[repository.cache]\npath = \"cache\"\n"),
            ("cjpm.lock", "version = 1\n[requires]\n" +
                "tool = {source = \"git+https://wrong.invalid/tool#${GIT_COMMIT}\"}\n" +
                "[scripts]\ntool = {source = \"git+https://example.invalid/tool#${GIT_COMMIT}\"}\n" +
                "helper = {source = \"git+https://example.invalid/helper#${GIT_COMMIT}\"}\n"),
            ("cache/git/tool/${GIT_COMMIT}/cjpm.toml", "[package]\nname = \"tool\"\n[dependencies]\n" +
                "helper = {git = \"https://example.invalid/helper\"}\n"),
            ("cache/git/tool/${GIT_COMMIT}/src/lib.cj", "package tool\n"),
            ("cache/git/helper/${GIT_COMMIT}/cjpm.toml", "[package]\nname = \"helper\"\n"),
            ("cache/git/helper/${GIT_COMMIT}/src/lib.cj", "package helper\n")
        ])
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()

            // assert
            @Expect(load.problems, [])
            @Expect(load.model.modules.map {it => it.name}, ["app", "helper", "tool", "default"])
            @Expect(load.model.modules[0].deps, [])
            @Expect(load.model.modules[2].deps, ["helper"])
            @Expect(load.model.modules[3].deps, ["tool"])
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func gitWorkspaceMembersUseTheirQualifiedNamesAndOnlyTheChosenCommit() {
        // arrange
        let workspace = "cache/git/workspace-${GIT_URL.hashCode()}/${GIT_COMMIT}"
        let dir = tree([
            ("cjpm.toml", "[package]\nname = \"app\"\n[test-dependencies]\n" +
                "\"org::dep\" = {git = \"${GIT_URL}\", tag = \"v1\"}\n"),
            ("cangjie-repo.toml", "[repository.cache]\npath = \"cache\"\n"),
            ("cjpm.lock", "version = 0\n[requires]\n\"org::dep\" = {git = \"${GIT_URL}\", " +
                "tag = \"v1\", commitId = \"${GIT_COMMIT}\"}\n"),
            ("${workspace}/cjpm.toml", "[workspace]\nmembers = [\"other\", \"nested/dep\"]\n"),
            ("${workspace}/other/cjpm.toml", "[package]\nname = \"other\"\n"),
            ("${workspace}/nested/dep/cjpm.toml", "[package]\nname = \"dep\"\norganization = \"org\"\n"),
            ("${workspace}/nested/dep/src/lib.cj", "package org::dep\n"),
            ("cache/git/dep@org/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/cjpm.toml",
                "[package]\nname = \"wrong\"\n")
        ])
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()

            // assert
            @Expect(load.problems, [])
            @Expect(load.model.modules.map {it => it.name}, ["org::dep", "app"])
            @Expect(load.model.modules[0].root, dir.join("${workspace}/nested/dep/src"))
        } finally {
            removeTree(dir)
        }
    }

    @TestCase[sample in [
        ("", "cannot read"),
        ("version = 2\n[requires]\n", "unsupported lock version"),
        ("version = 1\n[requires]\n", "no locked entry"),
        ("version = 0\n[requires]\ndep = {git = \"https://wrong.invalid/repo\", commitId = \"abc\"}", "URL differs"),
        ("version = 0\n[requires]\ndep = {git = \"https://example.invalid/dep.git\", commitId = \"../bad\"}", "invalid locked commit"),
        ("version = 1\n[requires]\ndep = {source = \"git+url#short\"}", "invalid Git lock source"),
        ("version = 0\n[requires]\ndep = {git = \"https://example.invalid/dep.git\", commitId = \"abc\"}", "checkout")
    ]]
    func missingOrInvalidLocksAndCheckoutsLeaveAnActionableProblem(sample: (String, String)) {
        // arrange
        let dir = tree([
            ("cjpm.toml", "[package]\nname = \"app\"\n[dependencies]\ndep = {git = \"${GIT_URL}\"}\n"),
            ("cangjie-repo.toml", "[repository.cache]\npath = \"cache\"\n")
        ])
        if (!sample[0].isEmpty()) {
            File.writeTo(dir.join("cjpm.lock").filePath.getOrThrow(), sample[0].toArray())
        }
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()

            // assert
            @Expect(load.model.modules.map {it => it.name}, ["app"])
            @Expect(load.problems.size, 1)
            @Expect(load.problems[0].contains(sample[1]), true)
            @Expect(load.problems[0].contains("cjpm update"), true)
        } finally {
            removeTree(dir)
        }
    }

    @TestCase[sample in [
        (DependencyTable(git: GIT_URL, branch: "changed"), "branch differs"),
        (DependencyTable(git: GIT_URL, tag: "changed"), "tag differs"),
        (DependencyTable(git: GIT_URL, commitId: "aaa"), "commit differs"),
        (DependencyTable(git: GIT_URL), "declares `wrong`")
    ]]
    func staleDeclarationsAndWrongPackagesAreNotLoaded(sample: (DependencyTable, String)) {
        // arrange
        let dir = tree([
            ("cjpm.lock", "version = 1\n[requires]\ndep = {source = \"git+${GIT_URL}#${GIT_COMMIT}\"}\n"),
            ("cangjie-repo.toml", "[repository.cache]\npath = \"cache\"\n"),
            ("cache/git/dep/${GIT_COMMIT}/cjpm.toml", "[package]\nname = \"wrong\"\n")
        ])
        let loading = Loading(sdkEnv, LINUX)
        try {
            // act
            let found = CjpmGit(loading, dir).resolve("dep", sample[0], script: false)

            // assert
            @Expect(found.isNone(), true)
            @Expect(loading.problems.size, 1)
            @Expect(loading.problems[0].contains(sample[1]), true)
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func cacheConfigUsesTheFirstFileAndResolvesPathsThere() {
        // arrange
        let dir = tree([
            ("app/cangjie-repo.toml", "[repository.cache]\npath = \"../project-cache\"\n"),
            ("user/.cjpm/cangjie-repo.toml", "[repository.cache]\npath = \"$CACHE_DIR\"\n"),
            ("sdk/tools/config/cangjie-repo.toml", "[repository.cache]\npath = \"../sdk-cache\"\n")
        ])
        let env = envOf([("HOME", dir.join("user").toString()), ("CANGJIE_HOME", dir.join("sdk").toString()),
            ("CACHE_DIR", "../user-cache")])
        let loading = Loading(env, LINUX)
        try {
            // act
            let project = repositoryCache(loading, dir.join("app"))
            remove(dir.join("app/cangjie-repo.toml").filePath.getOrThrow())
            let user = repositoryCache(loading, dir.join("app"))
            remove(dir.join("user/.cjpm/cangjie-repo.toml").filePath.getOrThrow())
            let sdk = repositoryCache(loading, dir.join("app"))
            remove(dir.join("sdk/tools/config/cangjie-repo.toml").filePath.getOrThrow())
            let fallback = repositoryCache(loading, dir.join("app"))

            // assert
            @Expect(project, Some(dir.join("project-cache")))
            @Expect(user, Some(dir.join("user/user-cache")))
            @Expect(sdk, Some(dir.join("sdk/tools/sdk-cache")))
            @Expect(fallback, Some(dir.join("user/.cjpm")))
            @Expect(loading.problems.toArray(), [])
        } finally {
            removeTree(dir)
        }
    }

    @TestCase[abbreviated in [false, true]]
    func qualifiedTargetDependenciesHonorCommitBeforeBranchAndTag(abbreviated: Bool) {
        // arrange
        let commit = if (abbreviated) { GIT_COMMIT[..8] } else { GIT_COMMIT }
        let dir = tree([
            ("cjpm.toml", "[package]\nname = \"app\"\n[target.x86_64-unknown-linux-gnu.dependencies]\n" +
                "\"org::dep\" = {git = \"${GIT_URL}\", commitId = \"${commit}\", branch = \"ignored\", tag = \"ignored\"}\n"),
            ("cangjie-repo.toml", "[repository.cache]\npath = \"cache\"\n"),
            ("cjpm.lock", "version = 1\n[requires]\n\"org::dep\" = {source = \"git+${GIT_URL}#${GIT_COMMIT}\"}\n"),
            ("cache/git/dep@org/${commit}/cjpm.toml", "[package]\nname = \"dep\"\norganization = \"org\"\n"),
            ("cache/git/dep@org/${commit}/src/lib.cj", "package org::dep\n")
        ])
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()

            // assert
            @Expect(load.problems, [])
            @Expect(load.model.modules.map {it => it.name}, ["org::dep", "app"])
            @Expect(load.model.modules[1].deps, ["org::dep"])
        } finally {
            removeTree(dir)
        }
    }
}
