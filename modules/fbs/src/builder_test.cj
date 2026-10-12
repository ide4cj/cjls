package fbs

import std.unittest.*
import std.unittest.testmacro.*

/**
 * A struct `{ a: UInt8; b: Int32 }`: `a` at 0, `b` at 4, 8 bytes aligned to 4.
 */
func pairBytes(a: UInt8, b: Int32): Array<Byte> {
    let bytes = Array<Byte>(8, repeat: 0)
    writeUInt8(bytes, 0, a)
    writeInt32(bytes, 4, b)
    bytes
}

@Test
class FbBuilderTest {
    @TestCase
    func aTableIsReadBackFieldByField(): Unit {
        // arrange
        let b = FbBuilder(capacity: 16)
        let name = b.createString("tokens")
        let numbers = b.createVector([b.createString("one"), b.createString("two")])
        b.startTable()
        b.addInt64(-7)
        b.slot(0)
        b.addOffset(name)
        b.slot(1)
        b.addBool(true)
        b.slot(3)
        b.addOffset(numbers)
        b.slot(4)
        b.addStruct(pairBytes(9, -300), 4)
        b.slot(5)
        let root = b.endTable()

        // act
        let fb = FbTable.at(b.finish(root), 0)

        // assert
        @Expect(fb.scalar(0, 0, readInt64), -7)
        @Expect(fb.string(1), Some("tokens"))
        @Expect(fb.offset(2), 0)
        @Expect(fb.scalar(2, 42, readInt32), 42)
        @Expect(fb.scalar(3, false, readBool), true)
        @Expect(fb.vector(4, 4, readString).toArray(), ["one", "two"])
        let pair = fb.structAt(5).getOrThrow()
        @Expect(readUInt8(fb.buf, pair), 9)
        @Expect(readInt32(fb.buf, pair + 4), -300)
    }

    @TestCase
    func everyValueIsAlignedToItsSizeFromTheStart(): Unit {
        // arrange
        let b = FbBuilder()
        let text = b.createString("abc")
        b.startVector(8, 2, 8)
        b.addInt64(2)
        b.addInt64(1)
        let longs = b.endVector(2)
        b.startTable()
        b.addUInt8(1)
        b.slot(0)
        b.addOffset(text)
        b.slot(1)
        b.addOffset(longs)
        b.slot(2)
        let root = b.endTable()

        // act
        let buf = b.finish(root)
        let fb = FbTable.at(buf, 0)

        // assert
        @Expect(buf.size % 8, 0)
        @Expect(fb.pos % 4, 0)
        let at = follow(buf, fb.pos + fb.offset(2))
        @Expect((at + 4) % 8, 0)
        @Expect(fb.vector(2, 8, readInt64).toArray(), [1, 2])
        @Expect(follow(buf, fb.pos + fb.offset(1)) % 4, 0)
    }

    @TestCase
    func aStringEndsWithAZeroPastItsLength(): Unit {
        // arrange
        let b = FbBuilder()
        let s = b.createString("ab")
        b.startTable()
        b.addOffset(s)
        b.slot(0)
        let root = b.endTable()

        // act
        let buf = b.finish(root)
        let fb = FbTable.at(buf, 0)

        // assert
        let at = follow(buf, fb.pos + fb.offset(0))
        @Expect(readUInt32(buf, at), 2)
        @Expect(buf[at + 4..at + 7].toArray(), [b'a', b'b', 0])
    }

    @TestCase
    func aUnionsValueIsAStructAloneOrATable(): Unit {
        // arrange
        let b = FbBuilder()
        let alone = b.createStruct(pairBytes(1, 2), 4)
        b.startTable()
        b.addUInt8(2)
        b.slot(0)
        b.addOffset(alone)
        b.slot(1)
        let root = b.endTable()

        // act
        let fb = FbTable.at(b.finish(root), 0)

        // assert
        @Expect(fb.scalar(0, 0, readUInt8), 2)
        let pair = follow(fb.buf, fb.pos + fb.offset(1))
        @Expect(readInt32(fb.buf, pair + 4), 2)
    }

    @TestCase
    func theFileIdentifierFollowsTheRootOffset(): Unit {
        // arrange
        let b = FbBuilder()
        b.startTable()
        let root = b.endTable()

        // act
        let buf = b.finish(root, fileIdentifier: "CJOF")

        // assert
        @Expect(String.fromUtf8(buf[4..8]), "CJOF")
        @Expect(FbTable.at(buf, 0).offset(0), 0)
    }

    @TestCase
    func aBufferThatGrowsKeepsWhatWasWritten(): Unit {
        // arrange
        let b = FbBuilder(capacity: 16)
        let words = Array<String>(100) {i => "word ${i}"}

        // act
        let vector = b.createStringVector(words)
        b.startTable()
        b.addOffset(vector)
        b.slot(0)
        let fb = FbTable.at(b.finish(b.endTable()), 0)

        // assert
        @Expect(fb.vector(0, 4, readString).toArray(), words)
    }

    @TestCase
    func aTableStartedInAnotherIsRefused(): Unit {
        // arrange
        let b = FbBuilder()
        b.startTable()

        // act, assert
        @AssertThrows[IllegalStateException](b.startTable())
    }
}
