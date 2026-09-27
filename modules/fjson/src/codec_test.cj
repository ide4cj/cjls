package fjson

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private func written<T>(value: T): String where T <: ToJson {
    String.fromUtf8(toJsonBytes(value))
}

private func read<T>(text: String): T where T <: FromJson<T> {
    fromJsonBytes<T>(text.toArray())
}

@Test
class FjCodecTest {
    @TestCase
    func scalarsRoundTrip() {
        // act & assert
        @Expect(#""a\"b""#, written("a\"b"))
        @Expect("a\"b", read<String>(#""a\"b""#))
        @Expect("true", written(true))
        @Expect(false, read<Bool>("false"))
        @Expect("-7", written(Int32(-7)))
        @Expect(UInt32(4000000000), read<UInt32>("4000000000"))
        @Expect(1.5, read<Float64>("1.5"))
    }

    @TestCase
    func aNumberOutsideItsTypeThrows() {
        // act & assert
        @AssertThrows[FjException](read<Int32>("2147483648"))
        @AssertThrows[FjException](read<UInt32>("-1"))
        @AssertThrows[FjException](read<Int64>("1.0"))
    }

    @TestCase
    func anOptionIsItsValueOrNull() {
        // act & assert
        @Expect("null", written(Option<String>.None))
        @Expect(#""x""#, written(Some("x")))
        @Expect(Option<String>.None, read<Option<String>>("null"))
        @Expect(Some("x"), read<Option<String>>(#""x""#))
    }

    @TestCase
    func anArrayIsAnArray() {
        // act & assert
        @Expect("[1,2,3]", written([1, 2, 3]))
        @Expect([1, 2, 3], read<Array<Int64>>(" [ 1 , 2 , 3 ] "))
        @Expect(0, read<Array<Int64>>("[]").size)
    }

    @TestCase
    func aMapIsAnObjectOfItsKeys() {
        // arrange
        let map = HashMap<String, Array<Int64>>()
        map["a"] = [1]

        // act
        let restored = read<HashMap<String, Array<Int64>>>(#"{"a": [1], "b": []}"#)

        // assert
        @Expect(#"{"a":[1]}"#, written(map))
        @Expect([1], restored["a"])
        @Expect(0, restored["b"].size)
    }

    @TestCase
    func aRawValueIsItsOwnBytesUnread() {
        // arrange
        let r = FjReader(#"{"params": {"a" : [1, "x"]}, "next": 2}"#.toArray())
        r.beginObject()
        r.nextKey()

        // act
        let raw = RawJson.fromJson(r)
        r.nextKey()

        // assert
        @Expect(#"{"a" : [1, "x"]}"#, raw.toString())
        @Expect(2, r.readInt64())
        @Expect(#"[{"a" : [1, "x"]}]"#, written([raw]))
        @Expect("null", RawJson.NULL.toString())
    }

    @TestCase
    func trailingBytesAfterTheValueAreRefused() {
        // act & assert
        @AssertThrows[FjException](read<Int64>("1 2"))
    }
}
