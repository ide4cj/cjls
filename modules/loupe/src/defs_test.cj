package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.Fixture
import loupe.syntax.parse

@Test
class NameClassificationTest {
    @TestCase
    func anOrdinaryNameLeavesBothSpecializedLookupsToTheBody() {
        // arrange
        let fixture = Fixture.parse("func f() { let x = 1; x$0 }")
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let source = db.sourceFile(cursor.fileId).getOrThrow()
        let token = tokenAt(parse(db, source).syntaxNode(), cursor.offset).getOrThrow()

        // act
        let macroName = macroDefinitions(db, source, token)
        let importName = importDefinitions(db, source, token)
        let targets = definitionAt(db, cursor.fileId, cursor.offset)

        // assert
        @Expect(match (macroName) {
            case NotApplicable => true
            case _ => false
        })
        @Expect(match (importName) {
            case NotApplicable => true
            case _ => false
        })
        @Expect(targets.size, 1)
    }

    @TestCase
    func aMacroInAnInactiveFileIsUnknownAndStopsClassification() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /main.cj inactive=windows
            @Miss$0ing
            func f() {}
            "#
                )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let source = db.sourceFile(cursor.fileId).getOrThrow()
        let token = tokenAt(parse(db, source).syntaxNode(), cursor.offset).getOrThrow()

        // act
        let macroName = macroDefinitions(db, source, token)
        let classified = classifyName(db, source, None, token)
        let hover = hoverAt(db, cursor.fileId, cursor.offset)

        // assert
        @Expect(match (macroName) {
            case UnknownMeaning => true
            case _ => false
        })
        @Expect(classified.isNone())
        @Expect(hover.isNone())
    }

    @TestCase
    func anUnresolvedMacroIsAnApplicableLookupWithNoDefinitions() {
        // arrange
        let fixture = Fixture.parse("@Miss$0ing func f() {}")
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let source = db.sourceFile(cursor.fileId).getOrThrow()
        let token = tokenAt(parse(db, source).syntaxNode(), cursor.offset).getOrThrow()

        // act
        let macroName = macroDefinitions(db, source, token)
        let classified = classifyName(db, source, None, token)

        // assert
        @Expect(match (macroName) {
            case NameDefinitions(defs) => defs.isEmpty()
            case _ => false
        })
        @Expect(classified, Some(Array<Definition>()))
    }

    @TestCase
    func anImportInAnInactiveFileIsApplicableWithNoDefinitions() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /main.cj inactive=windows
            import absent.na$0me
            "#
                )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let source = db.sourceFile(cursor.fileId).getOrThrow()
        let token = tokenAt(parse(db, source).syntaxNode(), cursor.offset).getOrThrow()

        // act
        let importName = importDefinitions(db, source, token)
        let classified = classifyName(db, source, None, token)

        // assert
        @Expect(match (importName) {
            case NameDefinitions(defs) => defs.isEmpty()
            case _ => false
        })
        @Expect(classified, Some(Array<Definition>()))
    }
}
