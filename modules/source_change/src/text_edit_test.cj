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
        const ORIGINAL = "привет\r\n"

        // act
        let unchanged = applyEdits(ORIGINAL, [])
        let deleted = applyEdits(ORIGINAL, [TextEdit(TextRange(0, ORIGINAL.size), "")])
        let created = applyEdits("", [TextEdit(TextRange(0, 0), ORIGINAL)])

        // assert
        @Expect(unchanged, ORIGINAL)
        @Expect(deleted, "")
        @Expect(created, ORIGINAL)
    }

    @TestCase
    func overlapAndInsertionsInsideReplacementsAreRejected(): Unit {
        // arrange
        let replacement = TextEdit(TextRange(0, 2), "x")
        let overlapping = [replacement, replacement]
        let inside = [replacement, TextEdit(TextRange(1, 1), "y")]

        // act / assert
        @AssertThrows[IllegalArgumentException](applyEdits("abc", overlapping))
        @AssertThrows[IllegalArgumentException](applyEdits("abc", inside))
    }

    @TestCase
    func outOfBoundsAndSplitUtf8CharactersAreRejected(): Unit {
        // arrange
        const TEXT = "ё😀"

        // act / assert
        @AssertThrows[IllegalArgumentException](applyEdits(TEXT, [TextEdit(TextRange(7, 7), "x")]))
        @AssertThrows[IllegalArgumentException](applyEdits(TEXT, [TextEdit(TextRange(0, 7), "x")]))
        @AssertThrows[IllegalArgumentException](applyEdits(TEXT, [TextEdit(TextRange(1, 2), "x")]))
        @AssertThrows[IllegalArgumentException](applyEdits(TEXT, [TextEdit(TextRange(2, 3), "x")]))
    }
}
