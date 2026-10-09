package stdxx

import std.unittest.*
import std.unittest.testmacro.*
import fjson.*
import stdxx.deriving.*

// The fixtures are `deriving_ext_test.cj`'s: every one of them derives `ToJson` and `FromJson` too.

@DeriveExt[ToJson, FromJson]
@Serde[untagged]
enum DerivedJsonLabel {
    | Text(String)
    | Offsets(UInt32, UInt32)
    | Signed(Int64, Int64)
}

private func json<T>(value: T): String where T <: ToJson {
    String.fromUtf8(toJsonBytes(value))
}

private func read<T>(text: String): T where T <: FromJson<T> {
    fromJsonBytes<T>(text.toArray())
}

@Test
class DeriveJsonStructTest {
    @TestCase
    func requiredFieldsAreWrittenInDeclarationOrder() {
        // act & assert
        @Expect(#"{"line":3,"character":14}"#, json(DerivedPosition(line: 3, character: 14)))
    }

    @TestCase
    func keysAreReadInAnyOrderAndUnknownOnesSkipped() {
        // act
        let position = read<DerivedPosition>(#" { "extra": {"a": [1, "x"]}, "character" : 14, "line": 3 } "#)

        // assert
        @Expect(3, position.line)
        @Expect(14, position.character)
    }

    @TestCase
    func aMissingRequiredFieldThrowsNamingIt() {
        // act
        let e = @AssertThrows[FjException](read<DerivedPosition>(#"{"line": 3}"#))

        // assert
        @Expect("`DerivedPosition` misses the field \"character\"", e.message)
    }

    @TestCase
    func aValueOfTheWrongKindThrows() {
        // act & assert
        @AssertThrows[FjException](read<DerivedPosition>(#"{"line": "3", "character": 1}"#))
        @AssertThrows[FjException](read<DerivedPosition>("[]"))
    }

    @TestCase
    func positionalFieldsRoundTrip() {
        // act
        let restored = read<DerivedPositional>(json(DerivedPositional(1, 2)))

        // assert
        @Expect(1, restored.x)
        @Expect(2, restored.y)
    }

    @TestCase
    func aGenericFieldRoundTripsThroughItsOwnCodec() {
        // act & assert
        @Expect(#"{"value":"boxed"}"#, json(DerivedBox(value: "boxed")))
        @Expect("boxed", read<DerivedBox<String>>(#"{"value":"boxed"}"#).value)
    }

    @TestCase
    func derivingLeavesRoomForDerive() {
        // arrange
        let described = DerivedAndDescribed(name: "x")

        // act & assert
        @Expect(#"{"name":"x"}"#, json(described))
        @Expect("DerivedAndDescribed(name: x)", described.toString())
    }

    @TestCase
    func renameAndBackquotesDecideTheWireName() {
        // arrange
        let names = DerivedNames(document: "file:///a.cj", `type`: "cangjie")

        // act
        let written = json(names)
        let restored = read<DerivedNames>(written)

        // assert
        @Expect(#"{"textDocument":"file:///a.cj","type":"cangjie"}"#, written)
        @Expect("file:///a.cj", restored.document)
        @Expect("cangjie", restored.`type`)
    }
}

@Test
class DeriveJsonNullabilityTest {
    @TestCase
    func withoutSkipNoneEveryFieldIsWritten() {
        // act & assert
        @Expect(#"{"required":"r","nullable":null,"optional":"o","optionalNullable":null}"#,
            json(DerivedShapes(required: "r", nullable: Nullable<String>.Null, optional: "o")))
    }

    @TestCase
    func anExplicitNullReadsAsNoneRatherThanThrowing() {
        // act
        let restored = read<DerivedShapes>(#"{"required": "r", "nullable": null, "optional": null}"#)

        // assert
        @Expect(restored.optional.isNone())
        @Expect(restored.nullable.isNull())
    }

    @TestCase
    func aRequiredNullableHasToBeThere() {
        // act & assert
        @AssertThrows[FjException](read<DerivedShapes>(#"{"required": "r"}"#))
    }

    @TestCase
    func anOptionalNullableTellsAbsentFromNull() {
        // act
        let absent = read<DerivedShapes>(#"{"required": "r", "nullable": null}"#)
        let null = read<DerivedShapes>(#"{"required": "r", "nullable": null, "optionalNullable": null}"#)
        let value = read<DerivedShapes>(#"{"required": "r", "nullable": null, "optionalNullable": "v"}"#)

        // assert
        @Expect(absent.optionalNullable.isNone())
        @Expect(null.optionalNullable.getOrThrow().isNull())
        @Expect("v", value.optionalNullable.getOrThrow().getOrThrow())
    }
}

@Test
class DeriveJsonSkipNoneTest {
    @TestCase
    func onTheTypeItOmitsEveryNoneFieldAndReadsThemBack() {
        // act
        let written = json(DerivedSkipped(required: "r"))
        let restored = read<DerivedSkipped>(written)

        // assert
        @Expect(#"{"required":"r"}"#, written)
        @Expect(restored.optional.isNone())
        @Expect(restored.optionalNullable.isNone())
    }

    @TestCase
    func onTheTypeItStillWritesAnExplicitNull() {
        // act & assert
        @Expect(#"{"required":"r","optionalNullable":null}"#,
            json(DerivedSkipped(required: "r", optionalNullable: Nullable<String>.Null)))
    }

    @TestCase
    func onASingleFieldItLeavesTheRestAlone() {
        // act & assert
        @Expect(#"{"kept":null}"#, json(DerivedPartlySkipped()))
    }

    @TestCase
    func oneMarkerCarriesBothOptions() {
        // act & assert
        @Expect("{}", json(DerivedRenamedAndSkipped()))
        @Expect(Some("file:///a.cj"), read<DerivedRenamedAndSkipped>(#"{"textDocument":"file:///a.cj"}"#).document)
    }
}

@Test
class DeriveJsonScalarEnumTest {
    @TestCase
    func aRenamedVariantTravelsAsItsNameAndAPlainOneAsItsIdentifier() {
        // act & assert
        @Expect(#""URI""#, json(DerivedBaseTypes.Uri))
        @Expect(#""Boolean""#, json(DerivedBaseTypes.Boolean))
        @Expect(DerivedBaseTypes.Numeric, read<DerivedBaseTypes>(#""integer""#))
    }

    @TestCase
    func anIntegerEnumTravelsAsANumberNegativeOnesIncluded() {
        // act & assert
        @Expect("2", json(DerivedSeverity.Warn))
        @Expect(DerivedSeverity.Fatal, read<DerivedSeverity>("1"))
        @Expect("-32700", json(DerivedErrorCode.ParseError))
        @Expect(DerivedErrorCode.MethodNotFound, read<DerivedErrorCode>("-32601"))
    }

    @TestCase
    func anUnknownValueThrowsNamingIt() {
        // act
        let e = @AssertThrows[FjException](read<DerivedBaseTypes>(#""nope""#))

        // assert
        @Expect("unexpected `DerivedBaseTypes` value: nope", e.message)
    }

    @TestCase
    func anUnknownValueIsKeptByOtherAndWrittenBack() {
        // act
        let symbol = read<DerivedSymbolKind>("27")
        let markup = read<DerivedMarkupKind>(#""asciidoc""#)

        // assert
        @Expect(DerivedSymbolKind.Unknown(27), symbol)
        @Expect("27", json(symbol))
        @Expect(DerivedMarkupKind.Unknown("asciidoc"), markup)
        @Expect(#""asciidoc""#, json(markup))
    }

    @TestCase
    func anUnknownValueOutsideThePayloadTypeThrows() {
        // act & assert
        @AssertThrows[FjException](read<DerivedSymbolKind>("-1"))
        @AssertThrows[FjException](read<DerivedSymbolKind>(#""1""#))
        @AssertThrows[FjException](read<DerivedMarkupKind>("1"))
    }
}

@Test
class DeriveJsonUntaggedEnumTest {
    @TestCase
    func theVariantIsWhicheverOneTheValueReadsAs() {
        // act & assert
        @Expect(DerivedScalarOrList.Single("one"), read<DerivedScalarOrList>(#""one""#))
        @Expect(DerivedScalarOrList.Many(["a", "b"]), read<DerivedScalarOrList>(#"["a", "b"]"#))
    }

    @TestCase
    func aVariantIsWrittenAsItsPayloadAlone() {
        // act & assert
        @Expect(#""one""#, json(DerivedScalarOrList.Single("one")))
        @Expect(#"["a"]"#, json(DerivedScalarOrList.Many(["a"])))
    }

    @TestCase
    func aVariantThatOverflowsGivesWayToTheNextOne() {
        // act & assert
        @Expect(DerivedNarrowOrWide.Wide(5_000_000_000), read<DerivedNarrowOrWide>("5000000000"))
        @Expect(DerivedNarrowOrWide.Narrow(7), read<DerivedNarrowOrWide>("7"))
    }

    @TestCase
    func aVariantFailingMidwayLeavesTheNextOneAtTheValuesStartInsideAnArray() {
        // act
        let items = read<Array<DerivedNarrowOrWide>>("[5000000000, 7, 5000000001]")

        // assert
        @Expect([DerivedNarrowOrWide.Wide(5_000_000_000), DerivedNarrowOrWide.Narrow(7),
            DerivedNarrowOrWide.Wide(5_000_000_001)], items)
    }

    @TestCase
    func aValueMatchingNoVariantThrows() {
        // act
        let e = @AssertThrows[FjException](read<DerivedScalarOrList>(" 1"))

        // assert
        @Expect("no `DerivedScalarOrList` variant matched the value at byte 1", e.message)
    }

    @TestCase
    func theReaderGoesOnPastTheUnion() {
        // act
        let r = FjReader(#"[["a"], "b"]"#.toArray())
        r.beginArray()
        r.nextItem()
        let first = DerivedScalarOrList.fromJson(r)
        r.nextItem()
        let second = DerivedScalarOrList.fromJson(r)

        // assert
        @Expect(!r.nextItem())
        @Expect(DerivedScalarOrList.Many(["a"]), first)
        @Expect(DerivedScalarOrList.Single("b"), second)
    }

    @TestCase
    func aGenericUntaggedEnumRoundTrips() {
        // act & assert
        @Expect(DerivedOneOrMany.One("x"), read<DerivedOneOrMany<String>>(json(DerivedOneOrMany.One("x"))))
        @Expect(DerivedOneOrMany.Several(["x", "y"]),
            read<DerivedOneOrMany<String>>(json(DerivedOneOrMany<String>.Several(["x", "y"]))))
    }

    @TestCase
    func aTupleIsAnArrayOfExactlyItsPayloads() {
        // act & assert
        @Expect("[3,7]", json(DerivedJsonLabel.Offsets(3, 7)))
        @Expect(match (read<DerivedJsonLabel>("[3, 7]")) {
            case Offsets(start, end) => start == 3 && end == 7
            case _ => false
        })
        // `-1` is no `UInt32`
        @Expect(match (read<DerivedJsonLabel>("[-1, 2]")) {
            case Signed(start, end) => start == -1 && end == 2
            case _ => false
        })
        @AssertThrows[FjException](read<DerivedJsonLabel>("[1, 2, 3]"))
        @AssertThrows[FjException](read<DerivedJsonLabel>("[1]"))
    }
}

@Test
class DeriveJsonTaggedEnumTest {
    @TestCase
    func thePayloadTravelsBesideTheTag() {
        // act & assert
        @Expect(#"{"kind":"rect","width":3,"height":4}"#, json(DerivedShape.Rect(3, 4)))
        @Expect(#"{"kind":"point"}"#, json(DerivedShape.Point))
    }

    @TestCase
    func theTagIsFoundWhereverItIs() {
        // act & assert
        @Expect(DerivedShape.Rect(3, 4), read<DerivedShape>(#"{"height": 4, "width": 3, "kind": "rect"}"#))
    }

    @TestCase[shape in [DerivedShape.Circle(5), DerivedShape.Rect(3, 4), DerivedShape.Point]]
    func everyShapeRoundTrips(shape: DerivedShape) {
        // act & assert
        @Expect(shape, read<DerivedShape>(json(shape)))
    }

    @TestCase
    func anOptionalPayloadFollowsTheSameRulesAsAField() {
        // act
        let written = json(DerivedTaggedPayload.Note("hello", None))

        // assert
        @Expect(#"{"kind":"note","text":"hello"}"#, written)
        @Expect(DerivedTaggedPayload.Note("hello", None), read<DerivedTaggedPayload>(written))
    }

    @TestCase
    func anUnknownOrAbsentTagThrows() {
        // act
        let unknown = @AssertThrows[FjException](read<DerivedShape>(#"{"kind": "hexagon"}"#))
        let absent = @AssertThrows[FjException](read<DerivedShape>(#"{"radius": 1}"#))

        // assert
        @Expect("unexpected `DerivedShape` kind: hexagon", unknown.message)
        @Expect("`DerivedShape` misses the field \"kind\"", absent.message)
    }
}

@Test
class DeriveJsonTransparentTest {
    @TestCase
    func aTransparentStructTravelsAsItsOnlyField() {
        // act & assert
        @Expect("-32700", json(DerivedOpenCode.PARSE_ERROR))
        @Expect(#""refactor""#, json(DerivedOpenKind(value: "refactor")))
        @Expect(DerivedOpenCode(-1), read<DerivedOpenCode>("-1"))
        @Expect("x", read<DerivedOpenKind>(#""x""#).value)
    }

    @TestCase
    func aValueTheFieldCannotHoldThrows() {
        // act & assert
        @AssertThrows[FjException](read<DerivedOpenCode>(#""-1""#))
        @AssertThrows[FjException](read<DerivedOpenUnsigned>("-1"))
    }
}

@Test
class DeriveJsonTaggedStructTest {
    @TestCase
    func theTagIsWrittenAheadOfTheFields() {
        // act & assert
        @Expect(#"{"kind":"create","uri":"file:///a"}"#, json(DerivedCreateFile(uri: "file:///a")))
    }

    @TestCase
    func aStructNotRenamedIsTaggedWithItsIdentifier() {
        // act & assert
        @Expect(#"{"kind":"DerivedRenameFile","uri":"file:///a"}"#, json(DerivedRenameFile(uri: "file:///a")))
    }

    @TestCase
    func aTaggedStructRoundTrips() {
        // act
        let restored = read<DerivedDeleteFile>(json(DerivedDeleteFile(uri: "file:///a", recursive: true)))

        // assert
        @Expect("file:///a", restored.uri)
        @Expect(Some(true), restored.recursive)
    }

    @TestCase
    func aForeignOrAbsentTagThrows() {
        // act
        let onOtherTag = @AssertThrows[FjException](read<DerivedCreateFile>(#"{"kind": "delete", "uri": "file:///a"}"#))
        let onAbsent = @AssertThrows[FjException](read<DerivedCreateFile>(#"{"uri": "file:///a"}"#))

        // assert
        @Expect("unexpected `DerivedCreateFile` kind: delete", onOtherTag.message)
        @Expect("`DerivedCreateFile` misses the field \"kind\"", onAbsent.message)
    }

    @TestCase
    func theTagPicksTheVariantOfAnUntaggedUnion() {
        // act - both structs read `{"uri"}` alike; only the tag keeps the first from taking it
        let restored = read<DerivedFileOperation>(#"{"uri": "file:///a", "kind": "delete"}"#)

        // assert
        @Expect(match (restored) {
            case Delete(op) => op.uri == "file:///a"
            case _ => false
        })
    }
}
