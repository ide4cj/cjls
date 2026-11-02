package project_model

import std.fs.File
import std.unittest.*
import std.unittest.testmacro.*
import loupe.{completionsAt, definitionAt}
import loupe.db.*
import loupe.hir.*
import loupe.vfs.{readFiles, Vfs, VfsPath}

func dependencyImportSource(pkg: String, imported: String): String {
    "package ${pkg}\nimport ${imported}.*\nfunc use(): Helper { Helper() }\n"
}

func testDependencyDatabase(model: ProjectModel): (AnalysisDatabase, Vfs) {
    let db = AnalysisDatabase()
    let vfs = Vfs()
    db.setProject(model, vfs.paths)
    for ((path, text) in readFiles(model.files()).files) {
        vfs.setFileContents(path, text)
    }
    db.applyChanges(vfs, vfs.takeChanges())
    (db, vfs)
}

/**
 * One import must agree across analysis, navigation, completion and diagnostics.
 */
func expectDependencyImport(
    db: AnalysisDatabase,
    vfs: Vfs,
    dir: VfsPath,
    path: String,
    pkg: String,
    imported: String,
    target: ?String
): Unit {
    // arrange
    let fileId = vfs.paths.lookup(dir.join(path)).getOrThrow()
    let file = db.sourceFile(fileId).getOrThrow()
    let source = dependencyImportSource(pkg, imported)
    let importOffset = "package ${pkg}\nimport ".size
    let typeOffset = source.size - "Helper { Helper() }\n".size
    let expected = target.map { path => [dir.join(path)] } ?? []
    let expectedProblems: Array<String> =
        if (target.isSome()) { [] } else { ["error: can not find package '${imported}'"] }

    // act
    let typeTargets =
        definitionAt(db, fileId, typeOffset).map { target => vfs.paths.path(target.fileId) }
    let importTargets =
        definitionAt(db, fileId, importOffset + 1).map { target => vfs.paths.path(target.fileId) }
    let labels =
        completionsAt(db, fileId, importOffset + 1).getOrThrow().items.map { item => item.label }
    let problems =
        scopeDiagnostics(db, packageOfFile(db, file).getOrThrow(), file)
            .map { diagnostic => diagnostic.problem.toString() }

    // assert
    @Expect(typeTargets, expected)
    @Expect(importTargets, expected)
    @Expect(labels.contains(imported), target.isSome())
    @Expect(problems, expectedProblems)
}

@Test
class CjpmTestDependenciesTest {
    @TestCase[targetSpecific in [false, true]]
    func productionCannotImportTestDependency(targetSpecific: Bool) {
        // arrange
        let section =
            if (targetSpecific) {
                "target.x86_64-unknown-linux-gnu.test-dependencies"
            } else {
                "test-dependencies"
            }
        let source = dependencyImportSource("app", "helper")
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[package]\nname = \"app\"\n[${section}]\nhelper = {path = \"helper\"}\n"
                    ),
                    ("src/main.cj", source),
                    ("src/main_test.cj", source),
                    ("helper/cjpm.toml", "[package]\nname = \"helper\"\n"),
                    ("helper/src/lib.cj", "package helper\npublic class Helper {}\n")
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()
            let (db, vfs) = testDependencyDatabase(load.model)
            let json = toProjectJson(load.model, dir)
            let projected = lowerProjectJson(json, dir, env: sdkEnv, cfg: LINUX)
            let ordinary = projected.modules.map { module => module.deps }
            let tests = projected.modules.map { module => module.testDeps }

            // assert
            @Expect(load.problems, [])
            @Expect(ordinary, [Array<String>(), Array<String>()])
            @Expect(tests, [Array<String>(), ["helper"]])
            expectDependencyImport(db, vfs, dir, "src/main.cj", "app", "helper", None)
            expectDependencyImport(
                db,
                vfs,
                dir,
                "src/main_test.cj",
                "app",
                "helper",
                "helper/src/lib.cj"
            )
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func eachDependencyKeepsItsOwnOrdinaryAndTestEdges() {
        // arrange
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[package]\nname = \"app\"\n[test-dependencies]\nhelper = {path = \"helper\"}\n"
                    ),
                    ("src/main_test.cj", dependencyImportSource("app", "helper")),
                    ("src/leaf_test.cj", dependencyImportSource("app", "leaf")),
                    ("src/private_test.cj", dependencyImportSource("app", "privatehelper")),
                    ("build.cj", dependencyImportSource("default", "helper")),
                    (
                        "helper/cjpm.toml",
                        "[package]\nname = \"helper\"\n[dependencies]\nleaf = {path = \"../leaf\"}\n[test-dependencies]\nprivatehelper = {path = \"../privatehelper\"}\n"
                    ),
                    ("helper/src/lib.cj", "package helper\npublic class RootHelper {}\n"),
                    ("helper/src/leaf.cj", dependencyImportSource("helper", "leaf")),
                    ("helper/src/private.cj", dependencyImportSource("helper", "privatehelper")),
                    (
                        "helper/src/private_test.cj",
                        dependencyImportSource("helper", "privatehelper")
                    ),
                    ("leaf/cjpm.toml", "[package]\nname = \"leaf\"\n"),
                    ("leaf/src/lib.cj", "package leaf\npublic class Helper {}\n"),
                    ("privatehelper/cjpm.toml", "[package]\nname = \"privatehelper\"\n"),
                    ("privatehelper/src/lib.cj", "package privatehelper\npublic class Helper {}\n")
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()
            let (db, vfs) = testDependencyDatabase(load.model)

