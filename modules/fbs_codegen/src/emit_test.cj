package fbs_codegen

import std.unittest.*
import std.unittest.testmacro.*

/**
 * The views `emitViews` makes of `names`, whitespace collapsed so that a test can look for a line in them.
 */
func viewsOf(names: Names): String {
    let lines = emitViews(names, "// header", "p").split("\n").map {l => l.trimAscii()}
    String.join(lines, delimiter: "\n")
}

@Test
class EmitTest {
    @TestCase
    func theFileStartsWithTheHeaderAndThePackage() {
        // act
        let sut = viewsOf(namesOf("table T {}"))

        // assert
        @Expect(sut.startsWith("// header\n\npackage p\n"))
    }

    @TestCase
    func anOpenEnumKeepsAValueItDoesNotKnow() {
        // act
        let sut = viewsOf(namesOf("enum E : ushort { A, B = 3 }", open: ["E"]))

        // assert
        @Expect(sut.contains("| Unknown(UInt16)"))
        @Expect(sut.contains("case 3 => E.B"))
        @Expect(sut.contains("case _ => E.Unknown(value)"))
        @Expect(sut.contains("case E.Unknown(v) => v"))
    }

    @TestCase
    func aClosedEnumThrowsOnAValueItDoesNotKnow() {
        // act
        let sut = viewsOf(namesOf("enum E : ushort { A }"))

        // assert
        @Expect(!sut.contains("Unknown"))
        @Expect(sut.contains("case _ => throw broken(\"E has no value \${value}\")"))
    }

    @TestCase
    func anEnumsMethodsAreInAnExtendWhereAMemberDoesNotHideAType() {
        // act
        let sut = viewsOf(namesOf("enum E : byte { String }"))

        // assert
        @Expect(sut.contains("extend E <: Hashable & Equatable<E> & ToString {"))
        @Expect(sut.contains("case E.String => \"String\""))
    }

    @TestCase
    func aKeywordMemberIsRawInCodeAndPlainInItsName() {
        // act
        let sut = viewsOf(namesOf("enum E : byte { Int8 }"))

        // assert
        @Expect(sut.contains("| `Int8`"))
        @Expect(sut.contains("case E.`Int8` => \"Int8\""))
    }

    @TestCase
    func everyUnionHasUnknownAndReadsItsMembersByTag() {
        // act
        let sut = viewsOf(namesOf("table T {}\nstruct S { x: int; }\nunion U { T, S, StringValue: string }"))

        // assert
        @Expect(sut.contains("| Unknown(UInt8)"))
        @Expect(sut.contains("case 1 => U.AsT(T(FbTable.at(buf, pos)))"))
        @Expect(sut.contains("case 2 => U.AsS(S(buf, follow(buf, pos)))"))
        @Expect(sut.contains("case 3 => U.AsStringValue(readString(buf, pos))"))
        @Expect(sut.contains("case _ => U.Unknown(tag)"))
    }

    @TestCase
    func aStructReadsItsFieldsAtTheirOffsets() {
        // act
        let sut = viewsOf(namesOf("enum E : ubyte { A }\nstruct S { a: ubyte; e: E; b: uint; }"))

        // assert
        @Expect(sut.contains("readUInt8(buf, pos)"))
        @Expect(sut.contains("E.fromValue(readUInt8(buf, pos + 1))"))
        @Expect(sut.contains("readUInt32(buf, pos + 4)"))
    }

