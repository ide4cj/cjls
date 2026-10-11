package loupe

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import rope.Rope
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase

@Test
class FormattingTest {
    @TestCase
    func aFileIsFormattedByEditsOfItsWhitespace() {
        // arrange
        let db = AnalysisDatabase()
        db.setFileText(FileId(0), Rope("func f() {\nx  \n}\n"))

        // act
        let edits = formatting(db, FileId(0))

        // assert
        @Expect(edits, Some([TextEdit(TextRange(10, 11), "\n    "), TextEdit(TextRange(12, 15), "\n")]))
    }

    @TestCase
    func aFileWithSyntaxErrorsOrNotKnownHasNone() {
        // arrange
        let db = AnalysisDatabase()
        db.setFileText(FileId(0), Rope("func f( {\n"))

        // act, assert
        @Expect(formatting(db, FileId(0)), None)
        @Expect(formatting(db, FileId(1)), None)
    }

    @TestCase
    func theLinesOfARangeAreFormattedAndNoOther() {
        // arrange
        let db = AnalysisDatabase()
        db.setFileText(FileId(0), Rope("func f() {\nx\ny\n}\n"))

        // act
        let edits = rangeFormatting(db, FileId(0), TextRange(13, 14))

        // assert
        @Expect(edits, Some([TextEdit(TextRange(13, 13), "    ")]))
    }
}
