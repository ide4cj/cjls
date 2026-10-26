package cjformat

import std.unittest.*
import std.unittest.testmacro.*
import cjsyntax.parse
import ginkgo.TextRange

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
    let start = lines[..first].fold(0) { offset, line => offset + line.size + 1 }
    let end = lines[first..last].fold(start) { offset, line => offset + line.size + 1 }
    TextRange(start, end + lines[last].size)
}

@Test
class FormatRangeTest {
    @TestCase
    func onlyTheSelectedStatementChanges(): Unit {
        // arrange
        let text = "func f() {\nlet a = 1\nlet b = 2\nlet c = 3\n}\n"

        // act
        let formatted = formattedIn(text, linesOf(text, 2, 2))

        // assert
        @Expect(formatted, Some("func f() {\nlet a = 1\n    let b = 2\nlet c = 3\n}\n"))
    }

    @TestCase
    func aLineIsIndentedAsTheWholeFileIndentsItAndTheLineBeforeKeepsItsEnd(): Unit {
        // arrange - trailing spaces on the line before, in the same edit as the indent
        let text = "class A {\nfunc f() {   \nlet a = 1\n}\n}\n"

        // act
        let formatted = formattedIn(text, linesOf(text, 2, 2))

        // assert
        @Expect(formatted, Some("class A {\nfunc f() {   \n        let a = 1\n}\n}\n"))
    }

    @TestCase
    func theEndOfALineCoveredIsFormattedButNotTheIndentOfTheNext(): Unit {
        // arrange
        let text = "func f() {\nlet a = 1   \nlet b = 2\n}\n"

        // act
        let formatted = formattedIn(text, linesOf(text, 1, 1))

        // assert
        @Expect(formatted, Some("func f() {\n    let a = 1\nlet b = 2\n}\n"))
    }

    @TestCase
    func aRangeCoveringSeveralSiblingsFormatsTheirEnclosingBody(): Unit {
        // arrange - lines 1 and 2 selected whole, as VS Code selects them
        let text = "func f() {\nlet a = 1\nlet b = 2\nlet c = 3\n}\n"
        let range = TextRange(linesOf(text, 1, 1).start, linesOf(text, 3, 3).start)

        // act
        let formatted = formattedIn(text, range)

        // assert
        @Expect(formatted, Some("func f() {\n    let a = 1\n    let b = 2\n    let c = 3\n}\n"))
    }

    @TestCase
    func aBodySelectionDoesNotReformatItsDeclarationHeader(): Unit {
        // arrange
        let text = "func   f() {\na\nb\n}\n"

        // act
        let formatted = formattedIn(text, linesOf(text, 1, 2))

        // assert
        @Expect(formatted, Some("func   f() {\n    a\n    b\n}\n"))
    }

    @TestCase
    func aRangeWithinALineCoversTheLine(): Unit {
        // arrange
        let text = "func f() {\nlet a = 1\n}\n"
        let start = linesOf(text, 1, 1).start + 4

        // act
        let formatted = formattedIn(text, TextRange(start, start + 1))

        // assert
        @Expect(formatted, Some("func f() {\n    let a = 1\n}\n"))
    }

    @TestCase
    func theRangeAtTheEndCoversTheLastLineBreak(): Unit {
        // arrange
        let text = "func f() {}\n\n\n"

        // act
        let formatted = formattedIn(text, linesOf(text, 0, 0))

        // assert
        @Expect(formatted, Some("func f() {}\n"))
    }

    @TestCase
    func aBraceJoinsTheLineBeforeWhenEitherLineIsCovered(): Unit {
        // arrange
        let text = "func f()\n    {\n}\n"

        // act
        let fromFirst = formattedIn(text, linesOf(text, 0, 0))
        let fromSecond = formattedIn(text, linesOf(text, 1, 1))

        // assert
        @Expect(fromFirst, Some("func f() {}\n"))
        @Expect(fromSecond, Some("func f() {}\n"))
    }

    @TestCase
    func aRangeCanJoinLinesOutsideTheSelectionButKeepsTheNextStatement(): Unit {
        // arrange
        let text = "func f() {\ncall(a,\nb)\nx\n}\n"

        // act
        let formatted = formattedIn(text, linesOf(text, 2, 2))

        // assert
        @Expect(formatted, Some("func f() {\n    call(a, b)\nx\n}\n"))
    }

    @TestCase
    func continuationIndentationComesFromTheWholeFileLayout(): Unit {
        // arrange
        let text = "func f() {\nlet g = { x =>\na(x)\nb(x)\n}\n}\n"

        // act
        let formatted = formattedIn(text, linesOf(text, 3, 3))

        // assert
        @Expect(formatted, Some("func f() {\nlet g = { x =>\na(x)\n            b(x)\n}\n}\n"))
    }

    @TestCase
    func aRangeReservesThePunctuationAfterItsSelectedNode(): Unit {
        // arrange
        let name = "a" * 90
        let text = "func f() {\n    call(${name});\n}\n"
        let start = text.indexOf("call").getOrThrow()

        // act
        let formatted = formattedIn(text, TextRange(start, start + 1))

        // assert
        @Expect(formatted, formatText(text))
    }

    @TestCase
    func aSelectionInsideAMacroCannotReformatItsInternalStatements(): Unit {
        // arrange
        let text = "func f() {\n    @M({ x =>\na(x)\nb(x)\n})\n}\n"

        // act
        let formatted = formattedIn(text, linesOf(text, 3, 3))

        // assert
        @Expect(formatted, Some(text))
    }

    @TestCase
    func aFileWithSyntaxErrorsIsNotFormatted(): Unit {
        // arrange
        let text = "func f( {\nlet a = 1\n"

        // act
        let edits = formatRange(parse(text), linesOf(text, 1, 1))

        // assert
        @Expect(edits, None)
    }
}
