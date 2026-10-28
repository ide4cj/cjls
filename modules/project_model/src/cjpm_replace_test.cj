package project_model

import std.fs.File
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.*
import loupe.findReferences
import loupe.hir.*
import loupe.vfs.*
import rope.Rope

@Test
class CjpmReplaceTest {
    @TestCase
    func entryReplacementSelectsTheIndirectPath() {
        // arrange
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        #"
[package]
name = "app"
[dependencies]
a = {path = "a"}
[replace]
leaf = {path = "new"}
"#
                    ),
                    (
                        "a/cjpm.toml",
                        #"
[package]
name = "a"
[dependencies]
leaf = {path = "../old"}
[replace]
leaf = {path = "../ignored"}
"#
                    ),
                    (
                        "ignored/cjpm.toml",
                        #"
[package]
name = "leaf"
"#
                    ),
                    (
                        "old/cjpm.toml",
                        #"
[package]
name = "leaf"
"#
                    ),
                    (
                        "new/cjpm.toml",
                        #"
[package]
name = "leaf"
"#
                    ),
                    (
                        "new/src/lib.cj",
                        #"
package leaf
public class Selected {}
"#
                    )
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()
            // assert
            @Expect(load.problems, [])
            @Expect(load.model.modules.map { it => it.name }, ["leaf", "a", "app"])
            @Expect(load.model.modules[0].root, dir.join("new/src"))
        } finally {
            removeTree(dir)
        }
    }
    @TestCase[script in [false, true]]
    func conflictingPathsProduceOneSelectionAndARecoverableProblem(script: Bool) {
        // arrange
        let section = if (script) { "[script-dependencies]\n" } else { "[dependencies]\n" }
        let scope = if (script) { "build-script" } else { "ordinary/test" }
        let remedy = if (script) { "Align script dependency declarations" } else { "[replace]" }
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "\n[package]\nname = \"app\"\n${section}\na = {path = \"a\"}\nleaf = {path = \"new\"}\n"
                    ),
                    ("build.cj", "main() {}\n"),
                    (
                        "a/cjpm.toml",
                        #"
[package]
name = "a"
[dependencies]
leaf = {path = "../old"}
"#
                    ),
                    (
                        "old/cjpm.toml",
                        #"
[package]
name = "leaf"
"#
                    ),
                    (
                        "new/cjpm.toml",
                        #"
[package]
name = "leaf"
"#
                    )
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()
            let leaves = load.model.modules.filter { it => it.name == "leaf" }
            // assert
            @Expect(leaves.size, 1)
            @Expect(load.problems.size, 1)
            @Expect(load.problems[0].contains("Conflicting ${scope} dependency `leaf`"))
            @Expect(load.problems[0].contains(remedy))
            @Expect(leaves[0].root, dir.join("old/src"))
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func aSharedPathKeepsIndependentImportsAndPhysicalReferences() {
        // arrange
        withSharedPathProject {
            context =>
            let db = context.db
            let shared = context.shared
            // act
            let firstPackage = shared[0].packages(db)[0]
            let secondPackage = shared[1].packages(db)[0]
            let index = packageIndex(db)
            let ordinary = index.find("leaf", from: PackageRef.Source(firstPackage)).getOrThrow()
            let script = index.find("leaf", from: PackageRef.Source(secondPackage)).getOrThrow()
            let scriptLeafPackage = sourcePackage(script)
            let scriptLeafFile = db.sourceFile(scriptLeafPackage.files(db)[0]).getOrThrow()
            let references =
                findReferences(db, scriptLeafFile.fileId(db), "package leaf\npublic class ".size)
            let ordinaryMap = defMap(db, ordinary)
            let scriptMap = defMap(db, script)
            let firstFile = sourceItemFile(filesOf(db, PackageRef.Source(firstPackage))[0])
            // assert
            @Expect(ordinary != script)
            @Expect(filesOf(db, script)[0], ItemFile.Source(scriptLeafFile))
            @Expect(references.filter { it => it.fileId == firstFile.fileId(db) }.size, 2)
            @Expect(ordinaryMap.names.contains("Ordinary"))
            @Expect(!ordinaryMap.names.contains("Script"))
            @Expect(scriptMap.names.contains("Script"))
            @Expect(!scriptMap.names.contains("Ordinary"))
        }
    }

    @TestCase
    func aSharedPathKeepsIndependentSignaturesAndBodies() {
        // arrange
        withSharedPathProject {
            context =>
            let db = context.db
            let firstPackage = context.shared[0].packages(db)[0]
            let secondPackage = context.shared[1].packages(db)[0]
            // act
            let firstFile = sourceItemFile(filesOf(db, PackageRef.Source(firstPackage))[0])
            let secondFile = sourceItemFile(filesOf(db, PackageRef.Source(secondPackage))[0])
            let firstDef =
                defMap(db, PackageRef.Source(firstPackage)).names.get("selected").getOrThrow()[0].id
            let secondDef =
                defMap(db, PackageRef.Source(secondPackage))
                    .names
                    .get("selected")
                    .getOrThrow()[0]
                    .id
            let firstSignature = signatureTypes(db, firstDef)
            let secondSignature = signatureTypes(db, secondDef)
            let firstBody = inferBody(db, firstDef)
            let secondBody = inferBody(db, secondDef)
            // assert
            @Expect(firstFile != secondFile)
            @Expect(firstSignature.ty != secondSignature.ty)
            @Expect(firstBody.ty, firstSignature.ty)
            @Expect(secondBody.ty, secondSignature.ty)
            @Expect(!firstBody.names.isEmpty())
            @Expect(firstBody.names != secondBody.names)
            @Expect(packageOfFile(db, firstFile), Some(firstPackage))
            @Expect(packageOfFile(db, secondFile), Some(secondPackage))
        }
    }

    @TestCase
    func aSharedPathRetainsScopesThroughModelMergeAndJson() {
        // arrange
        withSharedPathProject {
            context =>
            // act
            let merged = ProjectModel.merge([context.model], LINUX)
            let roundTripped =
                lowerProjectJson(
                    toProjectJson(context.model, context.dir),
                    context.dir,
                    env: sdkEnv
                )
            // assert
            @Expect(context.shared.size, 2)
            @Expect(merged.modules.size, context.model.modules.size)
            @Expect(roundTripped, context.model)
        }
    }

    @TestCase
    func aPhysicalEditUpdatesEveryContextAndSurvivesReload() {
        // arrange
        withSharedPathProject {
            context =>
            let db = context.db
            let firstPackage = context.shared[0].packages(db)[0]
            let secondPackage = context.shared[1].packages(db)[0]
            let firstFile = sourceItemFile(filesOf(db, PackageRef.Source(firstPackage))[0])
            let secondFile = sourceItemFile(filesOf(db, PackageRef.Source(secondPackage))[0])
            let changed =
                Rope(
                    "package shared\nimport leaf.*\npublic func selected(): Selected { Selected() }\npublic func added() {}\n"
                )
            // act
            db.setFileText(firstFile.fileId(db), changed)
            let firstEdited = defMap(db, PackageRef.Source(firstPackage))
            let secondEdited = defMap(db, PackageRef.Source(secondPackage))
            // assert
            @Expect(firstFile.text(db), changed)
            @Expect(secondFile.text(db), changed)
            @Expect(firstEdited.names.contains("added"))
            @Expect(secondEdited.names.contains("added"))

            // act
            reloadSharedPathProject(context)
            let restored = db.sourceFile(firstFile.fileId(db), context: secondPackage)
            // assert
            @Expect(restored, Some(secondFile))
            @Expect(secondFile.text(db), changed)
        }
    }

    @TestCase
    func aScopedConfigurationDoesNotChangeTheOrdinaryContext() {
        // arrange
        withSharedPathProject {
            context =>
            let db = context.db
            let firstFile =
                sourceItemFile(filesOf(db, PackageRef.Source(context.shared[0].packages(db)[0]))[0])
            let secondFile =
                sourceItemFile(filesOf(db, PackageRef.Source(context.shared[1].packages(db)[0]))[0])
            // act
            context.shared[1].setCfg(db).to(Some(Cfg([("selection", "script")])))
            let firstCfg = cfgOfFile(db, firstFile)
            let secondCfg = cfgOfFile(db, secondFile)
            // assert
            @Expect(firstCfg.get("selection"), None)
            @Expect(secondCfg.get("selection"), Some("script"))
        }
    }

    @TestCase[registryFirst in [true, false]]
    func pathSelectionsOverrideRegistryRequirementsRegardlessOfTraversal(registryFirst: Bool) {
        // arrange
        let path = "leaf = {path = \"old\"}\n"
        let indirectPath = "leaf = {path = \"../old\"}\n"
        let registry = "leaf = \"999.0.0\"\n"
        let direct = if (registryFirst) { registry } else { path }
        let indirect = if (registryFirst) { indirectPath } else { registry }
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[package]\nname = \"app\"\n[dependencies]\na = {path = \"a\"}\n${direct}"
                    ),
                    ("a/cjpm.toml", "[package]\nname = \"a\"\n[dependencies]\n${indirect}"),
                    ("old/cjpm.toml", "[package]\nname = \"leaf\"\n")
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()
            // assert - no lock or registry cache is needed for the overridden requirement.
            @Expect(load.problems, [])
            @Expect(load.model.modules.map { it => it.name }, ["leaf", "a", "app"])
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func everyRegistryRequirementChecksTheLockedSelection() {
        // arrange
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        #"
[package]
name = "app"
[dependencies]
a = {path = "a"}
leaf = "2.0.0"
"#
                    ),
                    (
                        "a/cjpm.toml",
                        #"
[package]
name = "a"
[dependencies]
leaf = "1.0.0"
"#
                    ),
                    ("cangjie-repo.toml", "[repository.cache]\npath = \"cache\"\n"),
                    ("cjpm.lock", "version = 0\n[requires]\nleaf = {version = \"1.0.0\"}\n"),
                    (
                        "cache/repository/source/default/leaf-1.0.0/cjpm.toml",
                        "[package]\nname = \"leaf\"\nversion = \"1.0.0\"\n"
                    )
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()
            // assert
            @Expect(load.problems.size, 1)
            @Expect(load.problems[0].contains("does not satisfy `2.0.0`"))
            @Expect(load.model.modules.filter { it => it.name == "leaf" }.size, 1)
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func entryReplacementsLeaveTheScriptSelectionIndependent() {
        // arrange
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        #"
[package]
name = "app"
[dependencies]
leaf = {path = "old"}
[script-dependencies]
leaf = {path = "old"}
[replace]
leaf = {path = "new"}
"#
                    ),
                    ("build.cj", "main() {}\n"),
                    ("old/cjpm.toml", "[package]\nname = \"leaf\"\n"),
                    ("new/cjpm.toml", "[package]\nname = \"leaf\"\n")
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()
            let leaves = load.model.modules.filter { it => it.name == "leaf" }
            // assert
            @Expect(load.problems, [])
            @Expect(leaves.map { it => it.root }, [dir.join("new/src"), dir.join("old/src")])
            @Expect(leaves[0].resolutionScope.isEmpty())
            @Expect(!leaves[1].resolutionScope.isEmpty())
        } finally {
            removeTree(dir)
        }
    }
    @TestCase[replaced in [true, false]]
    func conflictingGitDeclarationsHaveOneRecoverableSelection(replaced: Bool) {
        // arrange
        let first = "https://example.invalid/first.git"
        let second = "https://example.invalid/second.git"
        let replacement = if (replaced) { "[replace]\nleaf = {git = \"${second}\"}\n" } else { "" }
        let selected = if (replaced) { second } else { first }
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[package]\nname = \"app\"\n[dependencies]\na = {path = \"a\"}\nleaf = {git = \"${second}\"}\n${replacement}"
                    ),
                    (
                        "a/cjpm.toml",
                        "[package]\nname = \"a\"\n[dependencies]\nleaf = {git = \"${first}\"}\n"
                    ),
                    ("cangjie-repo.toml", "[repository.cache]\npath = \"cache\"\n"),
                    (
                        "cjpm.lock",
                        "version = 1\n[requires]\nleaf = {source = \"git+${selected}#${GIT_COMMIT}\"}\n"
                    ),
                    ("cache/git/leaf/${GIT_COMMIT}/cjpm.toml", "[package]\nname = \"leaf\"\n")
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()
            // assert
            @Expect(load.problems.size, if (replaced) { 0 } else { 1 })
            @Expect(load.model.modules.filter { it => it.name == "leaf" }.size, 1)
            @Expect(load.model.modules.map { it => it.deps }, [[], ["leaf"], ["a", "leaf"]])
        } finally {
            removeTree(dir)
        }
    }
    @TestCase[reached in [true, false]]
    func registryReplacementsRequireSingleVersionsEvenWhenUnused(reached: Bool) {
        // arrange
        let dependency = if (reached) { "[dependencies]\nleaf = {path = \"old\"}\n" } else { "" }
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[package]\nname = \"app\"\n${dependency}[replace]\nleaf = \"[1.0.0, 2.0.0)\"\n"
                    ),
                    ("old/cjpm.toml", "[package]\nname = \"leaf\"\n")
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()
            // assert
            @Expect(load.problems.size, 1)
            @Expect(load.problems[0].contains("must select a single registry version"))
            @Expect(load.model.modules.map { it => it.name }, ["app"])
        } finally {
            removeTree(dir)
        }
    }
}

