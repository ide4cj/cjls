package fbs_codegen

import std.unittest.*
import std.unittest.testmacro.*

func writersOf(schema: String): String {
    viewsOf(namesOf(schema, write: true))
}

@Test
class EmitWritersTest {
    @TestCase
    func noWriterIsMadeUnlessTheConfigAsks() {
        // act
        let sut = viewsOf(namesOf("table T { a: int; }"))

        // assert
        @Expect(!sut.contains("TData"))
        @Expect(sut.contains("import fbs.*"))
    }

    @TestCase
    func aTablesChildrenAreBuiltBeforeItAndItsFieldsSlottedByTheirIds() {
        // act
        let sut =
            writersOf(
                "table C {} union U { C } table T { u: U; s: string; v: [int]; c: C; n: short = 3; }"
            )

        // assert
        let start =
            sut.indexOf("b.startTable()\nif (let (Some(v), Some(o)) <- (u, uOffset))").getOrThrow()
        @Expect(sut.indexOf("let uOffset = u.map {v => v.pack(b)}").getOrThrow() < start)
        @Expect(sut.indexOf("let sOffset = s.map {v => b.createString(v)}").getOrThrow() < start)
        @Expect(sut.indexOf("let vOffset = b.endVector(v.size)").getOrThrow() < start)
        @Expect(sut.contains("b.addUInt8(v.tag)\nb.slot(0)\nb.addOffset(o)\nb.slot(1)"))
        @Expect(sut.contains("b.addOffset(vOffset)\nb.slot(3)"))
        @Expect(sut.contains("if (n != 3) {\nb.addInt16(n)\nb.slot(5)"))
    }

    @TestCase
    func aFieldThatMayBeAbsentDefaultsToItsSchemasDefaultOrNone() {
        // act
        let sut =
            writersOf(
                "enum E : byte { A, B } table T { n: uint = 1; e: E = B; s: string; v: [string]; r: string (required); }"
            )

        // assert
        @Expect(sut.contains("public let n!: UInt32 = 1"))
        @Expect(sut.contains("public let e!: E = E.fromValue(1)"))
        @Expect(sut.contains("public let s!: ?String = None"))
        @Expect(sut.contains("public let v!: Array<String> = []"))
        @Expect(sut.contains("public let r!: String"))
        @Expect(sut.contains("let rOffset = b.createString(r)"))
    }

    @TestCase
    func aStructIsWrittenAtItsOffsetsAndAddedInlineAligned() {
        // act
        let sut = writersOf("struct P { a: ubyte; b: int; } table T { p: P; ps: [P]; }")

        // assert
        @Expect(sut.contains("public static const SIZE = 8"))
        @Expect(sut.contains("writeUInt8(buf, pos + 0, a)\nwriteInt32(buf, pos + 4, b)"))
        @Expect(sut.contains("b.addStruct(v.toBytes(), PData.ALIGNMENT)\nb.slot(0)"))
        @Expect(sut.contains("b.startVector(PData.SIZE, ps.size, PData.ALIGNMENT)"))
    }

    @TestCase
    func aStructsEnumAndStructFieldsAndARequiredStructOrUnionAreWritten() {
        // act
        let sut =
            writersOf(
                "enum E : short { A } struct P { x: int; } struct S { e: E; p: P; } table C {} union U { C } " +
                    "table T { es: [E]; s: S (required); u: U (required); }"
            )

        // assert
        @Expect(sut.contains("writeInt16(buf, pos + 0, e.value)\np.writeTo(buf, pos + 4)"))
        @Expect(sut.contains("b.addInt16(es[i].value)"))
        @Expect(sut.contains("b.addStruct(s.toBytes(), SData.ALIGNMENT)\nb.slot(1)"))
        @Expect(sut.contains("let uOffset = u.pack(b)"))
        @Expect(sut.contains("b.addUInt8(u.tag)\nb.slot(2)\nb.addOffset(uOffset)\nb.slot(3)"))
    }

    @TestCase
    func aUnionsWriterKnowsItsTagAndBuildsAStructAlone() {
        // act
        let sut = writersOf("struct S { x: long; } table C {} union U { C, s: S, t: string }")

        // assert
        @Expect(sut.contains("| AsC(CData)\n| AsS(SData)\n| AsT(String)"))
        @Expect(sut.contains("case AsS(_) => 2"))
        @Expect(sut.contains("case AsS(v) => b.createStruct(v.toBytes(), SData.ALIGNMENT)"))
        @Expect(sut.contains("case AsT(v) => b.createString(v)"))
    }

    @TestCase
    func theRootIsFinishedWithItsFileIdentifier() {
        // act
        let sut = writersOf("table T {} root_type T; file_identifier \"ABCD\";")

        // assert
        @Expect(sut.contains("b.finish(pack(b), fileIdentifier: \"ABCD\")"))
    }

    @TestCase
    func aVectorOfUnionsOrAFieldNamedLikeTheWriterIsRefused() {
        // act, assert
        @AssertThrows[ConfigException](writersOf("table C {} union U { C } table T { us: [U]; }"))
        @AssertThrows[ConfigException](writersOf("table T { pack: int; }"))
        @AssertThrows[ConfigException](writersOf("table T {} table TData {}"))
    }
}