            // assert
            @Expect(load.problems, [])
            expectDependencyImport(db, vfs, dir, "src/leaf_test.cj", "app", "leaf", None)
            expectDependencyImport(
                db,
                vfs,
                dir,
                "src/private_test.cj",
                "app",
                "privatehelper",
                None
            )
            expectDependencyImport(db, vfs, dir, "build.cj", "default", "helper", None)
            expectDependencyImport(
                db,
                vfs,
                dir,
                "helper/src/leaf.cj",
                "helper",
                "leaf",
                "leaf/src/lib.cj"
            )
            expectDependencyImport(
                db,
                vfs,
                dir,
                "helper/src/private.cj",
                "helper",
                "privatehelper",
                None
            )
            expectDependencyImport(
                db,
                vfs,
                dir,
                "helper/src/private_test.cj",
                "helper",
                "privatehelper",
                "privatehelper/src/lib.cj"
            )
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func ordinaryEdgeRemainsOrdinaryWhenAlsoDeclaredForTests() {
        // arrange
        let source = dependencyImportSource("app", "helper")
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[package]\nname = \"app\"\n[dependencies]\nhelper = {path = \"helper\"}\n[target.x86_64-unknown-linux-gnu.test-dependencies]\nhelper = {path = \"helper\"}\n"
                    ),
                    ("src/main.cj", source),
                    ("src/main_test.cj", source),
                    ("helper/cjpm.toml", "[package]\nname = \"helper\"\n"),
                    ("helper/src/lib.cj", "package helper\npublic class Helper {}\n")
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()
            let (db, vfs) = testDependencyDatabase(load.model)
            let ordinary = load.model.modules.map { module => module.deps }
            let tests = load.model.modules.map { module => module.testDeps }

