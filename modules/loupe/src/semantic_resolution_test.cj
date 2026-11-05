package loupe

import std.unittest.*
import std.unittest.testmacro.*
import calca.CancelledException
import ginkgo.TextRange
import rope.Rope
import loupe.db.{MappedSpan, SpanOrigin}
import loupe.fixture.*
import loupe.hir.*

@Test
class SemanticResolutionTest {
    @TestCase
    func selectedOverloadMatchesNavigationAndEnumeratedCalls(): Unit {
        // arrange
        let fixture = Fixture.parse("func f(x: Int64) {}\nfunc f(x: Bool) {}\nfunc g() { f$0(1) }")
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)

        // act
        let occurrence = analysis.at(cursor.fileId, cursor.offset).getOrThrow()
        let result = occurrence.resolution()
        let call = result.call.getOrThrow()
        let calls = occurrence.owner.getOrThrow().calls()
        let resolutions = occurrence.owner.getOrThrow().resolutions()

        // assert
        @Expect(result.status, SemanticResolutionStatus.ResolvedMeaning)
        @Expect(call.callable().getOrThrow().identity, occurrence.definitions.getOrThrow()[0].identity)
        @Expect(call.argumentParameters(), Some([0]))
        @Assert(calls.size, 1)
        @Expect(calls[0].callable().getOrThrow().identity, call.callable().getOrThrow().identity)
        @Expect(resolutions.any { resolution => resolution.occurrence.location.focusRange == occurrence.location.focusRange })
    }

    @TestCase
    func initializerRetainsNamedTypeSeparately(): Unit {
        // arrange
        let fixture = Fixture.parse("class C { init(x: Int64) {} }\nmain() { C$0(1) }")
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let occurrence = SemanticAnalysis(db).at(cursor.fileId, cursor.offset).getOrThrow()
        let call = occurrence.resolution().call.getOrThrow()
        let initializer = call.initializer().getOrThrow()

        // assert
        @Expect(call.status, SemanticResolutionStatus.ResolvedMeaning)
        @Expect(initializer.identity != occurrence.definitions.getOrThrow()[0].identity)
        @Expect(semanticOriginText(initializer), ["init"])
        @Expect(semanticOriginText(occurrence.definitions.getOrThrow()[0]), ["C"])
    }

    @TestCase
    func inferredBindingsKeepTheirBinderAndFinalType(): Unit {
        // arrange
        let fixture = Fixture.parse("func identity<T>(x: T): T { x }\nmain() { ident$0ity(1) }")
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let result = SemanticAnalysis(db).at(cursor.fileId, cursor.offset).getOrThrow().resolution()
        let call = result.call.getOrThrow()
        let bindings = call.bindings()

        // assert
        @Expect(result.status, SemanticResolutionStatus.ResolvedMeaning)
        @Assert(bindings.size, 1)
        @Expect(semanticOriginText(bindings[0].parameter), ["T"])
        @Expect(bindings[0].valueType.display(), "Int64")
        @Expect(call.signature().getOrThrow().display(), "(Int64) -> Int64")
    }

    @TestCase
    func functionValuesAndLocalFunctionsAreSuccessfulWithoutDeclarationIds(): Unit {
        // arrange
        let fixture = Fixture.parse(
            "func f() { func local(x: Int64): Int64 { x }; let value = { x: Int64 => x }; loc$0al(1); value(2) }"
        )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let occurrence = SemanticAnalysis(db).at(cursor.fileId, cursor.offset).getOrThrow()
        let call = occurrence.resolution().call.getOrThrow()
        let calls = occurrence.owner.getOrThrow().calls()

        // assert
        @Expect(call.status, SemanticResolutionStatus.ResolvedMeaning)
        @Expect(match (call.callable().getOrThrow().identity) {
            case LocalIdentity(_, _) => true
            case _ => false
        })
        @Expect(calls.any { item => item.status == SemanticResolutionStatus.ResolvedMeaning && item.callable().isNone() })
    }

    @TestCase
    func missingNamesAndUnavailableClassificationRemainDistinct(): Unit {
        // arrange
        let missing = Fixture.parse("func f() { absent$0 }")
        let db = missing.database()
        let cursor = missing.cursor.getOrThrow()

        // act
        let result = SemanticAnalysis(db).at(cursor.fileId, cursor.offset).getOrThrow().resolution()

        // assert
        @Expect(result.status, SemanticResolutionStatus.UnresolvedMeaning)
        @Expect(match (result.reason.getOrThrow()) {
            case MissingResolutionReason => true
            case _ => false
        })

        // arrange
        let inactive = Fixture.parse("//- /main.cj inactive=windows\nfunc f() { absent$0 }")
        let inactiveDb = inactive.database()
        let at = inactive.cursor.getOrThrow()

        // act
        let unavailable = SemanticAnalysis(inactiveDb)
            .at(at.fileId, at.offset)
            .getOrThrow()
            .resolution()

        // assert
        @Expect(unavailable.status, SemanticResolutionStatus.UnavailableMeaning)
    }

    @TestCase
    func callEvidenceRejectsReadsAfterAnEdit(): Unit {
        // arrange
        let fixture = Fixture.parse("func f(x: Int64) {}\nmain() { f$0(1) }")
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let occurrence = SemanticAnalysis(db).at(cursor.fileId, cursor.offset).getOrThrow()
        let call = occurrence.resolution().call.getOrThrow()

        // act
        db.setFileText(cursor.fileId, Rope("main() {}"))

        // assert
        @AssertThrows[CancelledException](call.bindings())
        @AssertThrows[CancelledException](call.callable())
        @AssertThrows[CancelledException](occurrence.resolution())
    }
    @TestCase
    func signatureSegmentsRetainTheResolvedGenericBinder(): Unit {
        // arrange
        let fixture = Fixture.parse("func f<T>(x: T$0): T { x }")
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let occurrence = SemanticAnalysis(db).at(cursor.fileId, cursor.offset).getOrThrow()
        let result = occurrence.resolution()

        // assert
        @Expect(result.status, SemanticResolutionStatus.ResolvedMeaning)
        @Expect(match (result.path.getOrThrow()) {
            case Resolved(GenericOf(_, 0)) => true
            case _ => false
        })
        @Expect(semanticOriginText(occurrence.definitions.getOrThrow()[0]), ["T"])
    }

    @TestCase
    func importFailurePreservesItsStructuredReason(): Unit {
        // arrange
        let fixture = Fixture.parse("package m\nimport absent.pk$0g\nfunc f() {}")
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let result = SemanticAnalysis(db).at(cursor.fileId, cursor.offset).getOrThrow().resolution()

        // assert
        @Expect(result.status, SemanticResolutionStatus.UnresolvedMeaning)
        @Expect(match (result.reason.getOrThrow()) {
            case ImportResolutionFailure(NoPackage(_)) => true
            case _ => false
        })
    }

    @TestCase
    func ambiguousCallsAndArgumentDiagnosticsRemainInspectable(): Unit {
        // arrange
        let ambiguous = Fixture.parse(
            "func f(x: Int8): Int8 { x }\nfunc f(x: Int16): Int16 { x }\nmain() { f$0(1) }"
        )
        let db = ambiguous.database()
        let cursor = ambiguous.cursor.getOrThrow()

        // act
        let result = SemanticAnalysis(db).at(cursor.fileId, cursor.offset).getOrThrow().resolution()

        // assert
        @Expect(result.status, SemanticResolutionStatus.AmbiguousMeaning)

        // arrange
        let invalid = Fixture.parse("func f(x: Int64) {}\nmain() { f$0() }")
        let invalidDb = invalid.database()
        let at = invalid.cursor.getOrThrow()

        // act
        let failure = SemanticAnalysis(invalidDb).at(at.fileId, at.offset).getOrThrow().resolution()

        // assert
        @Expect(failure.status, SemanticResolutionStatus.UnresolvedMeaning)
        @Expect(failure.diagnostics.any { link => match (link.diagnostic) {
            case ArgCount(_, _, _) => true
            case _ => false
        } })
    }

    @TestCase
    func bodyEnumerationRetainsExpansionContext(): Unit {
        // arrange
        let (db, file) = expansionDatabase("package m\nimport m.ms.*\nfunc f() { @A(1) }")
        const OUTPUT = "let v = 1; v"
        let call = answer(
            db,
            file,
            "A",
            OUTPUT,
            [MappedSpan(TextRange(0, OUTPUT.size), SpanOrigin.FromCall)]
        )
        let analysis = SemanticAnalysis(db)

        // act
        let occurrence = analysis
            .inFile(ItemFile.Expansion(call), offsetIn(OUTPUT, "; v", plus: 2))
            .getOrThrow()
        let results = occurrence.owner.getOrThrow().resolutions()

        // assert
        @Expect(occurrence.resolution().status, SemanticResolutionStatus.ResolvedMeaning)
        @Expect(results.any { result => result.occurrence.location.file == ItemFile.Expansion(call) && result.occurrence.location.excerpt() == Some("v") })
    }

    @TestCase
    func namedDefaultVariadicAndTrailingArgumentsRetainTheirParameters(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            func configured(a: Int64, skip!: Int64 = 0, body!: (Int64) -> Int64): Int64 { body(a) }
            func packed(a: Int64, rest: Array<Int64>): Int64 { a }
            func f() {
                config$0ured(1) { x => x }
                configured(1, skip: 2) { x => x }
                packed(1, 2, 3)
            }
            "#
        )
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let cursor = fixture.cursor.getOrThrow()

        // act
        let occurrence = SemanticAnalysis(db).at(cursor.fileId, cursor.offset).getOrThrow()
        let calls = occurrence.owner.getOrThrow().calls()
        let mappings = calls.map { call => call.argumentParameters().getOrThrow() }

        // assert
        @Assert(calls.size, 3)
        @Expect(calls.all { call => call.status == SemanticResolutionStatus.ResolvedMeaning })
        @Expect(mappings.contains([0, 2]))
        @Expect(mappings.contains([0, 1, 2]))
        @Expect(mappings.contains([0, 1, 1]))
    }

    @TestCase
    func compoundIndexAssignmentRetainsOperatorAndSetterSeparately(): Unit {
        // arrange
        let fixture = Fixture.parse(
            #"
            struct V {
                operator func +(other: V): V { this }
            }
            class Box {
                operator func [](i: Int64): V { V() }
                operator func [](i: Int64, value!: V): Unit {}
            }
            func f(b: Box, v: V) { b[0] +$0= v }
            "#
        )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let occurrence = SemanticAnalysis(db).at(cursor.fileId, cursor.offset).getOrThrow()
        let result = occurrence.resolution()
        let operation = result.call.getOrThrow()
        let setter = result.setterCall.getOrThrow()
        let calls = occurrence.owner.getOrThrow().calls()

        // assert
        @Expect(operation.status, SemanticResolutionStatus.ResolvedMeaning)
        @Expect(setter.status, SemanticResolutionStatus.ResolvedMeaning)
        @Expect(operation.isSetter, false)
        @Expect(setter.isSetter)
        @Expect(operation.callable().getOrThrow().identity != setter.callable().getOrThrow().identity)
        @Expect(operation.argumentParameters(), Some([0]))
        @Expect(setter.argumentParameters(), Some([0, 1]))
        @Expect(calls.any { call => call.isSetter })
    }

    @TestCase
    func binaryBodiesWithoutAttachmentsAreExplicitlyUnavailable(): Unit {
        // arrange
        let fixture = Fixture.parse("main() { print$0ln(1) }")
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let cursor = fixture.cursor.getOrThrow()
        let target =
            SemanticAnalysis(db)
                .at(cursor.fileId, cursor.offset)
                .getOrThrow()
                .definitions
                .getOrThrow()[0]

        // act
        let result = target.bodyResolutions()

        // assert
        @Expect(result.owner.identity, target.identity)
        @Expect(result.status, SemanticResolutionStatus.UnavailableMeaning)
        @Expect(match (result.reason.getOrThrow()) {
            case UnavailableBodySource => true
            case _ => false
        })
        @Expect(result.occurrences.isEmpty())
        @Expect(result.calls.isEmpty())
    }

    @TestCase
    func emptySourceBodiesAndAbsentBlocksRemainDistinct(): Unit {
        // arrange
        let fixture = Fixture.parse("func empty() {}\nfunc signatureOnly()")
        let db = fixture.database()
        let file = fixture.files[0]
        let analysis = SemanticAnalysis(db)
        let empty =
            analysis
                .at(file.fileId, file.text.indexOf("empty").getOrThrow())
                .getOrThrow()
                .definitions
                .getOrThrow()[0]
        let signatureOnly =
            analysis
                .at(file.fileId, file.text.indexOf("signatureOnly").getOrThrow())
                .getOrThrow()
                .definitions
                .getOrThrow()[0]

        // act
        let known = empty.bodyResolutions()
        let missing = signatureOnly.bodyResolutions()

        // assert
        @Expect(known.status, SemanticResolutionStatus.ResolvedMeaning)
        @Expect(known.calls.isEmpty())
        @Expect(missing.status, SemanticResolutionStatus.UnavailableMeaning)
    }
    @TestCase
    func missingStandardInputsPreserveTheirStructuredReason(): Unit {
        // arrange
        let fixture = Fixture.parse("func f() { \"a$0\" }")
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let result = SemanticAnalysis(db).at(cursor.fileId, cursor.offset).getOrThrow().resolution()

        // assert
        @Expect(result.status, SemanticResolutionStatus.UnavailableMeaning)
        @Expect(match (result.reason.getOrThrow()) {
            case MissingResolutionInput(NoStd) => true
            case _ => false
        })
    }
}
