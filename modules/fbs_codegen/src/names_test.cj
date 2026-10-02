package fbs_codegen

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * The names of schema `text` under a config of the given `open`, `rename` and `wrap`.
 */
func namesOf(
    text: String,
    open!: Array<String> = [],
    rename!: Array<(String, String)> = [],
    wrap!: Array<(String, String)> = []
): Names {
    let config = Config(
        schema: "s.fbs",
        output: "out.cj",
        packageName: "p",
        open: open,
        rename: HashMap<String, String>(rename),
        wrap: HashMap<String, String>(wrap)
    )
    Names(parseSchema(text), config)
}

@Test
class NamesTest {
    @TestCase
    func fieldsAreCamelCasedAndKeywordsWrittenRaw() {
        // arrange
        let sut = namesOf("")

        // act & assert
        @Expect(sut.fieldName("all_file_imports"), "allFileImports")
        @Expect(sut.fieldName("_leading"), "_leading")
        @Expect(sut.fieldName("type"), "`type`")
        @Expect(sut.raw("Int8"), "`Int8`")
        @Expect(sut.raw("Decl"), "Decl")
    }

    @TestCase
    func theConfigRenamesDeclarationsAndEnumMembers() {
        // arrange
        let sut = namesOf("table Generic {}\nenum E : byte { Generic, Other }",
            rename: [("Generic", "Generics"), ("E.Other", "Else")])

        // act & assert
        @Expect(sut.typeName("Generic"), "Generics")
        @Expect(sut.typeName("E"), "E")
        @Expect(sut.memberName("E", "Generic"), "Generic")
        @Expect(sut.memberName("E", "Other"), "Else")
        sut.check()
    }

    @TestCase
    func anEnumMemberNamedLikeATypeIsRefused() {
        // arrange
        let sut = namesOf("table Generic {}\nenum E : byte { Generic }")

        // act & assert
        @AssertThrows[ConfigException](sut.check())
    }

    @TestCase
    func aUnionConstructorNamedLikeATypeIsRefused() {
        // arrange
        let sut = namesOf("table T {}\ntable AsT {}\nunion U { T }")

        // act & assert
        @AssertThrows[ConfigException](sut.check())
    }

    @TestCase
    func aDeclarationNamedLikeTheRuntimeIsRefused() {
        // arrange
        let sut = namesOf("table FbVector {}")

        // act & assert
        @AssertThrows[ConfigException](sut.check())
    }

    @TestCase
    func twoDeclarationsRenamedToOneNameAreRefused() {
        // arrange
        let sut = namesOf("table A {}\ntable B {}", rename: [("A", "B")])

        // act & assert
        @AssertThrows[ConfigException](sut.check())
    }

    @TestCase
    func whatTheConfigNamesMustBeInTheSchema() {
        // arrange
        let schema = "enum E : byte { A }\ntable T { f: int; }"

        // act & assert
        @AssertThrows[ConfigException](namesOf(schema, open: ["T"]).check())
        @AssertThrows[ConfigException](namesOf(schema, open: ["Missing"]).check())
        @AssertThrows[ConfigException](namesOf(schema, rename: [("E.B", "C")]).check())
        @AssertThrows[ConfigException](namesOf(schema, rename: [("Missing", "C")]).check())
        @AssertThrows[ConfigException](namesOf(schema, wrap: [("T.g", "W")]).check())
        @AssertThrows[ConfigException](namesOf(schema, wrap: [("T", "W")]).check())
        namesOf(schema, open: ["E"], rename: [("E.A", "B")], wrap: [("T.f", "W")]).check()
    }
}

@Test
class StructLayoutTest {
    @TestCase
    func eachFieldIsAlignedAndTheStructPaddedToItsLargestAlignment() {
        // arrange
        let names = namesOf("struct S { a: ubyte; b: uint; c: ushort; d: ubyte; }")

        // act
        let sut = structLayout(names, names.decl("S"))

        // assert
        @Expect(sut.offsets, [0, 4, 8, 10])
        @Expect(sut.size, 12)
        @Expect(sut.alignment, 4)
    }

    @TestCase
    func aNestedStructIsAlignedAsItsLargestField() {
        // arrange
        let names = namesOf("struct In { x: ubyte; y: long; }\nenum E : short { A }\nstruct S { a: ubyte; e: E; b: In; }")

        // act
        let sut = structLayout(names, names.decl("S"))

        // assert
        @Expect(sut.offsets, [0, 2, 8])
        @Expect(sut.size, 24)
        @Expect(sut.alignment, 8)
    }

    @TestCase
    func aStructOfAnythingButScalarsEnumsAndStructsIsRefused() {
        // arrange
        let names = namesOf("table T {}\nstruct A { s: string; }\nstruct B { t: T; }")

        // act & assert
        @AssertThrows[ConfigException](structLayout(names, names.decl("A")))
        @AssertThrows[ConfigException](structLayout(names, names.decl("B")))
    }
}

@Test
class FieldIdsTest {
    @TestCase
    func aUnionOrAVectorOfUnionsTakesTwoIds() {
        // arrange
        let names = namesOf("table T {}\nunion U { T }\ntable X { a: int; u: U; b: string; us: [U]; c: [int]; }")

        // act
        let sut = fieldIds(names, names.decl("X"))

        // assert
        @Expect(sut, [0, 1, 3, 4, 6])
    }

    @TestCase
    func aDeprecatedFieldKeepsItsId() {
        // arrange
        let names = namesOf("table X { a: int; old: int (deprecated); b: int; }")

        // act
        let sut = fieldIds(names, names.decl("X"))

        // assert
        @Expect(sut, [0, 1, 2])
    }
}
