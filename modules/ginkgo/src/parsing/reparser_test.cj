package ginkgo.parsing

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.*

func edited(text: String, delete: TextRange, insert: String): String {
    text[..delete.start] + insert + text[delete.end..]
}

@Test
class ReparserTest {
    @TestCase
    func anEditInAGroupReparsesThatGroupAndSharesTheRest() {
        // arrange
        let text = "1 + (2 * 3)\n4 >> 5\n"
        let before = toyParse(text)
        let lines = collectArray(before.syntaxNode().children())
        let edit = TextRange.empty(text.indexOf("3").getOrThrow())

        // act
        let after = toyReparser().reparse(before, edit, "7 + ")

        // assert
        let reparsed = after.getOrThrow()
        @Expect(reparsed == toyParse(edited(text, edit, "7 + ")))
        @Expect(reparsed.syntaxNode().text(), "1 + (2 * 7 + 3)\n4 >> 5\n")
        let linesAfter = collectArray(reparsed.syntaxNode().children())
        @Expect(refEq(linesAfter[1].green, lines[1].green))
        @Expect(!refEq(linesAfter[0].green, lines[0].green))
    }

    @TestCase
    func errorsOutsideTheGroupAreKeptAndShiftedPastTheEdit() {
        // arrange
        let text = "1 ? \n(2 * 3)\n4 ?\n"
        let before = toyParse(text)
        let edit = TextRange(text.indexOf("3").getOrThrow(), text.indexOf("3").getOrThrow() + 1)

        // act
        let after = toyReparser().reparse(before, edit, "33 + 4")

        // assert
        let reparsed = after.getOrThrow()
        let full = toyParse(edited(text, edit, "33 + 4"))
        @Expect(reparsed == full)
        @Expect(reparsed.errors.size, before.errors.size)
        @Expect(reparsed.errors[0].range, before.errors[0].range)
        let last = reparsed.errors.size - 1
        @Expect(reparsed.errors[last].range, before.errors[last].range.shift(5))
    }

    @TestCase
    func anEditLeavingTheGroupUnbalancedIsNotReparsed() {
        // arrange
        let text = "1 + (2 * 3)\n"
        let before = toyParse(text)
        let edit = TextRange.empty(text.indexOf("3").getOrThrow())

        // act
        let closedEarly = toyReparser().reparse(before, edit, ")")
        let openedAgain = toyReparser().reparse(before, edit, "(")

        // assert
        @Expect(closedEarly.isNone())
        @Expect(openedAgain.isNone())
    }

    @TestCase
    func anEditOutsideAnyGroupIsNotReparsed() {
        // arrange
        let text = "1 + (2 * 3)\n4\n"
        let before = toyParse(text)

        // act
        let after =
            toyReparser().reparse(before, TextRange.empty(text.indexOf("4").getOrThrow()), "5 + ")

        // assert
        @Expect(after.isNone())
    }

    @TestCase
    func anEditTheGroupsGrammarDoesNotConsumeWholeIsNotReparsed() {
        // arrange
        let text = "(1)\n"
        let before = toyParse(text)

        // act
        let after = toyReparser().reparse(before, TextRange.empty(2), " 2")

        // assert
        @Expect(after.isNone())
        @Expect(toyParse("(1 2)").errors.size > 0)
    }

    @TestCase
    func anEditOutsideTheTextIsNotReparsed() {
        // arrange
        let before = toyParse("(1)\n")

        // act
        let after = toyReparser().reparse(before, TextRange.empty(10), "2")

        // assert
        @Expect(after.isNone())
    }
}
