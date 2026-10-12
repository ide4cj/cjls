package macro_server

import std.io.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class FrameTest {
    @TestCase
    func aMessageIsReadBackAsItWasWritten(): Unit {
        // arrange
        let pipe = ByteBuffer()
        writeMessage(pipe, [1, 2, 3])
        writeMessage(pipe, Array<Byte>(5000) {i => UInt8(i % 256)})

        // act
        let first = readMessage(pipe)
        let second = readMessage(pipe)

        // assert
        @Expect(first, Some<Array<Byte>>([1, 2, 3]))
        @Expect(second, Some(Array<Byte>(5000) {i => UInt8(i % 256)}))
        @Expect(readMessage(pipe), None<Array<Byte>>)
    }

    @TestCase
    func theLengthIsANativeSizeT(): Unit {
        // arrange
        let pipe = ByteBuffer()

        let expected: Array<Byte> = [1, 0, 0, 0, 0, 0, 0, 0, 7]

        // act
        writeMessage(pipe, [7])

        // assert
        @Expect(pipe.bytes().toArray(), expected)
    }

    @TestCase
    func anOutputEndingInsideAMessageThrows(): Unit {
        // arrange
        let pipe = ByteBuffer()
        pipe.write([4, 0, 0, 0, 0, 0, 0, 0, 1, 2])

        // act, assert
        @AssertThrows[MacroServerException](readMessage(pipe))
    }
}