/**
 * Both graph selections over the same physical source, with independent transitive imports.
 */
struct SharedPathContext {
    SharedPathContext(
        let dir: VfsPath,
        let db: AnalysisDatabase,
        let paths: PathInterner,
        let model: ProjectModel,
        let shared: Array<Module>
    ) {}
}

/**
 * Loads the two graphs into analysis and releases their temporary files after the scenario.
 */
func withSharedPathProject(check: (SharedPathContext) -> Unit): Unit {
    let dir = sharedPathTree()
    try {
        let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv).getOrThrow()
        let db = AnalysisDatabase()
        let vfs = Vfs()
        db.setProject(load.model, vfs.paths)
        for ((path, text) in readFiles(load.model.files()).files) {
            vfs.setFileContents(path, text)
        }
        db.applyChanges(vfs, vfs.takeChanges())
        let shared = db.project().getOrThrow().modules(db).filter { it => it.name(db) == "shared" }
        @Assert(load.problems, [])
        @Assert(shared.size, 2)
        check(SharedPathContext(dir, db, vfs.paths, load.model, shared))
    } finally {
        removeTree(dir)
    }
}

/**
 * Removes then restores the script graph while preserving the edited physical source.
 */
func reloadSharedPathProject(context: SharedPathContext): Unit {
    // arrange
    let manifestPath = context.dir.join("cjpm.toml").filePath.getOrThrow()
    let original = File.readFrom(manifestPath)
    // act
    File
        .writeTo(
            manifestPath,
            "[package]\nname = \"app\"\n[dependencies]\nshared = {path = \"shared\"}\n".toArray()
        )
    context
        .db
        .setProject(
            loadCjpmProject(context.dir.join("cjpm.toml"), env: sdkEnv).getOrThrow().model,
            context.paths
        )
    let removed =
        context
            .db
            .project()
            .getOrThrow()
            .modules(context.db)
            .filter { it => it.name(context.db) == "shared" }
    // assert
    @Expect(removed.size, 1)
    // act
    File.writeTo(manifestPath, original)
    context
        .db
        .setProject(
            loadCjpmProject(context.dir.join("cjpm.toml"), env: sdkEnv).getOrThrow().model,
            context.paths
        )
}

