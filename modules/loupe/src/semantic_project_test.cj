package loupe

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import calca.CancelledException
import rope.Rope
import loupe.db.*
import loupe.fixture.*
import loupe.hir.*
import loupe.vfs.PathInterner

@Test
class SemanticProjectTest {
    @TestCase
    func importsExportsAndPotentialDependentsComposeWithObjects(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /a.cj module=lib package=lib
            package lib
            public func target() {}
            private func secret() {}
            //- /b.cj module=bridge package=bridge deps=lib
            package bridge
            public import lib.target as exported
            //- /app.cj module=app package=app deps=bridge
            package app
            import bridge.exported as alias
            func f() { ali$0as() }
            //- /unused.cj module=unused package=unused deps=lib
            package unused
            "#
        )
        let db = fixture.database()
        let analysis = SemanticAnalysis(db)
        let cursor = fixture.cursor.getOrThrow()

        // act
        let occurrence = analysis.at(cursor.fileId, cursor.offset).getOrThrow()
        let file = occurrence.contextualFile()
        let target = occurrence.definitions.getOrThrow()[0]
        let lib = target.contextualPackage().getOrThrow()
        let imports = file.imports().getOrThrow()
        let bridge = imports[0].target.getOrThrow()

        // assert
        @Expect(file.contextualPackage().getOrThrow().name(), "app")
        @Expect(lib.name(), "lib")
        @Expect(imports.size, 1)
        @Expect(imports[0].path.alias, Some("alias"))
        @Expect(imports[0].names[0].target.identity, target.identity)
        @Expect(imports[0].location().getOrThrow().excerpt().getOrThrow().contains("bridge.exported"))
        @Expect(bridge.exports().names.map { name => name.name }, ["exported"])
        @Expect(bridge.imports().getOrThrow()[0].isReExport)
        @Expect(lib.exports().names.map { name => name.name }, ["target"])
        @Expect(lib.writtenImporters().entries.size, 1)
        @Expect(lib.writtenImporters().entries[0].file.contextualPackage().getOrThrow().name(), "bridge")
        @Expect(lib.potentialDependents().map { pkg => pkg.name() }.contains("unused"))
        @Expect(!lib.potentialDependents().map { pkg => pkg.name() }.contains("app"))
        let reverse =
            lib.writtenImporters().entries.map { one => one.file.contextualPackage().getOrThrow() }
        let downstream =
            bridge
                .writtenImporters()
                .entries
                .map { one => one.file.contextualPackage().getOrThrow() }
        @Expect(target.usages(inPackages: reverse.concat(downstream)).getOrThrow().entries.any { use =>
            use.location.excerpt() == Some("alias")
        })
        @Expect(bridge.exports().names[0].site.isSome())
        @Expect(file.visibleNames().getOrThrow().any { name => name.name == "alias" && name.site.isSome() })
        @Expect(analysis.project().getOrThrow().files().size, 4)
    }

    @TestCase
    func contextsSharingPhysicalFilesRetainDifferentDependenciesAndUsages(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /app.cj module=app package=app
            package app
            import helper.target
            func caller() { target() }
            //- /helper.cj module=helper package=helper
            package helper
            public func target() {}
            "#
        )
        let originals = fixture.projectModel().modules
        let ordinary = ModuleModel(
            "app",
            originals[0].root,
            originals[0].packages,
            deps: ["helper"]
        )
        let script = ModuleModel(
            "app",
            originals[0].root,
            originals[0].packages,
            deps: ["helper"],
            resolutionScope: "script"
        )
        let scriptHelper = ModuleModel(
            "helper",
            originals[1].root,
            originals[1].packages,
            member: false,
            resolutionScope: "script"
        )
        let db = AnalysisDatabase()
        let paths = PathInterner()
        db.setProject(ProjectModel(Cfg([]), [ordinary, originals[1], script, scriptHelper]), paths)
        for (file in fixture.files) {
            db.setFileText(paths.intern(file.path), Rope(file.text))
        }
        let analysis = SemanticAnalysis(db)
        let modules = analysis.project().getOrThrow().modules()
        let first = modules[0].packages()[0].files()[0]
        let second = modules[2].packages()[0].files()[0]
        let offset = fixture.files[0].text.indexOf("target()").getOrThrow()

        // act
        let firstTarget = first.at(offset).getOrThrow().definitions.getOrThrow()[0]
        let secondTarget = second.at(offset).getOrThrow().definitions.getOrThrow()[0]

        // assert
        @Expect(first.identity != second.identity)
        @Expect(firstTarget.identity != secondTarget.identity)
        @Expect(firstTarget.contextualPackage().getOrThrow().module().getOrThrow().resolutionScope(), "")
        @Expect(secondTarget.contextualPackage().getOrThrow().module().getOrThrow().resolutionScope(), "script")
        @Expect(modules[2].dependencies()[0].modules[0].identity, modules[3].identity)
        @Expect(!modules[3].isWorkspaceMember())
        @Expect(secondTarget.contextualPackage().getOrThrow().writtenImporters().entries.size, 1)
        @Expect(secondTarget.usages().getOrThrow().entries.all { use =>
            use.location.contextualFile().contextualPackage().getOrThrow().module().getOrThrow().resolutionScope() == "script"
        })
        @Expect(second.at(offset).getOrThrow().contextualFile().identity, second.identity)
    }

    @TestCase
    func testPermissionsAndImplicitImportsDoNotBecomeWrittenImports(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /helper.cj module=helper package=helper
            package helper
            public func target() {}
            //- /app/main.cj module=app package=app
            package app
            import helper.target
            //- /app/main_test.cj module=app package=app
            package app
            import helper.target
            func check() { target() }
            //- /core.cj module=std package=std.core
            package std.core
            public struct String {}
            //- /unit.cj module=std package=std.unittest
            package std.unittest
            public func expect() {}
            //- /macro.cj module=std package=std.unittest.testmacro
            macro package std.unittest.testmacro
            "#
        )
        let model = fixture.projectModel()
        let original = model.modules[1]
        let app = ModuleModel(original.name, original.root, original.packages, testDeps: ["helper"])
        let db = AnalysisDatabase()
        let paths = PathInterner()
        db.setProject(ProjectModel(Cfg([]), [model.modules[0], app, model.modules[2]]), paths)
        for (file in fixture.files) {
            db.setFileText(paths.intern(file.path), Rope(file.text))
        }
        let analysis = SemanticAnalysis(db)
        let pkg = analysis.project().getOrThrow().modules()[1].packages()[0]
        let plain = pkg.files()[0]
        let test = pkg.files()[1]

        // act
        let plainImport = plain.imports().getOrThrow()[0]
        let testImport = test.imports().getOrThrow()[0]

        // assert
        @Expect(!plain.isTest())
        @Expect(test.isTest())
        @Expect(plainImport.error.isSome())
        @Expect(testImport.error.isNone())
        @Expect(testImport.names.size, 1)
        @Expect(pkg.module().getOrThrow().dependencies()[0].testOnly)
        @Expect(!pkg.permittedPackages().any { one => one.name() == "helper" })
        @Expect(pkg.permittedPackages(ofTests: true).any { one => one.name() == "helper" })
        @Expect(plain.implicitImports().getOrThrow().size, 1)
        @Expect(test.implicitImports().getOrThrow().size, 3)
        @Expect(test.implicitImports().getOrThrow().filter { one => one.isTestImport }.size, 2)
        @Expect(test.imports().getOrThrow().size, 1)
    }

    @TestCase
    func inactiveAndUnknownConditionsExposeLoadedEvidence(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m cfg=os:Linux
            package m
            @When[os == "Windows"]
            public func windows() {}
            @When[custom == "yes"]
            public func unknown() {}
            //- /other.cj module=m package=m inactive=windows
            package m
            func excluded() {}
            "#
        )
        let db = fixture.database()
        let project = SemanticAnalysis(db).project().getOrThrow()
        let module = project.modules()[0]
        let pkg = module.packages()[0]
        let file = pkg.files()[0]

        // act
        let conditions = file.conditions().getOrThrow()
        let cfg = file.configuration().getOrThrow()

        // assert
        @Expect(cfg.cfg.get("os"), Some("Linux"))
        @Expect(!cfg.completeCompilerInvocation)
        @Expect(cfg.loadingProblems.isNone())
        @Expect(cfg.selectionProvenance.isNone())
        @Expect(cfg.selectedSourceSets.isNone())
        @Expect(conditions.size, 2)
        @Expect(conditions[0].evaluation, Some(false))
        @Expect(!conditions[0].reasons.isEmpty())
        @Expect(conditions[1].evaluation.isNone())
        @Expect(file.whenStatus().getOrThrow().inactive.size, 1)
        @Expect(module.inactiveFiles().size, 1)
        @Expect(module.inactiveFiles()[0].reason.contains("windows"))
        @Expect(pkg.files().size, 1)
        @Expect(pkg.exports().names.map { name => name.name }, ["unknown"])
    }

    @TestCase
    func noProjectEmptyImportsAndUnresolvedImportsRemainDifferent(): Unit {
        // arrange
        let empty = AnalysisDatabase()
        let fixture = Fixture.parse("import missing.name\nfunc f() {}")
        let db = fixture.database()
        let project = SemanticAnalysis(db).project().getOrThrow()
        let file = project.files()[0]

        // act
        let imports = file.imports().getOrThrow()

        // assert
        @Expect(SemanticAnalysis(empty).project().isNone())
        @Expect(imports.size, 1)
        @Expect(imports[0].target.isNone())
        @Expect(imports[0].error.isSome())
        @Expect(imports[0].names.isEmpty())
        @Expect(file.implicitImports().getOrThrow().isEmpty())
        @Expect(file.contextualPackage().getOrThrow().writtenImporters().entries.isEmpty())
    }

    @TestCase
    func everyRetainedTraversalCancelsAfterInputChanges(): Unit {
        // arrange
        let fixture = Fixture.parse("import missing.name\nfunc f() {}")
        let db = fixture.database()
        let project = SemanticAnalysis(db).project().getOrThrow()
        let module = project.modules()[0]
        let pkg = module.packages()[0]
        let file = pkg.files()[0]
        let imported = file.imports().getOrThrow()[0]
        let object = pkg.object()

        // act
        db.setFileText(fixture.files[0].fileId, Rope("func changed() {}"))

        // assert
        @AssertThrows[CancelledException](project.modules())
        @AssertThrows[CancelledException](project.packages())
        @AssertThrows[CancelledException](module.dependencies())
        @AssertThrows[CancelledException](pkg.exports())
        @AssertThrows[CancelledException](pkg.writtenImporters())
        @AssertThrows[CancelledException](pkg.permittedPackages())
        @AssertThrows[CancelledException](file.imports())
        @AssertThrows[CancelledException](file.configuration())
        @AssertThrows[CancelledException](imported.location())
        @AssertThrows[CancelledException](object.contextualPackage())
    }

    @TestCase
    func binaryAndAttachedSourceTraversalsKeepTheirOwnContexts(): Unit {
        // arrange
        let fixture = Fixture.parse("main() { print$0ln(1) }")
        let db = fixture.database(
            binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: [stdWithSources(["std.core"])]
        )
        let analysis = SemanticAnalysis(db)
        let cursor = fixture.cursor.getOrThrow()
        let target =
            analysis.at(cursor.fileId, cursor.offset).getOrThrow().definitions.getOrThrow()[0]

        // act
        let binary = target.contextualPackage().getOrThrow()
        let attachment = binary.attachedSources()[0]
        let location =
            match (target.origins()[0]) {
                case SourceOrigin(location) => location
                case _ => throw FixtureException("println requires attached source")
            }
        let file = location.contextualFile()
        let declared = file.at(location.focusRange.start).getOrThrow().definitions.getOrThrow()[0]

        // assert
        @Expect(binary.origin(), SemanticPackageOrigin.BinaryPackageOrigin)
        @Expect(attachment.origin(), SemanticPackageOrigin.AttachedPackage)
        @Expect(binary.identity != attachment.identity)
        @Expect(file.contextualPackage().getOrThrow().identity, attachment.identity)
        @Expect(attachment.files().any { one => one.identity == file.identity })
        @Expect(declared.identity, target.identity)
        @Expect(declared.contextualPackage().getOrThrow().identity, binary.identity)
        @Expect(binary.imports().isNone())
        @Expect(binary.configuration().isNone())
        @Expect(file.imports().isSome())
        @Expect(binary.writtenImporters().unavailablePackages.any { one => one.identity == binary.identity })
    }

    @TestCase
    func binaryWithoutAttachmentsHasExportsAndUnavailableImportSyntax(): Unit {
        // arrange
        let fixture = Fixture.parse("main() { print$0ln(1) }")
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let analysis = SemanticAnalysis(db)
        let cursor = fixture.cursor.getOrThrow()

        // act
        let target =
            analysis.at(cursor.fileId, cursor.offset).getOrThrow().definitions.getOrThrow()[0]
        let binary = target.contextualPackage().getOrThrow()

        // assert
        @Expect(binary.attachedSources().isEmpty())
        @Expect(binary.exports().names.any { one => one.name == "println" && one.target.identity == target.identity })
        @Expect(binary.files().all { file => file.imports().isNone() })
        @Expect(binary.imports().isNone())
        @Expect(binary.module().isNone())
    }

    @TestCase
    func scopeStageAndPrivateVisibilityArePreserved(): Unit {
        // arrange
        let (db, source, call, text) = answeredM()
        let analysis = SemanticAnalysis(db)
        let generated = analysis
            .inFile(ItemFile.Expansion(call), offsetIn(text, "Gen"))
            .getOrThrow()
        let pkg = generated.contextualFile().contextualPackage().getOrThrow()

        // act
        let written = pkg.exports(stage: ScopeStage.Written)
        let expanded = pkg.exports(stage: ScopeStage.Expanded)

        // assert
        @Expect(!written.names.any { name => name.name == "Gen" })
        @Expect(expanded.names.any { name => name.name == "Gen" && name.stage == ScopeStage.Expanded })
        @Expect(generated.definitions.getOrThrow()[0].contextualPackage().getOrThrow().identity, pkg.identity)

        // arrange
        let fixture = Fixture.parse(
            #"
            //- /a.cj module=m package=m
            package m
            import m.other.E
            private func secret() {}
            private enum Hidden { Value }
            //- /b.cj module=m package=m
            package m
            func f() {}
            //- /enum.cj module=m package=m.other
            package m.other
            public enum E { Imported }
            "#
        )
        let otherDb = fixture.database()
        let files = SemanticAnalysis(otherDb).project().getOrThrow().files()

        // act
        let own = files[0].visibleNames().getOrThrow()
        let sibling = files[1].visibleNames().getOrThrow()

        // assert
        @Expect(own.any { name => name.name == "secret" && name.visibility == Visibility.Private })
        @Expect(!sibling.any { name => name.name == "secret" })
        @Expect(sibling.any { name => name.name == "Value" })
        @Expect(sibling.any { name => name.name == "Imported" })
        @Expect(files[1].lookup("secret", Namespace.Values), Some(Resolution.NotFound))
    }

    @TestCase
    func usageScopesRejectObjectsFromAnotherSnapshot(): Unit {
        // arrange
        let fixture = Fixture.parse("func f$0() {}")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let first = SemanticAnalysis(db)
        let second = SemanticAnalysis(db)
        let target = first.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]
        let otherPackages = second.project().getOrThrow().packages()

        // act / assert
        @AssertThrows[IllegalArgumentException](target.usages(inPackages: otherPackages))
    }

    @TestCase
    func selectedBinaryInputsAndMissingEdgesAreReportedWithoutRediscovery(): Unit {
        // arrange
        let fixture = Fixture.parse("main() {}")
        let ordinary = fixture.projectModel().modules[0]
        let module = ModuleModel(ordinary.name, ordinary.root, ordinary.packages, deps: ["missing"])
        let selected = BinaryModel("std", [fixture.files[0].path], discoverPackages: false)
        let db = AnalysisDatabase()
        let paths = PathInterner()
        db.setProject(
            ProjectModel(Cfg([("os", "Linux")]), [module], binaries: [selected]),
            paths,
            binaries: [stdCjoRead("std.core", stdCjo("std.core"))]
        )
        db.setFileText(paths.intern(fixture.files[0].path), Rope(fixture.files[0].text))
        let project = SemanticAnalysis(db).project().getOrThrow()

        // act
        let dependencies = project.modules()[0].dependencies()

        // assert
        @Expect(project.binaries(), [selected])
        @Expect(!dependencies[0].isResolved)
        @Expect(dependencies[1].implicit)
        @Expect(dependencies[1].isResolved)
        @Expect(project.packages().any { pkg => pkg.name() == "std.core" })
        @Expect(project.configuration().cfg.get("os"), Some("Linux"))
        @Expect(project.configuration().selectionProvenance.isNone())
        @Expect(!project.configuration().completeCompilerInvocation)
    }

    @TestCase
    func missingSourceAndUnreadableBinaryExportsAreNotKnownEmpty(): Unit {
        // arrange
        let fixture = Fixture.parse("func f() {}")
        let db = AnalysisDatabase()
        let paths = PathInterner()
        db.setProject(fixture.projectModel(), paths, binaries: [stdCjoRead("std.core", [])])
        let project = SemanticAnalysis(db).project().getOrThrow()

        // act
        let source = project.modules()[0].packages()[0]
        let binary =
            project
                .packages()
                .filter { pkg => pkg.origin() == SemanticPackageOrigin.BinaryPackageOrigin }[0]

        // assert
        @Expect(source.files().isEmpty())
        @Expect(source.unavailableFiles().size, 1)
        @Expect(!source.exports().isAvailable)
        @Expect(source.writtenImporters().unavailablePackages.any { pkg => pkg.identity == source.identity })
        @Expect(!binary.exports().isAvailable)
        @Expect(binary.exports().names.isEmpty())
    }
}
