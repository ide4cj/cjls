package loupe

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import rope.Rope
import loupe.db.*
import loupe.fixture.*
import loupe.hir.*
import loupe.vfs.PathInterner

@Test
class SemanticRelationshipContextTest {
    @TestCase
    func equalPhysicalLocationsRetainIndependentGraphIdentities(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "//- /lib.cj module=m package=m\npackage m\npublic func target() {}\npublic func caller() { target() }"
        )
        let ordinary = fixture.projectModel().modules[0]
        let script = ModuleModel(
            ordinary.name,
            ordinary.root,
            ordinary.packages,
            resolutionScope: "script"
        )
        let db = AnalysisDatabase()
        let paths = PathInterner()
        db.setProject(ProjectModel(Cfg([]), [ordinary, script]), paths)
        let written = fixture.files[0]
        let fileId = paths.intern(written.path)
        db.setFileText(fileId, Rope(written.text))
        let modules = db.project().getOrThrow().modules(db)
        let ordinaryFile = db.sourceFile(fileId, context: modules[0].packages(db)[0]).getOrThrow()
        let scriptFile = db.sourceFile(fileId, context: modules[1].packages(db)[0]).getOrThrow()
        let analysis = SemanticAnalysis(db)
        let offset = written.text.indexOf("target").getOrThrow()
        let first =
            analysis
                .inFile(ItemFile.Source(ordinaryFile), offset)
                .getOrThrow()
                .definitions
                .getOrThrow()[0]
        let second =
            analysis
                .inFile(ItemFile.Source(scriptFile), offset)
                .getOrThrow()
                .definitions
                .getOrThrow()[0]

        // act
        let ordinaryUses = first.usages().getOrThrow().entries
        let scriptUses = second.usages().getOrThrow().entries
        let ordinaryIncoming = first.incomingCalls()
        let scriptIncoming = second.incomingCalls()

        // assert
        @Expect(first.identity != second.identity)
        @Expect(ordinaryUses.size, 2)
        @Expect(scriptUses.size, 2)
        @Expect(ordinaryUses.all { use => use.location.file == ItemFile.Source(ordinaryFile) })
        @Expect(scriptUses.all { use => use.location.file == ItemFile.Source(scriptFile) })
        @Expect(ordinaryUses.map { use => use.location.focusRange }, scriptUses.map { use => use.location.focusRange })
        @Expect(ordinaryIncoming.size, 1)
        @Expect(scriptIncoming.size, 1)
        @Expect(ordinaryIncoming[0].site.focusRange, scriptIncoming[0].site.focusRange)
        @Expect(ordinaryIncoming[0].caller.identity != scriptIncoming[0].caller.identity)
        @Expect(ordinaryIncoming[0].callee.identity, first.identity)
        @Expect(scriptIncoming[0].callee.identity, second.identity)
    }

    @TestCase
    func testOnlyDependencyUsagesDoNotLoseTestImportVisibility(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "//- /lib.cj module=helper package=helper\npackage helper\npublic func target() {}\n//- /app/main.cj module=app package=app\npackage app\nfunc plain() {}\n//- /app/main_test.cj module=app package=app\npackage app\nimport helper.target\nfunc check() { target() }"
        )
        let model = fixture.projectModel()
        let helper = model.modules[0]
        let original = model.modules[1]
        let app = ModuleModel(original.name, original.root, original.packages, testDeps: ["helper"])
        let db = AnalysisDatabase()
        let paths = PathInterner()
        db.setProject(ProjectModel(Cfg([]), [helper, app]), paths)
        for (file in fixture.files) {
            db.setFileText(paths.intern(file.path), Rope(file.text))
        }
        let written = fixture.files[0]
        let analysis = SemanticAnalysis(db)
        let target =
            analysis
                .at(paths.intern(written.path), written.text.indexOf("target").getOrThrow())
                .getOrThrow()
                .definitions
                .getOrThrow()[0]

        // act
        let uses = target.usages().getOrThrow().entries
        let incoming = target.incomingCalls()

        // assert
        @Expect(uses.size, 3)
        @Expect(uses.filter { use => !use.isDeclaration }.size, 2)
        @Expect(incoming.size, 1)
        @Expect(incoming[0].site.excerpt(), Some("target"))
    }
}
