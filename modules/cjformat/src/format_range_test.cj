package cjformat

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import cjsyntax.parse

/**
 * `text` with the edits of `formatRange` over `range` made to it.
 */
func formattedIn(text: String, range: TextRange): ?String {
    let edits = formatRange(parse(text), range) ?? return None
    applyEdits(text, edits)
}

/**
 * The range from the start of line `first` to the end of line `last` (0-based), as Neovim's `gq`
 * asks for it.
 */
func linesOf(text: String, first: Int64, last: Int64): TextRange {
    let lines = text.split("\n")
    var start = 0
    for (line in lines[..first]) {
        start += line.size + 1
    }
    var end = start
    for (line in lines[first..last]) {
        end += line.size + 1
    }
    TextRange(start, end + lines[last].size)
}

@Test
class FormatRangeTest {
    @TestCase
    func onlyTheLinesCoveredChange() {
        // arrange
        let text = "func f() {\nlet a = 1\nlet b = 2\nlet c = 3\n}\n"

        // act
        let formatted = formattedIn(text, linesOf(text, 2, 2))

        // assert
        @Expect(formatted, Some("func f() {\nlet a = 1\n    let b = 2\nlet c = 3\n}\n"))
    }

    @TestCase
    func aLineIsIndentedAsTheWholeFileIndentsItAndTheLineBeforeKeepsItsEnd() {
        // arrange - trailing spaces on the line before, in the same edit as the indent
        let text = "class A {\nfunc f() {   \nlet a = 1\n}\n}\n"

        // act
        let formatted = formattedIn(text, linesOf(text, 2, 2))

        // assert
        @Expect(formatted, Some("class A {\nfunc f() {   \n        let a = 1\n}\n}\n"))
    }

    @TestCase
    func theEndOfALineCoveredIsFormattedButNotTheIndentOfTheNext() {
        // arrange
        let text = "func f() {\nlet a = 1   \nlet b = 2\n}\n"

        // act
        let formatted = formattedIn(text, linesOf(text, 1, 1))

        // assert
        @Expect(formatted, Some("func f() {\n    let a = 1\nlet b = 2\n}\n"))
    }

    @TestCase
    func aRangeEndingWhereALineStartsDoesNotCoverIt() {
        // arrange - lines 1 and 2 selected whole, as VS Code selects them
        let text = "func f() {\nlet a = 1\nlet b = 2\nlet c = 3\n}\n"
        let range = TextRange(linesOf(text, 1, 1).start, linesOf(text, 3, 3).start)

        // act
        let formatted = formattedIn(text, range)

        // assert
        @Expect(formatted, Some("func f() {\n    let a = 1\n    let b = 2\nlet c = 3\n}\n"))
    }

    @TestCase
    func aRangeWithinALineCoversTheLine() {
        // arrange
        let text = "func f() {\nlet a = 1\n}\n"
        let start = linesOf(text, 1, 1).start + 4

        // act
        let formatted = formattedIn(text, TextRange(start, start + 1))

        // assert
        @Expect(formatted, Some("func f() {\n    let a = 1\n}\n"))
    }

    @TestCase
    func theRangeAtTheEndCoversTheLastLineBreak() {
        // arrange
        let text = "func f() {}\n\n\n"

        // act
        let formatted = formattedIn(text, linesOf(text, 0, 0))

        // assert
        @Expect(formatted, Some("func f() {}\n"))
    }

    @TestCase
    func aFileWithSyntaxErrorsIsNotFormatted() {
        // arrange
        let text = "func f( {\nlet a = 1\n"

        // act, assert
        @Expect(formatRange(parse(text), linesOf(text, 1, 1)), None)
    }
}
