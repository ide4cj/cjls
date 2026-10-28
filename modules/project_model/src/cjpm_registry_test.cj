package project_model

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.*
import loupe.definitionAt
import loupe.vfs.{readFiles, Vfs}

/**
 * A resolved entry in either lock format, with v1 metadata for the original archive.
 */
func registryEntry(format: Int64, version: String): String {
    let metadata =
        if (format == 0) {
            ""
        } else {
            ", source = \"registry+https://example.invalid/registry\", checksum = \"sha256:${"a" * 64}\", dependencies = []"
        }
    "{version = \"${version}\"${metadata}}"
}

@Test
class CjpmRegistryTest {
    @TestCase[format in [0, 1]]
    func lockedRegistrySourcesAndTransitiveImportsReachAnalysis(format: Int64) {
        // arrange
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[package]\nname = \"app\"\n[dependencies]\n\"org::dep\" = \"[1.0.0, 2.0.0)\"\n"
                    ),
                    (
                        "src/main.cj",
                        "package app\nimport org::dep.*\nfunc use(): Remote { Remote() }\n"
                    ),
                    ("cangjie-repo.toml", "[repository.cache]\npath = \"cache\"\n"),
                    (
                        "cjpm.lock",
                        "version = ${format}\n[requires]\n\"org::dep\" = ${registryEntry(format, "1.2.0")}\nleaf = ${registryEntry(format, "2.0.0")}\n"
                    ),
                    (
                        "cache/repository/source/org/dep-1.2.0/cjpm.toml",
                        "[package]\nname = \"dep\"\norganization = \"org\"\nversion = \"1.2.0\"\n[dependencies]\nleaf = {version = \"2.0.0\"}\n"
                    ),
                    (
                        "cache/repository/source/org/dep-1.2.0/src/lib.cj",
                        "package org::dep\npublic class Remote {}\n"
                    ),
                    ("cache/repository/source/org/dep-1.2.0/cjpm.lock", "not a lock"),
                    (
                        "cache/repository/source/default/leaf-2.0.0/cjpm.toml",
                        "[package]\nname = \"leaf\"\nversion = \"2.0.0\"\n"
                    ),
                    ("cache/repository/source/default/leaf-2.0.0/src/lib.cj", "package leaf\n"),
                    (
                        "cache/repository/source/org/dep-1.9.0/cjpm.toml",
                        "[package]\nname = \"wrong\"\nversion = \"1.9.0\"\n"
                    )
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()
            let db = AnalysisDatabase()
            let vfs = Vfs()
            db.setProject(load.model, vfs.paths)
            for ((path, text) in readFiles(load.model.files()).files) {
                vfs.setFileContents(path, text)
            }
            db.applyChanges(vfs, vfs.takeChanges())
            let mainFile = vfs.paths.lookup(dir.join("src/main.cj")).getOrThrow()
            let targets =
                definitionAt(db, mainFile, "package app\nimport org::dep.*\nfunc use(): ".size)