    @TestCase
    func aTableReadsEachFieldByItsId() {
        // act
        let sut = viewsOf(
            namesOf(
                "table T {}\nunion U { T }\nenum E : int { A = 2, B }\nstruct S { x: int; }\ntable X {\n  a: int = 5;\n  u: U;\n  e: E = B;\n  s: S;\n  t: T;\n  v: [S];\n  w: [string];\n  us: [U];\n}"
            ))

        // assert
        @Expect(sut.contains("fb.scalar(0, 5, readInt32)"))
        @Expect(sut.contains("public prop u: ?U {"))
        @Expect(sut.contains("U.read(fb, 1)"))
        @Expect(sut.contains("E.fromValue(fb.scalar(3, 3, readInt32))"))
        @Expect(sut.contains("fb.structAt(4).map {p => S(fb.buf, p)}"))
        @Expect(sut.contains("fb.table(5).map {x => T(x)}"))
        @Expect(sut.contains("fb.vector(6, 4, {b, p => S(b, p)})"))
        @Expect(sut.contains("fb.vector(7, 4, readString)"))
        @Expect(sut.contains("public prop us: FbVector<U> {"))
        @Expect(sut.contains("U.readVector(fb, 8)"))
    }

    @TestCase
    func aRequiredFieldIsNotOptionalAndADeprecatedOneIsLeftOut() {
        // act
        let sut = viewsOf(namesOf("table X { name: string (required); old: int (deprecated); note: string; }"))

        // assert
        @Expect(sut.contains("public prop name: String {"))
        @Expect(sut.contains("FbTable.required(fb.string(0), \"X\", \"name\")"))
        @Expect(!sut.contains("old"))
        @Expect(sut.contains("public prop note: ?String {"))
        @Expect(sut.contains("fb.string(2)"))
    }

    @TestCase
    func aWrappedFieldIsReadThroughItsType() {
        // act
        let sut = viewsOf(namesOf("table X { bits: [ulong]; }", wrap: [("X.bits", "Bits")]))

        // assert
        @Expect(sut.contains("public prop bits: Bits {"))
        @Expect(sut.contains("Bits(fb.vector(0, 8, readUInt64))"))
    }

    @TestCase
    func theRootTableHasItsFileIdentifierAndARoot() {
        // act
        let sut = viewsOf(namesOf("file_identifier \"ABCD\";\ntable R {}\ntable X {}\nroot_type R;"))

        // assert
        @Expect(sut.contains("static let FILE_IDENTIFIER = \"ABCD\""))
        @Expect(sut.contains("static func root(buf: Array<Byte>): R {"))
        @Expect(sut.split("static func root").size, 2)
    }

    @TestCase
    func aFieldNamedLikeWhatAViewHoldsIsRefused() {
        // act & assert
        @AssertThrows[ConfigException](emitViews(namesOf("table X { fb: int; }"), "", "p"))
        @AssertThrows[ConfigException](emitViews(namesOf("struct S { pos: int; }"), "", "p"))
    }

    @TestCase
    func aDefaultThatIsNoMemberOfTheEnumIsRefused() {
        // act & assert
        @AssertThrows[ConfigException](emitViews(namesOf("enum E : int { A }\ntable X { e: E = Z; }"), "", "p"))
    }

    @TestCase
    func theSchemasCommentsBecomeDocComments() {
        // act
        let sut = viewsOf(namesOf("// what X is\ntable X {\n  a: int; // what a is\n}"))

        // assert
        @Expect(sut.contains("/**\n* what X is\n*/\npublic struct X {"))
        @Expect(sut.contains("/**\n* what a is\n*/\npublic prop a: Int32 {"))
    }
}

@Test
class CodeWriterTest {
    @TestCase
    func blocksIndentTheirBodiesAndBlankLinesStayEmpty() {
        // arrange
        let sut = CodeWriter()

        // act
        sut.block("a") {
            sut.line("b")
            sut.blank()
            sut.line("")
        }

        // assert
        @Expect(sut.toString(), "a {\n    b\n\n\n}\n")
    }

    @TestCase
    func aDocCommentCannotEndOrOpenACommentEarly() {
        // arrange
        let sut = CodeWriter()

        // act
        sut.doc(["a */ b /* c", ""])
        sut.doc([])

        // assert
        @Expect(sut.toString(), "/**\n * a *\\/ b /\\* c\n *\n */\n")
    }

    @TestCase
    func aQuotedStringEscapesWhatALiteralWouldRead() {
        // act & assert
        @Expect(quoted("a\"b\\c\$d\ne"), "\"a\\\"b\\\\c\\\$d\\ne\"")
    }
}
