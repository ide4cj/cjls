package stdxx

import std.collection.HashMap
import std.unittest.*
import std.unittest.testmacro.*
import fjson.*

@Test
@Configure[randomSeed: 42]
class IntegerOrStringTest {
    @TestCase[value in random()]
    func anIntegerRoundTrips(value: Int32) {
        // act
        let restored = fromJsonBytes<IntegerOrString>(toJsonBytes(Integer(value)))

        // assert
        @Expect(Integer(value), restored)
    }

    @TestCase[value in random()]
    func aStringRoundTrips(value: String) {
        // act
        let restored = fromJsonBytes<IntegerOrString>(toJsonBytes(IntegerOrString.String(value)))

        // assert
        @Expect(IntegerOrString.String(value), restored)
    }

    @TestCase[json in ["true", "null", "2147483648", "1.5"]]
    func anythingElseIsRefused(json: String) {
        // act & assert
        @AssertThrows[FjException](fromJsonBytes<IntegerOrString>(json.toArray()))
    }

    @TestCase
    func toStringRendersTheBareValue() {
        // act & assert
        @Expect("42", Integer(42).toString())
        @Expect("hello", IntegerOrString.String("hello").toString())
    }

    @TestCase
    func askingForTheOtherVariantThrows() {
        // act
        let onString = @AssertThrows[UnexpectedVariantException](IntegerOrString.String("1").getIntegerOrThrow())
        let onInteger = @AssertThrows[UnexpectedVariantException](Integer(1).getStringOrThrow())

        // assert
        @Expect("expected `Integer` variant, got `String`", onString.message)
        @Expect("expected `String` variant, got `Integer`", onInteger.message)
    }

    @TestCase
    func anIntegerAndItsTextAreDifferentKeys() {
        // arrange - `toString` maps `42` and `"42"` onto the same text, so hashing must not go through it
        let map = HashMap<IntegerOrString, String>()

        // act
        map[Integer(42)] = "integer"
        map[IntegerOrString.String("42")] = "string"

        // assert
        @Expect(2, map.size)
        @Expect("integer", map[Integer(42)])
        @Expect("string", map[IntegerOrString.String("42")])
    }
}
