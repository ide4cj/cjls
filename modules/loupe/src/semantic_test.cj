package loupe

import std.collection.*
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import calca.CancelledException
import rope.{Encoding, LineColumn, Rope}
import loupe.fixture.*
import loupe.hir.*

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
    func localIdentityKeepsItsOwnerAndExactDeclaration() {
        let fixture = Fixture.parse("func f() { let x = 1; { let x = 2; x$0 } }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let result = analysis.at(at.fileId, at.offset).getOrThrow()
        let target = result.definitions.getOrThrow()[0]
        @Expect(result.location.excerpt(), Some("x"))
        @Expect(semanticOriginText(target), ["x"])
        @Expect(semanticOriginText(target, full: true), ["x"])
        let declaredAt =
            match (target.origins()[0]) {
                case SourceOrigin(location) => location.focusRange.start
                case _ => throw FixtureException("local has no origin")
            }
        @Expect(declaredAt, fixture.files[0].text.indexOf("x = 2").getOrThrow())
        let declaration = analysis.at(at.fileId, declaredAt).getOrThrow()
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
    func declarationIdentityDoesNotRoundTripThroughCoordinates() {
        let fixture = Fixture.parse("func tar$0get(): Int64 { 1 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()
        @Expect(result.definitions.getOrThrow()[0].identity, result.owner.getOrThrow().identity)
        @Expect(semanticOriginText(result.definitions.getOrThrow()[0]), ["target"])
    }

    @TestCase
    func primitiveWrittenTypeIsAnObjectWithoutANominalDefinition() {
        let fixture = Fixture.parse("func f(x: Int$064): Unit {}")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
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
        @Assert(types.size, 1)
        @Expect(semanticOriginText(types[0]), ["Int64"])
        @Expect(types[0].typeDisplay(), Some("Int64"))
    }

    @TestCase
    func bodyTypeAndExpressionRetainSeparateIdentities() {
        let fixture = Fixture.parse("func f() { let x: Int$064 = 1 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()
        @Expect(result.objects.any { object => match (object.identity) {
            case BodyTypeIdentity(_, _) => semanticOriginText(object) == ["Int64"] && object.typeDisplay() == Some("Int64")
            case _ => false
        } })
    }

    @TestCase
    func literalSelectionFindsTheNearestExpression() {
        let fixture = Fixture.parse("func f() { 1 + 2$0 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
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
        @Assert(expressions.size, 1)
        @Expect(semanticOriginText(expressions[0]), ["2"])
        @Expect(expressions[0].typeDisplay(), Some("Int64"))
    }

    @TestCase
    func overloadsAndKnownEmptyMeaningsArePreserved() {
        let fixture = Fixture.parse("func f(x: Int64) {}\nfunc f(x: Bool) {}\nfunc g() { f$0 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        @Expect(analysis.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow().size, 2)
        let missing = Fixture.parse("func g() { absent$0 }")
        let missingDb = missing.database()
        let cursor = missing.cursor.getOrThrow()
        @Expect(SemanticAnalysis(missingDb).at(cursor.fileId, cursor.offset).getOrThrow().definitions.getOrThrow().size, 0)
        @Expect(analysis.at(at.fileId, -1).isNone())
        @Expect(analysis.at(at.fileId, 10000).isNone())
    }

    @TestCase
    func unicodeEvidenceAndNegotiatedCoordinatesUseTheSameText() {
        let fixture = Fixture.parse("func f() { let x = \"😀я\"; x$0 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()
        let prefix = "func f() { let x = \"😀я\"; "
        @Expect(result.location.excerpt(), Some("x"))
        @Expect(result.location.position(), Some(LineColumn(0, prefix.size)))
        let snapshotText = result.location.text().getOrThrow()
        @Expect(snapshotText.positionOf(result.location.focusRange.start, Encoding.Utf16), LineColumn(0, prefix.toRuneArray().size + 1))
        @Expect(snapshotText.positionOf(result.location.focusRange.start, Encoding.Utf32), LineColumn(0, prefix.toRuneArray().size))
    }

    @TestCase
    func editingInvalidatesObjectsAndEvidenceInsteadOfReadingNewText() {
        let fixture = Fixture.parse("func f() { let x = 1; x$0 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let result = analysis.at(at.fileId, at.offset).getOrThrow()
        let target = result.definitions.getOrThrow()[0]
        let copied = result.location.excerpt()
        let snapshotText = result.location.text().getOrThrow()
        db.setFileText(at.fileId, Rope("func f() {}"))
        @Expect(copied, Some("x"))
        @Expect(snapshotText.toString(), fixture.files[0].text)
        @AssertThrows[CancelledException](result.location.text())
        @AssertThrows[CancelledException](result.location.excerpt())
        @AssertThrows[CancelledException](target.origins())
        @AssertThrows[CancelledException](target.typeDisplay())
        @AssertThrows[CancelledException](analysis.at(at.fileId, at.offset))
    }

    @TestCase
    func binaryIdentitySurvivesMissingNavigationSource() {
        let fixture = Fixture.parse("main() { print$0ln(1) }")
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let at = fixture.cursor.getOrThrow()
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()
        let targets = result.definitions.getOrThrow()
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
    func expansionLocationsKeepGeneratedAndCopiedOrigins() {
        let (db, _, call, text) = answeredM()
        let analysis = SemanticAnalysis(db)
        let generated = analysis
            .inFile(ItemFile.Expansion(call), offsetIn(text, "Gen"))
            .getOrThrow()
        let target = generated.definitions.getOrThrow()[0]
        @Expect(semanticOriginText(target), ["Gen"])
        let location =
            match (target.origins()[0]) {
                case SourceOrigin(location) => location
                case _ => throw FixtureException("generated declaration has no expansion origin")
            }
        @Expect(location.kind(), SemanticSourceKind.ExpansionSource)
        @Expect(location.source().isNone())
        let copied = analysis.inFile(ItemFile.Expansion(call), offsetIn(text, "C")).getOrThrow()
        @Expect(copied.location.excerpt(), Some("C"))
        @Expect(copied.location.source().getOrThrow().excerpt(), Some("C"))
        let generic = analysis
            .inFile(ItemFile.Expansion(call), offsetIn(text, "<T>", plus: 1))
            .getOrThrow()
        @Expect(semanticOriginText(generic.definitions.getOrThrow()[0]), ["T"])
    }

    @TestCase
    func syntheticAndUnavailableBodyOriginsStayDistinct() {
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
        @Assert(synthetic.isSome())
        @Expect(match (analysis.object(ExpressionIdentity(owner, ExprId(synthetic.getOrThrow()))).origins()[0]) {
            case SyntheticOrigin => true
            case _ => false
        })
        @Expect(match (analysis.object(ExpressionIdentity(owner, ExprId(map.exprs.size))).origins()[0]) {
            case UnavailableOrigin => true
            case _ => false
        })
    }

    @TestCase
    func inactiveAndIncompleteCodeRemainInspectableWithoutInventedMeanings() {
        let fixture = Fixture.parse("//- /main.cj inactive=windows\nfunc f() { abs$0ent }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()
        @Expect(result.location.excerpt(), Some("absent"))
        @Expect(result.definitions.isNone())
        let incomplete = Fixture.parse("func f() { let $0")
        let incompleteDb = incomplete.database()
        let cursor = incomplete.cursor.getOrThrow()
        @Expect(SemanticAnalysis(incompleteDb).at(cursor.fileId, cursor.offset).isSome())
    }

    @TestCase
    func requestCancellationReachesThePinnedAnalysis() {
        let fixture = Fixture.parse("func f() { 1$0 }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let stop = AtomicBool(false)
        let analysis = SemanticAnalysis(db.snapshot(cancelledBy: { => stop.load() }))
        let result = analysis.at(at.fileId, at.offset).getOrThrow()
        stop.store(true)
        @AssertThrows[CancelledException](result.location.excerpt())
        @AssertThrows[CancelledException](analysis.at(at.fileId, at.offset))
    }

    @TestCase
    func aPatternBindingExposesBothPatternAndLocalIdentities() {
        let fixture = Fixture.parse("func f() { let (a$0, b) = (1, 2); a }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let result = SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow()
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
    func genericParameterDeclarationAndUseHaveTheSameIdentity() {
        let fixture = Fixture.parse("func f<T>(x: T$0): T { x }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let use = analysis.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]
        let declaration = analysis
            .at(at.fileId, fixture.files[0].text.indexOf("T>").getOrThrow())
            .getOrThrow()
        @Expect(use.identity, declaration.definitions.getOrThrow()[0].identity)
        @Expect(semanticOriginText(use), ["T"])
    }

    @TestCase
    func checkedBinaryAttachmentIsLabeledAndReadFromTheSnapshot() {
        let fixture = Fixture.parse("main() { print$0ln(1) }")
        let db = fixture.database(
            binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: [stdWithSources(["std.core"])]
        )
        let at = fixture.cursor.getOrThrow()
        let analysis = SemanticAnalysis(db)
        let target = analysis.at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]
        let location =
            match (target.origins()[0]) {
                case SourceOrigin(location) => location
                case _ => throw FixtureException("checked binary has no source")
            }
        @Expect(location.kind(), SemanticSourceKind.AttachedSource)
        @Expect(location.excerpt(), Some("println"))
        let declaration = analysis.inFile(location.file, location.focusRange.start).getOrThrow()
        @Expect(declaration.definitions.getOrThrow()[0].identity, target.identity)
    }

    @TestCase
    func namedTypeIdentityIsDistinctFromConstructorNavigation() {
        let fixture = Fixture.parse("class C { init(x: Int64) {} }\nmain() { C$0(1) }")
        let db = fixture.database()
        let at = fixture.cursor.getOrThrow()
        let target =
            SemanticAnalysis(db).at(at.fileId, at.offset).getOrThrow().definitions.getOrThrow()[0]
        @Expect(match (target.identity) {
            case NamedIdentity(DeclDef(id)) => id.item(db).kind == ItemKind.Class
            case _ => false
        })
        @Expect(semanticOriginText(target), ["C"])
        let navigation = definitionAt(db, at.fileId, at.offset)
        @Assert(navigation.size, 1)
        let text = db.sourceFile(at.fileId).getOrThrow().text(db)
        @Expect(text.slice(navigation[0].focusRange.start..navigation[0].focusRange.end).toString(), "init")
    }
}
