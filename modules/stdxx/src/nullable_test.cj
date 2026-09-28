package stdxx

import std.unittest.*
import std.unittest.testmacro.*
import fjson.*

@Test
@Configure[randomSeed: 42]
class NullableTest {
    @TestCase[value in random()]
    func aValueTravelsAsItself(value: String) {
        // act
        let written = toJsonBytes(Nullable.Value(value))
        let restored = fromJsonBytes<Nullable<String>>(written)

        // assert
        @Expect(written, toJsonBytes(value))
        @Expect(value, restored.getOrThrow())
    }

    @TestCase
    func nullTravelsAsNull() {
        // act
        let written = String.fromUtf8(toJsonBytes(Nullable<String>.Null))
        let restored = fromJsonBytes<Nullable<String>>("null".toArray())

        // assert
        @Expect("null", written)
        @Expect(restored.isNull())
    }

    @TestCase
    func askingNullForAValueThrows() {
        // act
        let e = @AssertThrows[NullValueException](Nullable<String>.Null.getOrThrow())

        // assert
        @Expect("value is null", e.message)
    }
}
