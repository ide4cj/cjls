package stdxx

import std.unittest.*
import std.unittest.testmacro.*
import fjson.*
import ftoml.*
import stdxx.deriving.*

@DeriveExt[ToJson, FromJson, ToToml, FromToml]
@Serde[denyUnknownFields]
struct StrictDefaults {
    StrictDefaults(
        @Serde[rename: "line_width", default]
        let lineWidth!: Int64 = 100,
        @Serde[default: "defaultLabel"]
        let label!: String,
        @Serde[default]
        let optional!: ?Int64 = Some(7)
    ) {}
}

private func defaultLabel(): String {
    "fallback"
}

@DeriveExt[FromJson]
struct NullableDefaults {
    NullableDefaults(
        @Serde[default]
        let required!: Nullable<Int64> = Nullable.Value(9),
        @Serde[default]
        let optional!: ?Nullable<Int64> = Some(Nullable.Value(8))
    ) {}
}

@DeriveExt[FromJson, FromToml]
struct LazyDefault {
    LazyDefault(
        @Serde[default: "unavailableDefault"]
        let value!: Int64
    ) {}
}

private func unavailableDefault(): Int64 {
    throw IllegalStateException("the default must not run for a present field")
}

@DeriveExt[FromJson, FromToml]
struct RequiredDefault {
    RequiredDefault(let value!: Int64 = 42) {}
}

@DeriveExt[FromJson, FromToml]
@Serde[tag: "kind", rename: "record", denyUnknownFields]
struct StrictTaggedRecord {
    StrictTaggedRecord(
        @Serde[rename: "wire_value", default]
        let value!: Int64 = 3
    ) {}
}

@DeriveExt[FromJson, FromToml]
@Serde[tag: "kind", denyUnknownFields]
enum StrictTaggedChoice {
    | @Serde[rename: "empty"]
    EmptyChoice
    | @Serde[rename: "value", payload: ["wire_value"]]
    ValueChoice(Int64)
}

@DeriveExt[FromJson, FromToml]
struct NestedStrictDefaults {
    NestedStrictDefaults(let inner!: StrictDefaults) {}
}

@Test
class DeriveDefaultsTest {
    @TestCase
    func missingFieldsUseExplicitDefaultsInBothFormats(): Unit {
        // act
        let json = fromJsonBytes<StrictDefaults>("{}".toArray())
        let toml = fromTomlString<StrictDefaults>("")

        // assert
        @Expect(json.lineWidth, 100)
        @Expect(json.label, "fallback")
        @Expect(json.optional, Some(7))
        @Expect(toml.lineWidth, 100)
        @Expect(toml.label, "fallback")
        @Expect(toml.optional, Some(7))
    }

    @TestCase
    func presentFieldsOverrideDefaultsAndExplicitNullStaysNone(): Unit {
        // act
        let json =
            fromJsonBytes<StrictDefaults>(
                #"{"line_width":80,"label":"given","optional":null}"#.toArray()
            )
        let toml = fromTomlString<StrictDefaults>("line_width = 80\nlabel = 'given'\noptional = 9")

        // assert
        @Expect(json.lineWidth, 80)
        @Expect(json.label, "given")
        @Expect(json.optional.isNone())
        @Expect(toml.lineWidth, 80)
        @Expect(toml.label, "given")
        @Expect(toml.optional, Some(9))
    }