            // assert
            @Expect(load.problems, [])
            @Expect(ordinary, [Array<String>(), ["helper"]])
            @Expect(tests, [Array<String>(), Array<String>()])
            expectDependencyImport(
                db,
                vfs,
                dir,
                "src/main.cj",
                "app",
                "helper",
                "helper/src/lib.cj"
            )
            expectDependencyImport(
                db,
                vfs,
                dir,
                "src/main_test.cj",
                "app",
                "helper",
                "helper/src/lib.cj"
            )
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func testFileReexportsStayInTheirPackageTestContext() {
        // arrange
        let source = "package app\nfunc use(): Helper { Helper() }\n"
        let consumer = dependencyImportSource("consumer", "app")
        let dir =
            tree(
                [
                    ("cjpm.toml", "[workspace]\nmembers = [\"app\", \"consumer\"]\n"),
                    (
                        "app/cjpm.toml",
                        "[package]\nname = \"app\"\n[test-dependencies]\nhelper = {path = \"../helper\"}\n"
                    ),
                    ("app/src/main.cj", source),
                    ("app/src/main_test.cj", source),
                    ("app/src/export_test.cj", "package app\npublic import helper.*\n"),
                    (
                        "consumer/cjpm.toml",
                        "[package]\nname = \"consumer\"\n[dependencies]\napp = {path = \"../app\"}\n"
                    ),
                    ("consumer/src/main_test.cj", consumer),
                    ("helper/cjpm.toml", "[package]\nname = \"helper\"\n"),
                    ("helper/src/lib.cj", "package helper\npublic class Helper {}\n")
                ]
            )
        try {
            // act
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()
            let (db, vfs) = testDependencyDatabase(load.model)
            let production = vfs.paths.lookup(dir.join("app/src/main.cj")).getOrThrow()
            let test = vfs.paths.lookup(dir.join("app/src/main_test.cj")).getOrThrow()
            let downstream = vfs.paths.lookup(dir.join("consumer/src/main_test.cj")).getOrThrow()
            let offset = source.size - "Helper { Helper() }\n".size
            let productionTargets = definitionAt(db, production, offset)
            let testTargets =
                definitionAt(db, test, offset).map { target => vfs.paths.path(target.fileId) }
            let downstreamTargets =
                definitionAt(db, downstream, consumer.size - "Helper { Helper() }\n".size)

            // assert
            @Expect(load.problems, [])
            @Expect(productionTargets.isEmpty())
            @Expect(testTargets, [dir.join("helper/src/lib.cj")])
            @Expect(downstreamTargets.isEmpty())
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func changingOnlyEdgeScopeInvalidatesExistingAnalysis() {
        // arrange
        let source = dependencyImportSource("app", "helper")
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[package]\nname = \"app\"\n[dependencies]\nhelper = {path = \"helper\"}\n"
                    ),
                    ("src/main.cj", source),
                    ("src/main_test.cj", source),
                    ("helper/cjpm.toml", "[package]\nname = \"helper\"\n"),
                    ("helper/src/lib.cj", "package helper\npublic class Helper {}\n")
                ]
            )
        try {
            let first = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()
            let (db, vfs) = testDependencyDatabase(first.model)
            expectDependencyImport(
                db,
                vfs,
                dir,
                "src/main.cj",
                "app",
                "helper",
                "helper/src/lib.cj"
            )

            // act
            File
                .writeTo(
                    dir.join("cjpm.toml").filePath.getOrThrow(),
                    "[package]\nname = \"app\"\n[test-dependencies]\nhelper = {path = \"helper\"}\n"
                        .toArray()
                )
            let second =
                loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()
            db.setProject(second.model, vfs.paths)

            // assert
            expectDependencyImport(db, vfs, dir, "src/main.cj", "app", "helper", None)
            expectDependencyImport(
                db,
                vfs,
                dir,
                "src/main_test.cj",
                "app",
                "helper",
                "helper/src/lib.cj"
            )
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func testOnlyMacrosArePlannedWithoutTheirTestRuntimeImports() {
        // arrange
        let source = "package app\nimport helper.*\n@A class C {}\n"
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[package]\nname = \"app\"\n[test-dependencies]\nhelper = {path = \"helper\"}\n"
                    ),
                    ("src/main.cj", source),
                    ("src/main_test.cj", source),
                    (
                        "helper/cjpm.toml",
                        "[package]\nname = \"helper\"\n[test-dependencies]\nprivatehelper = {path = \"../privatehelper\"}\n"
                    ),
                    (
                        "helper/src/lib.cj",
                        "macro package helper\npublic macro A(input: Tokens): Tokens { input }\n"
                    ),
                    ("helper/src/lib_test.cj", "package helper\nimport privatehelper.*\n"),
                    ("privatehelper/cjpm.toml", "[package]\nname = \"privatehelper\"\n"),
                    ("privatehelper/src/lib.cj", "package privatehelper\npublic class Helper {}\n")
                ]
            )
        try {
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()
            let (db, vfs) = testDependencyDatabase(load.model)
            let production =
                db.sourceFile(vfs.paths.lookup(dir.join("src/main.cj")).getOrThrow()).getOrThrow()
            let test =
                db
                    .sourceFile(vfs.paths.lookup(dir.join("src/main_test.cj")).getOrThrow())
                    .getOrThrow()
            let pkg = PackageRef.Source(packageOfFile(db, test).getOrThrow())

            // act
            let productionRequests = macroRequests(db, production)
            let testRequests = macroRequests(db, test)
            let plan = macroBuildPlan(db)
            let planned = plan.map { unit => unit.pkg.name(db) }
            let expansionIsTest =
                testRequests.map { request => isTestOf(db, pkg, ItemFile.Expansion(request.call)) }
            let linked = plan.map { unit => unit.deps.map { pkg => pkg.name(db) } }

            // assert
            @Expect(load.problems, [])
            @Expect(productionRequests.size, 0)
            @Expect(testRequests.size, 1)
            @Expect(expansionIsTest, [true])
            @Expect(planned, ["helper"])
            @Expect(linked, [Array<String>()])
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func downstreamTestsCannotMakeProductionImportsCyclic() {
        // arrange
        let source = dependencyImportSource("app", "helper")
        let dir =
            tree(
                [
                    (
                        "cjpm.toml",
                        "[package]\nname = \"app\"\n[dependencies]\nhelper = {path = \"helper\"}\n"
                    ),
                    ("src/main.cj", source),
                    (
                        "helper/cjpm.toml",
                        "[package]\nname = \"helper\"\n[test-dependencies]\napp = {path = \"..\"}\n"
                    ),
                    ("helper/src/lib.cj", "package helper\npublic class Helper {}\n"),
                    ("helper/src/lib_test.cj", "package helper\nimport app.*\n")
                ]
            )
        try {
            let load = loadCjpmProject(dir.join("cjpm.toml"), env: sdkEnv, cfg: LINUX).getOrThrow()
            let (db, vfs) = testDependencyDatabase(load.model)
            let file =
                db.sourceFile(vfs.paths.lookup(dir.join("src/main.cj")).getOrThrow()).getOrThrow()

            // act
            let problems = scopeDiagnostics(db, packageOfFile(db, file).getOrThrow(), file)

            // assert
            @Expect(load.problems, [])
            @Expect(problems.isEmpty())
        } finally {
            removeTree(dir)
        }
    }
}