/**
 * Extracts a source package from this fixture, where a binary indicates incorrect loading.
 *
 * @throws IllegalStateException - if loading produced a binary package
 */
func sourcePackage(pkg: PackageRef): Package {
    match (pkg) {
        case PackageRef.Source(source) => source
        case _ => throw IllegalStateException("expected source package")
    }
}

/**
 * Extracts a source input from this fixture's package files.
 *
 * @throws IllegalStateException - if loading produced a binary file
 */
func sourceItemFile(item: ItemFile): SourceFile {
    match (item) {
        case ItemFile.Source(file) => file
        case _ => throw IllegalStateException("expected source")
    }
}

/**
 * Creates a shared local dependency with distinct locked Git dependencies in the two graphs.
 */
func sharedPathTree(): VfsPath {
    const FIRST_COMMIT = "1111111111111111111111111111111111111111"
    const SECOND_COMMIT = "2222222222222222222222222222222222222222"
    tree(
        [
            (
                "cjpm.toml",
                #"
[package]
name = "app"
[dependencies]
a = {path = "a"}
shared = {path = "shared"}
leaf = {git = "https://example.invalid/leaf"}
[script-dependencies]
shared = {path = "shared"}
leaf = {git = "https://example.invalid/leaf"}
"#
            ),
            (
                "a/cjpm.toml",
                #"
[package]
name = "a"
[script-dependencies]
shared = {path = "../shared"}
"#
            ),
            ("a/build.cj", "main() {}\n"),
            ("src/main.cj", "package app\n"),
            ("build.cj", "main() {}\n"),
            (
                "shared/cjpm.toml",
                #"
[package]
name = "shared"
[dependencies]
leaf = {git = "https://example.invalid/leaf"}
"#
            ),
            (
                "shared/src/lib.cj",
                "package shared\nimport leaf.*\npublic func selected(): Selected { Selected() }\n"
            ),
            (
                "cangjie-repo.toml",
                #"
[repository.cache]
path = "cache"
"#
            ),
            (
                "cjpm.lock",
                "version = 1\n[requires]\nleaf = {source = \"git+https://example.invalid/leaf#${FIRST_COMMIT}\"}\n[scripts]\nleaf = {source = \"git+https://example.invalid/leaf#${SECOND_COMMIT}\"}\n"
            ),
        ]
            .concat(sharedPathGitFiles(FIRST_COMMIT, SECOND_COMMIT))
    )
}

/**
 * Cached versions distinguish the declarations available through the two graphs.
 */
func sharedPathGitFiles(first: String, second: String): Array<(String, String)> {
    [
        ("cache/git/leaf/${first}/cjpm.toml", "[package]\nname = \"leaf\"\n"),
        (
            "cache/git/leaf/${first}/src/lib.cj",
            "package leaf\npublic class Selected {}\npublic class Ordinary {}\n"
        ),
        ("cache/git/leaf/${second}/cjpm.toml", "[package]\nname = \"leaf\"\n"),
        (
            "cache/git/leaf/${second}/src/lib.cj",
            "package leaf\npublic class Selected {}\npublic class Script {}\n"
        )
    ]
}
