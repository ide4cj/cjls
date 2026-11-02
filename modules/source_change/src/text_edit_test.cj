package source_change

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange

@Test
class TextEditTest {
    @TestCase
    func unorderedEditsUseOriginalUtf8CoordinatesAndLeaveTheInputUntouched(): Unit {
        // arrange
        let edits = [TextEdit(TextRange(8, 9), "!"), TextEdit(TextRange(0, 2), "я")]

        // act
        let result = applyEdits("ёж😀x", edits)

        // assert
        @Expect(result, "яж😀!")
        @Expect(edits[0].range, TextRange(8, 9))
    }

    @TestCase
    func insertionsAtTheSamePositionRetainInputOrderAroundAReplacement(): Unit {
        // arrange
        let edits =
            [
                TextEdit(TextRange(1, 2), "X"),
                TextEdit(TextRange(1, 1), "a"),
                TextEdit(TextRange(2, 2), "c"),
                TextEdit(TextRange(1, 1), "b")
            ]

        // act
        let result = applyEdits("012", edits)

        // assert
        @Expect(result, "0abXc2")
    }

    @TestCase
    func emptyChangesAndWholeFileDeletionAreValid(): Unit {
        // arrange
        let original = "привет\r\n"

        // act
        let unchanged = applyEdits(original, [])
        let deleted = applyEdits(original, [TextEdit(TextRange(0, original.size), "")])
        let created = applyEdits("", [TextEdit(TextRange(0, 0), original)])

        // assert
        @Expect(unchanged, original)
        @Expect(deleted, "")
        @Expect(created, original)
    }

    @TestCase
    func overlapAndInsertionsInsideReplacementsAreRejected(): Unit {
        // arrange
        let replacement = TextEdit(TextRange(0, 2), "x")

        // act / assert
        @AssertThrows[IllegalArgumentException](applyEdits("abc", [replacement, replacement]))
        @AssertThrows[IllegalArgumentException](applyEdits("abc", [replacement,
            TextEdit(TextRange(1, 1), "y")]))
    }

    @TestCase
    func outOfBoundsAndSplitUtf8CharactersAreRejected(): Unit {
        // arrange
        let text = "ё😀"

        // act / assert
        @AssertThrows[IllegalArgumentException](applyEdits(text, [TextEdit(TextRange(7, 7), "x")]))
        @AssertThrows[IllegalArgumentException](applyEdits(text, [TextEdit(TextRange(0, 7), "x")]))
        @AssertThrows[IllegalArgumentException](applyEdits(text, [TextEdit(TextRange(1, 2), "x")]))
        @AssertThrows[IllegalArgumentException](applyEdits(text, [TextEdit(TextRange(2, 3), "x")]))
    }
}
