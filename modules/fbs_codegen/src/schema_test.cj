package fbs_codegen

import std.unittest.*
import std.unittest.testmacro.*

/**
 * A field's type as a schema would write it.
 */
func show(t: FbType): String {
    match (t) {
        case ScalarType(s) => s.cangjie
        case StringType => "string"
        case NamedType(n) => n
        case VectorType(e) => "[${show(e)}]"
    }
}

@Test
class SchemaTest {
    @TestCase
    func theHeaderStatementsAreRead() {
        // act
        let sut = parseSchema(
            "namespace A.B;\nattribute \"priority\";\nfile_identifier \"ABCD\";\ntable T { x: int; }\nroot_type T;")

        // assert
        @Expect(sut.namespace, "A.B")
        @Expect(sut.fileIdentifier, Some("ABCD"))
        @Expect(sut.rootType, Some("T"))
        @Expect(sut.decls.map {d => d.name}, ["T"])
    }

    @TestCase
    func enumMembersCountOnFromTheLastValueGiven() {
        // act
        let sut = parseSchema("enum E : ubyte { A, B = 5, C, D = 2, }")

        // assert
        let e = sut.decls[0]
        @Expect(e.kind == EnumDecl)
        @Expect(e.underlying == Some(FbUInt8))
        @Expect(e.members.map {m => m.name}, ["A", "B", "C", "D"])
        @Expect(e.members.map {m => m.value}, [0, 5, 6, 2])
    }

    @TestCase
    func anEnumOfAnythingButAnIntegerIsRefused() {
        // act & assert
        @AssertThrows[SchemaException](parseSchema("enum E : float { A }"))
        @AssertThrows[SchemaException](parseSchema("enum E : string { A }"))
    }

    @TestCase
    func aUnionMemberMayHoldATypeOfAnotherName() {
        // act
        let sut = parseSchema("table T {}\nunion U { T, StringValue: string }")

        // assert
        let u = sut.decls[1]
        @Expect(u.kind == UnionDecl)
        @Expect(u.unionMembers.map {m => m.name}, ["T", "StringValue"])
        @Expect(u.unionMembers.map {m => m.typeName}, ["T", "string"])
    }

    @TestCase
    func fieldsHaveTheirTypesDefaultsAndMetadata() {
        // act
        let sut = parseSchema(
            "table T {\n  a: uint = 7;\n  b: string (required);\n  c: [ubyte];\n  d: [S] (deprecated, priority: 1);\n  e: x.S;\n}")

        // assert
        let fields = sut.decls[0].fields
        @Expect(fields.map {f => f.name}, ["a", "b", "c", "d", "e"])
        @Expect(fields.map {f => show(f.fbType)}, ["UInt32", "string", "[UInt8]", "[S]", "x.S"])
        @Expect(fields[0].defaultValue, Some("7"))
        @Expect(fields[1].defaultValue, Option<String>.None)
        @Expect(fields.map {f => f.required}, [false, true, false, false, false])
        @Expect(fields.map {f => f.deprecated}, [false, false, false, true, false])
    }

    @TestCase
    func commentsAboveADeclarationAndAtTheEndOfItsLineDocumentIt() {
        // act
        let sut = parseSchema(
            "// a file header\n\n/// what T is\n// in two lines\ntable T {\n  // what a is\n  a: int; // and more\n  b: int;\n}")

        // assert
        let t = sut.decls[0]
        @Expect(t.doc, ["what T is", "in two lines"])
        @Expect(t.fields[0].doc, ["what a is", "and more"])
        @Expect(t.fields[1].doc.size, 0)
    }

    @TestCase
    func aCommentAfterADeclarationOnItsLineDoesNotDocumentTheNext() {
        // act
        let sut = parseSchema("enum E : byte {\n  A, // the first\n  B\n}")

        // assert
        @Expect(sut.decls[0].members[0].doc, ["the first"])
        @Expect(sut.decls[0].members[1].doc.size, 0)
    }

    @TestCase
    func blockCommentsAreSkipped() {
        // act
        let sut = parseSchema("/* a\n * block\n */\ntable T { a: int; /* inline */ b: int; }")

        // assert
        @Expect(sut.decls[0].fields.map {f => f.name}, ["a", "b"])
    }

    @TestCase[text in ["include \"other.fbs\";", "rpc_service S {}", "table T { a: int (id: 0); }", "table T { a int; }",
        "table T { a: int }"]]
    func whatTheSubsetDoesNotReadIsRefused(text: String) {
        // act & assert
        @AssertThrows[SchemaException](parseSchema(text))
    }

    @TestCase
    func aRefusalNamesItsLine() {
        // act
        let sut = try {
            parseSchema("table T {\n  a: int;\n  b int;\n}")
            ""
        } catch (e: SchemaException) {
            e.message
        }

        // assert
        @Expect(sut.startsWith("line 3:"))
    }
}
