package stdxx.serialization

import std.unittest.*
import std.unittest.testmacro.*
import fjson.*

private func read(text: String): AnyValue {
    fromJsonBytes<AnyValue>(text.toArray())
}

@Test
class AnyValueTest {
    @TestCase[text in ["null", "[1,null,2.5,true]", #"{"k":"v","a":{"b":[]}}"#]]
    func whateverIsReadIsWrittenBackAsIs(text: String) {
        // act & assert
        @Expect(String.fromUtf8(toJsonBytes(read(text))), text)
    }

    @TestCase
    func anObjectKeepsItsKeysInTheirOrder() {
        // act
        let value = read(#"{"z": 1, "a": {"n": "x"}}"#)

        // assert
        @Expect(value.asObject().map {member => member[0]}, ["z", "a"])
        @Expect(value["a"]["n"].asString(), "x")
        @Expect(value.get("b").isNone())
        @AssertThrows[IllegalArgumentException](value["b"])
    }

    @TestCase
    func anIntegerPastInt64ReadsAsTheNearestFloat() {
        // act
        let value = read("[9223372036854775807, 100000000000000000000]")

        // assert
        @Expect(value[0].asInteger(), Int64.Max)
        @Expect(value[1].asFloat(), 1e20)
    }

    @TestCase
    func aValueOfAnotherKindIsNoneOfTheOthers() {
        // act & assert
        @AssertThrows[IllegalArgumentException](read("1").asString())
        @AssertThrows[IllegalArgumentException](read("1.0").asInteger())
        @Expect(read("null").isNull())
        @Expect(read(#"{"a":1,"b":2}"#) != read(#"{"b":2,"a":1}"#))
    }
}
