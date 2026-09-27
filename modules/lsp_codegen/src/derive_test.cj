package lsp_codegen

import std.unittest.*
import std.unittest.testmacro.*
import stdxx.IntegerOrString

@Test
class EmitDerivesTest {
    @TestCase
    func aTaggedStructNamesItsTagAndValue() {
        // arrange
        let options = SerdeTypeOptions(tag: SerdeTag(field: "kind", value: "create"))
        let expected = """
@DeriveExt[ToJson, FromJson]
@Serde[tag: "kind", rename: "create"]
"""

        // act
        let actual = emittedBy {emitter => emitter.emitDerives([DeriveIr.Json(options)])}

        // assert
        @PowerAssert(expected, actual)
    }

    @TestCase
    func noOptionsLeaveNoMarker() {
        // arrange
        let derives = [DeriveIr.Json(SerdeTypeOptions()), DeriveIr.Equatable, DeriveIr.Hashable]
        let expected = """
@DeriveExt[ToJson, FromJson]
@Derive[Equatable, Hashable]
"""

        // act
        let actual = emittedBy {emitter => emitter.emitDerives(derives)}

        // assert
        @PowerAssert(expected, actual)
    }

    @TestCase
    func aMemberMarkerListsItsValueAndOther() {
        // act
        let actual = serdeMarkerOf(SerdeMemberOptions(value: IntegerOrString.Integer(1), other: true))

        // assert
        @Expect("@Serde[value: 1, other]", actual.toString())
    }

    @TestCase
    func aStringValueIsTheVariantsRename() {
        // act
        let actual = serdeMarkerOf(SerdeMemberOptions(value: IntegerOrString.String("plaintext")))

        // assert
        @Expect("@Serde[rename: \"plaintext\"]", actual.toString())
    }

    @TestCase
    func aUnionIsUntagged() {
        // arrange
        let expected = """
@DeriveExt[ToJson, FromJson]
@Serde[untagged]
"""

        // act
        let actual = emittedBy {emitter => emitter.emitDerives([DeriveIr.Json(SerdeTypeOptions(untagged: true))])}

        // assert
        @PowerAssert(expected, actual)
    }
}
