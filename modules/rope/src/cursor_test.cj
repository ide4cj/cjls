package rope

import std.random.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class PositionCursorTest {
    @TestCase
    func positionsInTheOrderOfTheTextAgreeWithPositionOf() {
        // arrange
        let random = Random(13)
        let text = randomText(random, 3000)
        let rope = Rope(text)

        for (encoding in [Utf8, Utf16, Utf32]) {
            let cursor = PositionCursor(rope, encoding)
            for (offset in boundaries(text)) {
                // act
                let position = cursor.positionOf(offset)
                let units = cursor.unitsBefore(offset)

                // assert
                @Assert(position, rope.positionOf(offset, encoding))
                @Assert(units, rope.summaryBefore(offset).measure(encoding))
            }
        }
    }

    @TestCase
    func offsetsLeavesApartAgreeWithPositionOf() {
        // arrange
        let random = Random(14)
        let line =
            String
                .join(
                    Array(3 * MAX_CHUNK) { _ => PIECES[random.nextInt64(PIECES.size)] }
                        .filter { p => !p.contains("\n") }
                )
        let text = "${line}\n${line}\r\n${line}"
        let rope = Rope(text)
        let offsets = boundaries(text)
        let cursor = PositionCursor(rope, Utf16)

        for (i in 0..offsets.size: 997) {
            // act
            let position = cursor.positionOf(offsets[i])

            // assert
            @Assert(position, rope.positionOf(offsets[i], Utf16))
        }
    }

    @TestCase
    func anOffsetBeforeTheLastOneThrows() {
        // arrange
        let cursor = PositionCursor(Rope("ab\ncd"), Utf16)
        cursor.positionOf(4)

        // act, assert
        @AssertThrows[IllegalArgumentException](cursor.positionOf(3))
    }

    @TestCase
    func anOffsetPastTheEndThrows() {
        // arrange
        let cursor = PositionCursor(Rope("ab"), Utf16)

        // act, assert
        @AssertThrows[IndexOutOfBoundsException](cursor.positionOf(3))
    }

    @TestCase
    func anOffsetInsideACharacterThrowsAndLeavesTheOffsetsAfterIt() {
        // arrange
        let rope = Rope("й😀x")
        let cursor = PositionCursor(rope, Utf16)

        // act, assert
        @AssertThrows[IllegalArgumentException](cursor.positionOf(1))
        @Expect(cursor.positionOf(6), LineColumn(0, 3))
    }
}
