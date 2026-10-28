package project_model

import std.unittest.*
import std.unittest.testmacro.*

@Test
class CjpmGitCompatibilityTest {
    @TestCase[sample in [
        (DependencyTable(git: GIT_URL), DependencyTable(git: GIT_URL, branch: "main"), "?branch=main", false),
        (DependencyTable(git: GIT_URL, branch: "main"), DependencyTable(git: GIT_URL), "?branch=main", false),
        (DependencyTable(git: GIT_URL, tag: "v1"), DependencyTable(git: GIT_URL), "?tag=v1", false),
        (DependencyTable(git: GIT_URL, branch: "main"), DependencyTable(git: GIT_URL, branch: "main"), "?branch=main", true),
        (DependencyTable(git: GIT_URL, commitId: GIT_COMMIT), DependencyTable(git: GIT_URL), "", true),
        (DependencyTable(git: GIT_URL.removeSuffix(".git")), DependencyTable(git: GIT_URL), "", true),
        (DependencyTable(git: GIT_URL, commitId: GIT_COMMIT, branch: "ignored"), DependencyTable(git: GIT_URL, commitId: GIT_COMMIT), "", false),
        (DependencyTable(git: GIT_URL, branch: "main", tag: "ignored"), DependencyTable(git: GIT_URL, branch: "main"), "?branch=main", false)
    ]]
    func selectorsMustAgreeWithinOneScopeEvenWhenTheyReachTheSameCommit(
        sample: (DependencyTable, DependencyTable, String, Bool)
    ) {
        // arrange
        let (first, second, selector, compatible) = sample
        let entry = "dep = {source = \"git+${GIT_URL}${selector}#${GIT_COMMIT}\"}\n"
        let dir =
            tree(
                [
                    ("cjpm.lock", "version = 1\n[requires]\n${entry}[scripts]\n${entry}"),
                    ("cangjie-repo.toml", "[repository.cache]\npath = \"cache\"\n"),
                    ("cache/git/dep/${GIT_COMMIT}/cjpm.toml", "[package]\nname = \"dep\"\n")
                ]
            )
        let loading = Loading(sdkEnv, hostCfg())
        let git = CjpmGit(loading, dir)
        try {
            // act
            let selected = git.resolve("dep", first, script: false)
            let incoming = git.resolve("dep", second, script: false)
            let independent = git.resolve("dep", second, script: true)
            // assert
            @Expect(selected.isSome())
            @Expect(incoming.isSome(), compatible)
            @Expect(independent.isSome())
            @Expect(loading.problems.size, if (compatible) { 0 } else { 1 })
            if (!compatible && !loading.problems.isEmpty()) {
                @Expect(loading.problems[0].contains("conflicting Git declarations"))
            }
        } finally {
            removeTree(dir)
        }
    }
}
