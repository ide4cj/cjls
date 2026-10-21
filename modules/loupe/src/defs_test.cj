package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.Fixture
import loupe.syntax.parse

@Test
class NameClassificationTest {
    @TestCase
    func anOrdinaryNameLeavesBothSpecializedLookupsToTheBody() {
        let fixture = Fixture.parse("func f() { let x = 1; x$0 }")
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let source = db.sourceFile(cursor.fileId).getOrThrow()
        let token = tokenAt(parse(db, source).syntaxNode(), cursor.offset).getOrThrow()

        @Expect(match (macroDefinitions(db, source, token)) {
            case NotApplicable => true
            case _ => false
        })
        @Expect(match (importDefinitions(db, source, token)) {
            case NotApplicable => true
            case _ => false
        })
        @Expect(definitionAt(db, cursor.fileId, cursor.offset).size, 1)
    }

    @TestCase
    func aMacroInAnInactiveFileIsUnknownAndStopsClassification() {
        let fixture = Fixture.parse(#"
            //- /main.cj inactive=windows
            @Miss$0ing
            func f() {}
            "#)
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let source = db.sourceFile(cursor.fileId).getOrThrow()
        let token = tokenAt(parse(db, source).syntaxNode(), cursor.offset).getOrThrow()

        @Expect(match (macroDefinitions(db, source, token)) {
            case UnknownMeaning => true
            case _ => false
        })
        @Expect(classifyName(db, source, None, token).isNone())
        @Expect(hoverAt(db, cursor.fileId, cursor.offset).isNone())
    }

    @TestCase
    func anUnresolvedMacroIsAnApplicableLookupWithNoDefinitions() {
        let fixture = Fixture.parse("@Miss$0ing func f() {}")
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let source = db.sourceFile(cursor.fileId).getOrThrow()
        let token = tokenAt(parse(db, source).syntaxNode(), cursor.offset).getOrThrow()

        @Expect(match (macroDefinitions(db, source, token)) {
            case NameDefinitions(defs) => defs.isEmpty()
            case _ => false
        })
        @Expect(classifyName(db, source, None, token), Some(Array<Definition>()))
    }

    @TestCase
    func anImportInAnInactiveFileIsApplicableWithNoDefinitions() {
        let fixture = Fixture.parse(#"
            //- /main.cj inactive=windows
            import absent.na$0me
            "#)
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let source = db.sourceFile(cursor.fileId).getOrThrow()
        let token = tokenAt(parse(db, source).syntaxNode(), cursor.offset).getOrThrow()

        @Expect(match (importDefinitions(db, source, token)) {
            case NameDefinitions(defs) => defs.isEmpty()
            case _ => false
        })
        @Expect(classifyName(db, source, None, token), Some(Array<Definition>()))
    }
}
