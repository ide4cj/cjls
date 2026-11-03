package loupe

import std.collection.*
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import calca.CancelledException
import ginkgo.TextRange
import rope.{Encoding, LineColumn, Rope}
import loupe.db.{MappedSpan, SpanOrigin}
import loupe.fixture.*
import loupe.hir.*

/**
 * Exact source excerpts for objects with available syntax origins.
 */
func semanticOriginText(object: SemanticObject, full!: Bool = false): Array<String> {
    object.origins() |>
        filterMap {
            origin: SemanticOrigin =>
            match (origin) {
                case SourceOrigin(location) => location.excerpt(full: full)
                case _ => None<String>
            }
        } |>
        collectArray
}

@Test
class SemanticAnalysisTest {
    @TestCase
    func localIdentityKeepsItsOwnerAndExactDeclaration(): Unit {
        // arrange
        let fixture = Fixture.parse("func f() { let x = 1; { let x = 2; x$0 } }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)

        // act
        let result = analysis.at(at.fileId, at.offset).getOrThrow()
        let target = result.definitions.getOrThrow()[0]

        // assert
        @Expect(result.location.excerpt(), Some("x"))
        @Expect(semanticOriginText(target), ["x"])
        @Expect(semanticOriginText(target, full: true), ["x"])
        let declaredAt =
            match (target.origins()[0]) {
                case SourceOrigin(location) => location.focusRange.start
                case _ => throw FixtureException("local has no origin")
            }
        @Expect(declaredAt, fixture.files[0].text.indexOf("x = 2").getOrThrow())

        // act
        let declaration = analysis.at(at.fileId, declaredAt).getOrThrow()

        // assert
        @Expect(declaration.definitions.getOrThrow()[0].identity, target.identity)
        @Expect(declaration.objects.any { object => object.identity == target.identity })
        @Expect(target.typeDisplay(), Some("Int64"))
        @Expect(match ((target.identity, result.owner.getOrThrow().identity)) {
            case (LocalIdentity(owner, _), NamedIdentity(DeclDef(decl))) => owner == decl
            case _ => false
        })
        @Expect(result.objects.any { object => match (object.identity) {
            case ExpressionIdentity(_, _) => object.typeDisplay() == Some("Int64")
            case _ => false
        } })
    }

    @TestCase
    func declarationIdentityDoesNotRoundTripThroughCoordinates(): Unit {
        // arrange
        let fixture = Fixture.parse("func tar$0get(): Int64 { 1 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()

        // act
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()

        // assert
        @Expect(result.definitions.getOrThrow()[0].identity, result.owner.getOrThrow().identity)
        @Expect(semanticOriginText(result.definitions.getOrThrow()[0]), ["target"])
    }

    @TestCase
    func primitiveWrittenTypeIsAnObjectWithoutANominalDefinition(): Unit {
        // arrange
        let fixture = Fixture.parse("func f(x: Int$064): Unit {}")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()

        // act
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()
        let types =
            result
                .objects
                .filter {
                    object =>
                    match (object.identity) {
                        case SignatureTypeIdentity(_, _) => true
                        case _ => false
                    }
                }

        // assert
        @Assert(types.size, 1)
        @Expect(semanticOriginText(types[0]), ["Int64"])
        @Expect(types[0].typeDisplay(), Some("Int64"))
    }

    @TestCase
    func bodyTypeAndExpressionRetainSeparateIdentities(): Unit {
        // arrange
        let fixture = Fixture.parse("func f() { let x: Int$064 = 1 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()

        // act
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()

        // assert
        @Expect(result.objects.any { object => match (object.identity) {
            case BodyTypeIdentity(_, _) => semanticOriginText(object) == ["Int64"] && object.typeDisplay() == Some("Int64")
            case _ => false
        } })
    }

    @TestCase
    func literalSelectionFindsTheNearestExpression(): Unit {
        // arrange
        let fixture = Fixture.parse("func f() { 1 + 2$0 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()

        // act
        let result = SemanticAnalysis(db).at(at.fileId, at.offset - 1).getOrThrow()
        let expressions =
            result
                .objects
                .filter {
                    object =>
                    match (object.identity) {
                        case ExpressionIdentity(_, _) => true
                        case _ => false
                    }
                }

        // assert
        @Assert(expressions.size, 1)
        @Expect(semanticOriginText(expressions[0]), ["2"])
        @Expect(expressions[0].typeDisplay(), Some("Int64"))
    }

    @TestCase
    func overloadsAndKnownEmptyMeaningsArePreserved(): Unit {
        // arrange
        let fixture = Fixture.parse("func f(x: Int64) {}\nfunc f(x: Bool) {}\nfunc g() { f$0 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)

        // act
        let overloads = analysis.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()

        // assert
        @Expect(overloads.size, 2)

        // arrange
        let missing = Fixture.parse("func g() { absent$0 }")
        let missingDb = missing.database()
        let cursor = missing.cursor.getOrThrow()

        // act
        let unresolved = SemanticAnalysis(missingDb).at(cursor.fileId, cursor.offset).getOrThrow()
        let beforeStart = analysis.at(at.fileId, -1)
        let afterEnd = analysis.at(at.fileId, 10000)

        // assert
        @Expect(unresolved.definitions.getOrThrow().size, 0)
        @Expect(beforeStart.isNone())
        @Expect(afterEnd.isNone())
    }

    @TestCase
    func unicodeEvidenceAndNegotiatedCoordinatesUseTheSameText(): Unit {
        // arrange
        let fixture = Fixture.parse("func f() { let x = \"😀я\"; x$0 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        const PREFIX = "func f() { let x = \"😀я\"; "

        // act
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()
        let snapshotText = result.location.text().getOrThrow()

        // assert
        @Expect(result.location.excerpt(), Some("x"))
        @Expect(result.location.position(), Some(LineColumn(0, PREFIX.size)))
        @Expect(snapshotText.positionOf(result.location.focusRange.start, Encoding.Utf16), LineColumn(0, PREFIX.toRuneArray().size + 1))
        @Expect(snapshotText.positionOf(result.location.focusRange.start, Encoding.Utf32), LineColumn(0, PREFIX.toRuneArray().size))
    }

    @TestCase
    func editingInvalidatesObjectsAndEvidenceInsteadOfReadingNewText(): Unit {
        // arrange
        let fixture = Fixture.parse("func f() { let x = 1; x$0 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let result = analysis.at(at.fileId, at.offset).getOrThrow()
        let target = result.definitions.getOrThrow()[0]
        let copied = result.location.excerpt()
        let snapshotText = result.location.text().getOrThrow()

        // act
        db.setFileText(at.fileId, Rope("func f() {}"))

        // assert
        @Expect(copied, Some("x"))
        @Expect(snapshotText.toString(), fixture.files[0].text)
        @AssertThrows[CancelledException](result.location.text())
        @AssertThrows[CancelledException](result.location.excerpt())
        @AssertThrows[CancelledException](target.origins())
        @AssertThrows[CancelledException](target.typeDisplay())
        @AssertThrows[CancelledException](analysis.at(at.fileId, at.offset))
    }

    @TestCase
    func binaryIdentitySurvivesMissingNavigationSource(): Unit {
        // arrange
        let fixture = Fixture.parse("main() { print$0ln(1) }")
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let at = fixture.cursor.getOrThrow()

        // act
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()
        let targets = result.definitions.getOrThrow()

        // assert
        @Assert(targets.size, 1)
        @Expect(match (targets[0].identity) {
            case NamedIdentity(DeclDef(id)) => match (id.file(db)) {
                case Binary(_, _) => true
                case _ => false
            }
            case _ => false
        })
        @Expect(match (targets[0].origins()[0]) {
            case UnavailableOrigin => true
            case _ => false
        })
    }

    @TestCase
    func expansionLocationsKeepGeneratedAndCopiedOrigins(): Unit {
        // arrange
        let (db, _, call, text) = answeredM()
        let analysis = SemanticAnalysis(db)

        // act
        let generated = analysis
            .inFile(ItemFile.Expansion(call), offsetIn(text, "Gen"))
            .getOrThrow()
        let target = generated.definitions.getOrThrow()[0]

        // assert
        @Expect(semanticOriginText(target), ["Gen"])
        let location =
            match (target.origins()[0]) {
                case SourceOrigin(location) => location
                case _ => throw FixtureException("generated declaration has no expansion origin")
            }
        @Expect(location.kind(), SemanticSourceKind.ExpansionSource)
        @Expect(location.source().isNone())

        // act
        let copied = analysis.inFile(ItemFile.Expansion(call), offsetIn(text, "C")).getOrThrow()

        // assert
        @Expect(copied.location.excerpt(), Some("C"))
        @Expect(copied.location.source().getOrThrow().excerpt(), Some("C"))

        // act
        let generic = analysis
            .inFile(ItemFile.Expansion(call), offsetIn(text, "<T>", plus: 1))
            .getOrThrow()

        // assert
        @Expect(semanticOriginText(generic.definitions.getOrThrow()[0]), ["T"])
    }

    @TestCase
    func syntheticAndUnavailableBodyOriginsStayDistinct(): Unit {
        // arrange
        let fixture = Fixture.parse("class C { let x = 1 }\nfunc f(c: ?C) { c$0?.x }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let result = analysis.at(at.fileId, at.offset).getOrThrow()
        let owner =
            match (result.owner.getOrThrow().identity) {
                case NamedIdentity(DeclDef(owner)) => owner
                case _ => throw FixtureException("no body owner")
            }
        let map = bodyWithSourceMap(db, owner).sourceMap
        let synthetic =
            (0..map.exprs.size).iterator() |>
                filter { i: Int64 => map.exprs[i] == BodyOrigin.SyntheticSource } |>
                first
        let syntheticId =
            synthetic ?? throw FixtureException("optional chain must have a synthetic expression")

        // act
        let syntheticOrigins = analysis
            .object(ExpressionIdentity(owner, ExprId(syntheticId)))
            .origins()
        let unavailableOrigins = analysis
            .object(ExpressionIdentity(owner, ExprId(map.exprs.size)))
            .origins()

        // assert
        @Expect(match (syntheticOrigins[0]) {
            case SyntheticOrigin => true
            case _ => false
        })
        @Expect(match (unavailableOrigins[0]) {
            case UnavailableOrigin => true
            case _ => false
        })
    }

    @TestCase
    func inactiveAndIncompleteCodeRemainInspectableWithoutInventedMeanings(): Unit {
        // arrange
        let fixture = Fixture.parse("//- /main.cj inactive=windows\nfunc f() { abs$0ent }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()

        // act
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()

        // assert
        @Expect(result.location.excerpt(), Some("absent"))
        @Expect(result.definitions.isNone())

        // arrange
        let incomplete = Fixture.parse("func f() { let $0")
        let incompleteDb = incomplete.database()
        let cursor = incomplete.cursor.getOrThrow()

        // act
        let incompleteResult = SemanticAnalysis(incompleteDb).at(cursor.fileId, cursor.offset)

        // assert
        @Expect(incompleteResult.isSome())
    }

    @TestCase
    func requestCancellationReachesThePinnedAnalysis(): Unit {
        // arrange
        let fixture = Fixture.parse("func f() { 1$0 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let stop = AtomicBool(false)
        let analysis = SemanticAnalysis(db.snapshot(cancelledBy: { => stop.load() }))

        let result = analysis.at(at.fileId, at.offset).getOrThrow()

        // act
        stop.store(true)

        // assert
        @AssertThrows[CancelledException](result.location.excerpt())
        @AssertThrows[CancelledException](analysis.at(at.fileId, at.offset))
    }

    @TestCase
    func aPatternBindingExposesBothPatternAndLocalIdentities(): Unit {
        // arrange
        let fixture = Fixture.parse("func f() { let (a$0, b) = (1, 2); a }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()

        // act
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()

        // assert
        @Expect(result.objects.any { object => match (object.identity) {
            case PatternIdentity(_, _) => semanticOriginText(object) == ["a"]
            case _ => false
        } })
        @Expect(result.objects.any { object => match (object.identity) {
            case LocalIdentity(_, _) => semanticOriginText(object) == ["a"] && object.typeDisplay() == Some("Int64")
            case _ => false
        } })
    }

    @TestCase
    func genericParameterDeclarationAndUseHaveTheSameIdentity(): Unit {
        // arrange
        let fixture = Fixture.parse("func f<T>(x: T$0): T { x }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)

        // act
        let use = analysis.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]
        let declaration = analysis
            .at(at.fileId, fixture.files[0].text.indexOf("T>").getOrThrow())
            .getOrThrow()

        // assert
        @Expect(use.identity, declaration.definitions.getOrThrow()[0].identity)
        @Expect(semanticOriginText(use), ["T"])
    }

    @TestCase
    func checkedBinaryAttachmentIsLabeledAndReadFromTheSnapshot(): Unit {
        // arrange
        let fixture = Fixture.parse("main() { print$0ln(1) }")
        let db = fixture.database(
            binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: [stdWithSources(["std.core"])]
        )
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)

        // act
        let target = analysis.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]
        let location =
            match (target.origins()[0]) {
                case SourceOrigin(location) => location
                case _ => throw FixtureException("checked binary has no source")
            }

        // assert
        @Expect(location.kind(), SemanticSourceKind.AttachedSource)
        @Expect(location.excerpt(), Some("println"))

        // act
        let declaration = analysis.inFile(location.file, location.focusRange.start).getOrThrow()

        // assert
        @Expect(declaration.definitions.getOrThrow()[0].identity, target.identity)
    }

    @TestCase
    func namedTypeIdentityIsDistinctFromConstructorNavigation(): Unit {
        // arrange
        let fixture = Fixture.parse("class C { init(x: Int64) {} }\nmain() { C$0(1) }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()

        // act
        let target =
            SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]

        // assert
        @Expect(match (target.identity) {
            case NamedIdentity(DeclDef(id)) => id.item(db).kind == ItemKind.Class
            case _ => false
        })
        @Expect(semanticOriginText(target), ["C"])

        // act
        let navigation = definitionAt(db, at.fileId, at.offset)

        // assert
        @Assert(navigation.size, 1)
        let text = db.sourceFile(at.fileId).getOrThrow().text(db)
        @Expect(text.slice(navigation[0].focusRange.start..navigation[0].focusRange.end).toString(), "init")
    }

    @TestCase
    func explicitInitializerKeepsItsOwnDefinitionIdentity(): Unit {
        // arrange
        let fixture = Fixture.parse("class C { ini$0t(x: Int64) {} }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()

        // act
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()
        let definitions =
            result.definitions ?? throw FixtureException("initializer has no definition")

        // assert
        @Assert(definitions.size, 1)
        @Expect(definitions[0].identity, result.owner.getOrThrow().identity)
        @Expect(match (definitions[0].identity) {
            case NamedIdentity(DeclDef(id)) => id.item(db).kind == ItemKind.Init
            case _ => false
        })
        @Expect(semanticOriginText(definitions[0]), ["init"])
    }

    @TestCase
    func localGenericInExpansionHasTheSameIdentityAtDeclarationAndUse(): Unit {
        // arrange
        let (db, file) = expansionDatabase("package m\nimport m.ms.*\nfunc f() { @A(1) }")
        const OUTPUT = "func g<T>(x: T): T { x }; g(1)"
        let call = answer(
            db,
            file,
            "A",
            OUTPUT,
            [MappedSpan(TextRange(0, OUTPUT.size), SpanOrigin.FromCall)]
        )
        let analysis = SemanticAnalysis(db)

        // act
        let declared = analysis
            .inFile(ItemFile.Expansion(call), offsetIn(OUTPUT, "<T>", plus: 1))
            .getOrThrow()
        let used = analysis
            .inFile(ItemFile.Expansion(call), offsetIn(OUTPUT, ": T", plus: 2))
            .getOrThrow()
        let definitions =
            declared.definitions ?? throw FixtureException("expanded generic has no definition")

        // assert
        @Assert(definitions.size, 1)
        @Expect(definitions[0].identity, used.definitions.getOrThrow()[0].identity)
        @Expect(semanticOriginText(definitions[0]), ["T"])
        @Expect(match (definitions[0].origins()[0]) {
            case SourceOrigin(location) => location.file == ItemFile.Expansion(call) && location.source().isNone()
            case _ => false
        })
    }
}
