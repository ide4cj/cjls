package fjson

import std.unittest.*
import std.unittest.testmacro.*

private func read(text: String): JsonValue {
    fromJsonBytes<JsonValue>(text.toArray())
}

@Test
class JsonValueTest {
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

    @TestCase
    func aPrettyValueHasAnItemOrAMemberPerLineAndAnEmptyContainerOnOne() {
        // act
        let text = read(#"{"a":[1,"x"],"b":{},"c":[],"d":{"e":null}}"#).toPrettyString()

        // assert
        @Expect(text, "{\n  \"a\": [\n    1,\n    \"x\"\n  ],\n  \"b\": {},\n  \"c\": [],\n  \"d\": {\n    \"e\": null\n  }\n}")
    }
}
