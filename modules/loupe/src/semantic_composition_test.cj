package loupe

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import calca.CancelledException
import rope.{Encoding, Rope}
import loupe.db.*
import loupe.fixture.*
import loupe.hir.*
import loupe.vfs.PathInterner

@Test
class SemanticCompositionTest {
    @TestCase
    func reExportedGenericCallComposesAllStreamsAndRejectsWrites(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /lib.cj module=lib package=lib cfg=os:Linux
            package lib
            public func identity<T>(value: T): T { value }
            //- /bridge.cj module=bridge package=bridge deps=lib
            package bridge
            public import lib.identity as exported
            //- /app.cj module=app package=app deps=bridge cfg=os:Linux
            package app
            import bridge.exported as alias
            func caller() { let text = "😀я"; ali$0as(true); missing() }
            @When[os == "Windows"]
            func inactive() {}
            "#
        )
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)

        // act
        let occurrence = analysis.at(at.fileId, at.offset).getOrThrow()
        let call = occurrence.resolution().call.getOrThrow()
        let target = call.callable().getOrThrow()
        let file = occurrence.contextualFile()
        let app = file.contextualPackage().getOrThrow()
        let lib = target.contextualPackage().getOrThrow()
        let bridge = file.imports().getOrThrow()[0].target.getOrThrow()
        let downstream =
            bridge
                .writtenImporters()
                .entries
                .map { imported => imported.file.contextualPackage().getOrThrow() }
        let uses = target.usages(inPackages: downstream).getOrThrow()
        let use =
            uses
                .entries
                .filter { one => one.location.focusRange == occurrence.location.focusRange }[0]
        let owner =
            match (use.owner) {
                case ObjectOwner(object) => object
                case _ => throw FixtureException("call usage must retain its owner")
            }
        let outgoing = owner.outgoingCalls()
        let expression =
            occurrence
                .objects
                .filter {
                    object =>
                    match (object.identity) {
                        case ExpressionIdentity(_, _) => true
                        case _ => false
                    }
                }[0]
        let syntax = syntaxOriginNode(expression.syntaxOrigins()[0])
        let tree = analysis.syntax(occurrence.location.file).getOrThrow()
        let pointer = syntax.pointer().getOrThrow()
        let text = occurrence.location.text().getOrThrow()
        let utf8 = text.positionOf(occurrence.location.focusRange.start, Encoding.Utf8)
        let utf16 = text.positionOf(occurrence.location.focusRange.start, Encoding.Utf16)
        let utf32 = text.positionOf(occurrence.location.focusRange.start, Encoding.Utf32)

        // assert
        @Expect(occurrence.resolution().status, SemanticResolutionStatus.ResolvedMeaning)
        @Expect(target.identity, occurrence.definitions.getOrThrow()[0].identity)
        @Expect(call.signature().getOrThrow().display(), "(Bool) -> Bool")
        @Expect(call.bindings().size, 1)
        @Expect(call.bindings()[0].valueType.display(), "Bool")
        @Expect(call.bindings()[0].parameter.contextualPackage().getOrThrow().identity, lib.identity)
        @Expect(app.name(), "app")
        @Expect(lib.name(), "lib")
        @Expect(bridge.exports().names[0].target.identity, target.identity)
        @Expect(app.module().getOrThrow().dependencies()[0].modules[0].identity, bridge.module().getOrThrow().identity)
        @Expect(file.configuration().getOrThrow().cfg.get("os"), Some("Linux"))
        @Expect(!file.configuration().getOrThrow().hasCompleteCompilerInvocation)
        @Expect(file.conditions().getOrThrow()[0].evaluation, Some(false))
        @Expect(!app.exports().names.any { name => name.name == "inactive" })
        @Expect(uses.gaps.contains("macro-origin-usages"))
        @Expect(use.target.identity, target.identity)
        @Expect(use.location.contextualFile().identity, file.identity)
        @Expect(use.location.excerpt(), Some("alias"))
        @Expect(owner.identity, occurrence.owner.getOrThrow().identity)
        @Expect(outgoing.edges.size, 1)
        @Expect(outgoing.edges[0].callee.identity, target.identity)
        @Expect(outgoing.edges[0].site.contextualFile().identity, file.identity)
        @Expect(outgoing.gaps.any { gap => gap.reason == "unresolved-call" })
        @Expect(target.incomingCalls().any { edge => edge.caller.identity == owner.identity })
        @Expect(syntax.location().file, occurrence.location.file)
        @Expect(syntax.location().excerpt(), Some("alias"))
        @Expect(syntax.mappings().any { mapping => mapping.object.identity == expression.identity })
        @Expect(tree.resolve(pointer).getOrThrow().text(), syntax.text())
        @Expect(utf8.column > utf16.column)
        @Expect(utf16.column, utf32.column + 1)

        // act
        db.setFileText(
            at.fileId,
            Rope(fixture.files[2].text.replace("alias(true)", "alias(false)"))
        )
        let fresh = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()

        // assert
        @Expect(fresh.resolution().call.getOrThrow().signature().getOrThrow().display(), "(Bool) -> Bool")
        @AssertThrows[CancelledException](occurrence.resolution())
        @AssertThrows[CancelledException](call.bindings())
        @AssertThrows[CancelledException](target.usages())
        @AssertThrows[CancelledException](owner.outgoingCalls())
        @AssertThrows[CancelledException](use.location.excerpt())
        @AssertThrows[CancelledException](syntax.mappings())
        @AssertThrows[CancelledException](tree.resolve(pointer))
        @AssertThrows[CancelledException](file.imports())
        @AssertThrows[CancelledException](app.exports())
        @AssertThrows[CancelledException](bridge.writtenImporters())
        @AssertThrows[CancelledException](lib.configuration())
    }

    @TestCase
    func samePhysicalFileKeepsContextAcrossResolutionSyntaxAndReverseEdges(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /lib.cj module=m package=m
            package m
            public func identity<T>(value: T): T { value }
            public func caller() { identity(true) }
            "#
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
        let analysis = SemanticAnalysis(db)
        let modules = analysis.project().getOrThrow().modules()
        let files = modules.map { module => module.packages()[0].files()[0] }
        let offset = written.text.indexOf("identity(true)").getOrThrow()

        // act
        let occurrences = files.map { file => file.at(offset).getOrThrow() }
        let targets =
            occurrences.map { one => one.resolution().call.getOrThrow().callable().getOrThrow() }
        let syntax = targets.map { target => syntaxOriginNode(target.syntaxOrigins()[0]) }
        let incoming = targets.map { target => target.incomingCalls() }

        // assert
        @Expect(files[0].identity != files[1].identity)
        @Expect(targets[0].identity != targets[1].identity)
        @Expect(syntax[0].location().focusRange, syntax[1].location().focusRange)
        @Expect(syntax[0].location().file != syntax[1].location().file)
        for (i in 0..2) {
            @Expect(occurrences[i].contextualFile().identity, files[i].identity)
            @Expect(targets[i].contextualPackage().getOrThrow().module().getOrThrow().identity, modules[i].identity)
            @Expect(occurrences[i].resolution().call.getOrThrow().signature().getOrThrow().display(), "(Bool) -> Bool")
            @Expect(syntax[i].mappings().any { mapping => mapping.object.identity == targets[i].identity })
            @Expect(incoming[i].size, 1)
            @Expect(incoming[i][0].site.contextualFile().identity, files[i].identity)
            @Expect(incoming[i][0].caller.outgoingCalls().edges[0].callee.identity, targets[i].identity)
            @Expect(targets[i].usages().getOrThrow().entries.all { use => use.location.contextualFile().identity == files[i].identity })
        }
        let scriptTree = analysis.syntax(syntax[1].location().file).getOrThrow()
        @AssertThrows[IllegalArgumentException](scriptTree.resolve(syntax[0].pointer().getOrThrow()))

        // act
        db.setFileText(fileId, Rope(written.text.replace("true", "false")))

        // assert
        @AssertThrows[CancelledException](targets[0].incomingCalls())
        @AssertThrows[CancelledException](targets[1].incomingCalls())
        @AssertThrows[CancelledException](syntax[0].mappings())
        @AssertThrows[CancelledException](syntax[1].mappings())
        let fresh = SemanticAnalysis(db).project().getOrThrow().modules()
        @Expect(fresh.all { module => module.packages()[0].files()[0].at(offset).getOrThrow().resolution().call.getOrThrow().signature().getOrThrow().display() == "(Bool) -> Bool" })
    }

    @TestCase[attached in [false, true]]
    func binaryCallsKeepIdentityAndExplicitSourceAvailability(attached: Bool): Unit {
        // arrange
        let fixture = Fixture.parse("main() { print$0ln(1) }")
        let models: Array<BinaryModel> =
            if (attached) { [stdWithSources(["std.core"])] } else { [] }
        let db = fixture.database(
            binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: models
        )
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)

        // act
        let occurrence = analysis.at(at.fileId, at.offset).getOrThrow()
        let target = occurrence.resolution().call.getOrThrow().callable().getOrThrow()
        let pkg = target.contextualPackage().getOrThrow()
        let incoming = target.incomingCalls()
        let origins = target.syntaxOrigins()

        // assert
        @Expect(occurrence.resolution().status, SemanticResolutionStatus.ResolvedMeaning)
        @Expect(target.identity, occurrence.definitions.getOrThrow()[0].identity)
        @Expect(pkg.origin(), SemanticPackageOrigin.BinaryPackageOrigin)
        @Expect(pkg.exports().names.any { name => name.target.identity == target.identity })
        @Expect(pkg.imports().isNone())
        @Expect(pkg.configuration().isNone())
        @Expect(incoming.size, 1)
        @Expect(incoming[0].caller.identity, occurrence.owner.getOrThrow().identity)
        @Expect(incoming[0].callee.identity, target.identity)
        if (attached) {
            // act
            let syntax = syntaxOriginNode(origins[0])
            let location =
                match (target.origins()[0]) {
                    case SourceOrigin(source) => source
                    case _ =>
                        throw FixtureException("attached declaration requires source evidence")
                }
            let file = location.contextualFile()
            let declared =
                file.at(location.focusRange.start).getOrThrow().definitions.getOrThrow()[0]

            // assert
            @Expect(syntax.location().kind(), SemanticSourceKind.AttachedSource)
            @Expect(syntax.mappings().any { mapping => mapping.object.identity == target.identity })
            @Expect(declared.identity, target.identity)
            @Expect(file.contextualPackage().getOrThrow().identity != pkg.identity)
            @Expect(declared.contextualPackage().getOrThrow().identity, pkg.identity)
            @Expect(file.imports().isSome())
        } else {
            // act
            let body = target.bodyResolutions()
            let outgoing = target.outgoingCalls()

            // assert
            @Expect(match (origins[0]) { case UnavailableSyntax => true; case _ => false })
            @Expect(body.status, SemanticResolutionStatus.UnavailableMeaning)
            @Expect(body.calls.isEmpty())
            @Expect(outgoing.edges.isEmpty())
            @Expect(outgoing.gaps.any { gap => gap.reason == "unavailable-body" })
            @Expect(pkg.attachedSources().isEmpty())
        }
    }
}