    @TestCase
    func explicitNullRetainsBothNullableShapes(): Unit {
        // act
        let absent = fromJsonBytes<NullableDefaults>("{}".toArray())
        let present =
            fromJsonBytes<NullableDefaults>(#"{"required":null,"optional":null}"#.toArray())

        // assert
        @Expect(match (absent.required) { case Nullable.Value(value) => value == 9; case _ => false })
        @Expect(match (absent.optional) { case Some(Nullable.Value(value)) => value == 8; case _ => false })
        @Expect(match (present.required) { case Nullable.Null => true; case _ => false })
        @Expect(match (present.optional) { case Some(Nullable.Null) => true; case _ => false })
    }

    @TestCase
    func defaultsAreLazyAndDoNotReplaceInvalidPresentValues(): Unit {
        // act
        let json = fromJsonBytes<LazyDefault>(#"{"value":2}"#.toArray())
        let toml = fromTomlString<LazyDefault>("value = 2")

        // assert
        @Expect(json.value, 2)
        @Expect(toml.value, 2)
        @AssertThrows[FjException](fromJsonBytes<StrictDefaults>(#"{"line_width":"80"}"#.toArray()))
        @AssertThrows[FtException](fromTomlString<StrictDefaults>("line_width = '80'"))
        @AssertThrows[FjException](fromJsonBytes<StrictDefaults>(#"{"line_width":null}"#.toArray()))
    }

    @TestCase
    func constructorDefaultsRemainRequiredWithoutTheMarker(): Unit {
        // act / assert
        @AssertThrows[FjException](fromJsonBytes<RequiredDefault>("{}".toArray()))
        @AssertThrows[FtException](fromTomlString<RequiredDefault>(""))
    }

    @TestCase
    func unknownKeysUseWireNamesAndKeepTomlLocations(): Unit {
        // act
        let jsonError =
            @AssertThrows[FjException](
                fromJsonBytes<StrictDefaults>(#"{"lineWidth":80}"#.toArray()))
        let tomlError =
            @AssertThrows[FtException](
                fromTomlString<StrictDefaults>("lineWidth = 80"))

        // assert
        @Expect(jsonError.message.contains("lineWidth"))
        @Expect(tomlError.message.contains("lineWidth"))
        @Expect(tomlError.line, 1)
        @Expect(tomlError.column > 0)
    }

    @TestCase
    func taggedStructsAcceptTheirTagAndRejectExtraFields(): Unit {
        // act
        let json = fromJsonBytes<StrictTaggedRecord>(#"{"kind":"record"}"#.toArray())
        let toml = fromTomlString<StrictTaggedRecord>("kind = 'record'\nwire_value = 8")

        // assert
        @Expect(json.value, 3)
        @Expect(toml.value, 8)
        @AssertThrows[FjException](fromJsonBytes<StrictTaggedRecord>(
            #"{"kind":"record","extra":1}"#.toArray()))
        @AssertThrows[FtException](fromTomlString<StrictTaggedRecord>("kind = 'record'\nextra = 1"))
    }

    @TestCase
    func taggedEnumsValidateEmptyAndPayloadVariants(): Unit {
        // act
        let json = fromJsonBytes<StrictTaggedChoice>(#"{"kind":"empty"}"#.toArray())
        let toml = fromTomlString<StrictTaggedChoice>("wire_value = 5\nkind = 'value'")

        // assert
        @Expect(match (json) { case EmptyChoice => true; case _ => false })
        @Expect(match (toml) { case ValueChoice(value) => value == 5; case _ => false })
        @AssertThrows[FjException](fromJsonBytes<StrictTaggedChoice>(
            #"{"kind":"empty","extra":1}"#.toArray()))
        @AssertThrows[FtException](fromTomlString<StrictTaggedChoice>("kind = 'empty'\nextra = 1"))
        @AssertThrows[FjException](fromJsonBytes<StrictTaggedChoice>(
            #"{"kind":"value","wire_value":5,"extra":1}"#.toArray()))
        @AssertThrows[FtException](fromTomlString<StrictTaggedChoice>(
            "kind = 'value'\nwire_value = 5\nextra = 1"))
    }

    @TestCase
    func nestedStrictObjectsKeepTheirPolicy(): Unit {
        // act
        let json = fromJsonBytes<NestedStrictDefaults>(#"{"inner":{}}"#.toArray())
        let toml = fromTomlString<NestedStrictDefaults>("[inner]")

        // assert
        @Expect(json.inner.lineWidth, 100)
        @Expect(toml.inner.lineWidth, 100)
        @AssertThrows[FjException](fromJsonBytes<NestedStrictDefaults>(
            #"{"inner":{"extra":1}}"#.toArray()))
        @AssertThrows[FtException](fromTomlString<NestedStrictDefaults>("[inner]\nextra = 1"))
    }

    @TestCase
    func defaultsAndStrictnessDoNotChangeSerialization(): Unit {
        // arrange
        let value = StrictDefaults(label: "given")

        // act
        let json = String.fromUtf8(toJsonBytes(value))
        let toml = toTomlString(value)

        // assert
        @Expect(json, #"{"line_width":100,"label":"given","optional":7}"#)
        @Expect(toml, "line_width = 100\nlabel = \"given\"\noptional = 7\n")
    }
}