            // assert
            @Expect(load.problems, [])
            @Expect(load.model.modules.map { it => it.name }, ["leaf", "org::dep", "app"])
            @Expect(load.model.modules.map { it => it.member }, [false, false, true])
            @Expect(load.model.modules[1].deps, ["leaf"])
            @Expect(load.model.modules[2].deps, ["org::dep"])
            @Expect(targets.map { target => vfs.paths.path(target.fileId) },
                [dir.join("cache/repository/source/org/dep-1.2.0/src/lib.cj")])
        } finally {
            removeTree(dir)
        }
    }

    @TestCase[format in [0, 1]]
    func scriptsUseTheirOwnVersionsIncludingTransitiveDependencies(format: Int64) {
        // arrange
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[package]\nname = \"app\"\n[target.x86_64-unknown-linux-gnu.test-dependencies]\ndep = {version = \"1.0.0\"}\n[script-dependencies]\ndep = \"2.0.0\"\n"
                    ),
                    ("build.cj", "main() {}\n"),
                    ("cangjie-repo.toml", "[repository.cache]\npath = \"cache\"\n"),
                    (
                        "cjpm.lock",
                        "version = ${format}\n[requires]\ndep = ${registryEntry(format, "1.0.0")}\n[scripts]\ndep = ${registryEntry(format, "2.0.0")}\nhelper = ${registryEntry(format, "3.0.0")}\n"
                    ),
                    (
                        "cache/repository/source/default/dep-1.0.0/cjpm.toml",
                        "[package]\nname = \"dep\"\nversion = \"1.0.0\"\n"
                    ),
                    (
                        "cache/repository/source/default/dep-2.0.0/cjpm.toml",
                        "[package]\nname = \"dep\"\nversion = \"2.0.0\"\n[dependencies]\nhelper = \"3.0.0\"\n"
                    ),
                    (
                        "cache/repository/source/default/helper-3.0.0/cjpm.toml",
                        "[package]\nname = \"helper\"\nversion = \"3.0.0\"\n"
                    )
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()

            // assert
            @Expect(load.problems, [])
            @Expect(load.model.modules.map { it => it.name }, ["dep", "app", "helper", "dep", "default"])
            @Expect(load.model.modules[0].root, dir.join("cache/repository/source/default/dep-1.0.0/src"))
            @Expect(load.model.modules[3].root, dir.join("cache/repository/source/default/dep-2.0.0/src"))
            @Expect(load.model.modules[3].deps, ["helper"])
            @Expect(load.model.modules[4].deps, ["dep"])
        } finally {
            removeTree(dir)
        }
    }

    @TestCase[sample in [
        ("", "cannot read"),
        ("version = 7", "unsupported lock version"),
        ("version = 1\n[requires]", "no locked entry"),
        ("version = 0\n[requires]\ndep = {version = 3}", "cannot read"),
        ("version = 0\n[requires]\ndep = {}", "no version"),
        ("version = 0\n[requires]\ndep = {version = \"../escape\"}", "invalid registry version"),
        ("version = 0\n[requires]\ndep = {version = \"2.0.0\"}", "does not satisfy"),
        ("version = 0\n[requires]\ndep = {git = \"url\", version = \"1.0.0\"}", "not a registry dependency"),
        ("version = 1\n[requires]\ndep = {version = \"1.0.0\", source = \"registry+\"}", "invalid registry lock source"),
        ("version = 1\n[requires]\ndep = {version = \"1.0.0\", source = \"git+url#commit\"}", "invalid registry lock source"),
        ("version = 1\n[requires]\ndep = {version = \"1.0.0\", source = \"registry+url\"}", "no checksum"),
        ("version = 1\n[requires]\ndep = {version = \"1.0.0\", source = \"registry+url\", checksum = \"invalid\"}", "invalid registry lock checksum"),
        ("version = 0\n[requires]\ndep = {version = \"1.0.0\"}", "downloaded sources")
    ]]
    func missingMalformedAndStaleSelectionsAreRecoverable(sample: (String, String)) {
        // arrange
        let dir =
            tree(
                [
                    ("cjpm.toml", "[package]\nname = \"app\"\n[dependencies]\ndep = \"1.0.0\"\n"),
                    ("cangjie-repo.toml", "[repository.cache]\npath = \"cache\"\n")
                ]
            )
        if (!sample[0].isEmpty()) {
            File.writeTo(dir.join("cjpm.lock").filePath.getOrThrow(), sample[0].toArray())
        }
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()

            // assert
            @Expect(load.model.modules.map { it => it.name }, ["app"])
            @Expect(load.problems.size, 1)
            @Expect(load.problems[0].contains(sample[1]), true)
            @Expect(load.problems[0].contains("cjpm update"), true)
        } finally {
            removeTree(dir)
        }
    }

    @TestCase[sample in [("wrong", "1.0.0"), ("dep", "2.0.0")]]
    func cachedManifestMustMatchTheLockedIdentity(sample: (String, String)) {
        // arrange
        let dir =
            tree(
                [
                    ("cjpm.toml", "[package]\nname = \"app\"\n[dependencies]\ndep = \"1.0.0\"\n"),
                    ("cangjie-repo.toml", "[repository.cache]\npath = \"cache\"\n"),
                    ("cjpm.lock", "version = 0\n[requires]\ndep = ${registryEntry(0, "1.0.0")}\n"),
                    (
                        "cache/repository/source/default/dep-1.0.0/cjpm.toml",
                        "[package]\nname = \"${sample[0]}\"\nversion = \"${sample[1]}\"\n"
                    )
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()

            // assert
            @Expect(load.model.modules.size, 1)
            @Expect(load.problems.size, 1)
            @Expect(load.problems[0].contains("cached manifest does not declare"), true)
        } finally {
            removeTree(dir)
        }
    }

    @TestCase[sample in [
        ("1.2.3", "1.2.3", true), ("1.2.3", "1.2.4", false),
        ("[1.2.3,2.0.0)", "1.2.3", true), ("(1.2.3,2.0.0]", "1.2.3", false),
        ("[1.2.3,2.0.0)", "2.0.0", false), ("(1.2.3,2.0.0]", "2.0.0", true),
        ("(,1.0.0]", "0.0.0", true), ("[1.0.0,)", "3.0.0", true),
        ("(,)", "3.0.0", true), ("[2.0.0,1.0.0],1.0.0", "1.0.0", true),
        ("1.2.3, [2.0.0, 3.0.0), (4.0.0,)", "2.1.0", true),
        ("1.2.3, [2.0.0, 3.0.0), (4.0.0,)", "3.1.0", false)
    ]]
    func versionConstraintsMatchCjpmIntervals(sample: (String, String, Bool)) {
        // act
        let matches = registryVersionMatches(sample[0], sample[1])

        // assert
        @Expect(matches, sample[2])
    }

    @TestCase[text in ["", "^1.0.0", "~1.0.0", "*", "1.2", "01.2.3", "1.0.0-beta", "1.0.0+build", "[1.0.0", "[,1.0.0]", "[1.0.0,]", "1.0.0,", "1.0.0,invalid", "[2.0.0,1.0.0]", "(1.0.0,1.0.0)", "(1.0.0,1.0.1)"]]
    func invalidConstraintsAreRejectedEvenAfterAMatchingAlternative(text: String) {
        // act / assert
        @AssertThrows[ProjectException](registryVersionMatches(text, "1.0.0"))
    }
}
