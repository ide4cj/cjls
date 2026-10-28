package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*
import loupe.hir.*
import rope.Rope

@Test
class FunctionBindingInferenceTest {
    @TestCase
    func addingTheCAnnotationInvalidatesTheCallbackType() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            func callback(x: Int32): Int32 { x }
            func test(): Unit {
                let f: CFunc<(Int32) -> Int32> = callback
            }
            "#
                )
        let db = deriveDatabase(fixture)
        let file = fixture.files[0]
        @Expect(diagnostics(db, file.fileId).size, 1)

        // act
        db.setFileText(file.fileId, Rope("@C\n${file.text}"))

        // assert
        @Expect(diagnostics(db, file.fileId), Array<Diagnostic>())
    }

    @TestCase
    func anOrdinaryFunctionStillDoesNotFitACFunctionParameter() {
        checkDiagnostics(
            #"
            package m
            func callback(x: Int32): Int32 { x }
            func test(): Unit {
                let f: CFunc<(Int32) -> Int32> = callback
            //                                   ^^^^^^^^ error: mismatched types: expected 'CFunc<(Int32) -> Int32>', found '(Int32) -> Int32'
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func aCFunctionWithADifferentSignatureStillDoesNotFit() {
        checkDiagnostics(
            #"
            package m
            @C
            func callback(x: Int64): Int64 { x }
            func test(): Unit {
                let f: CFunc<(Int32) -> Int32> = callback
            //                                   ^^^^^^^^ error: mismatched types: expected 'CFunc<(Int32) -> Int32>', found 'CFunc<(Int64) -> Int64>'
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func aCAnnotatedFunctionHasACFunctionType() {
        checkDiagnostics(
            #"
            package m
            @C
            func callback(x: Int32): Int32 { x }
            func take(f: CFunc<(Int32) -> Int32>): Unit {}
            func test(): Unit {
                let f: CFunc<(Int32) -> Int32> = callback
                take(callback)
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func explicitTypeArgumentsSelectAnImportedGenericBeforeANongenericMember() {
        checkDiagnostics(
            #"
            //- /convert.cj module=convert package=convert
            package convert
            public func read<T>(value: Int64): ?T { None }
            //- /main.cj module=m package=m deps=convert
            package m
            import convert.read
            struct Span {
                Span(let start: Int64, let end: Int64) {}
                static func at(offset: Int64, size: Int64): Span { Span(offset, offset + size) }
            }
            extend Span {
                static func read(value: Int64): ?Span { None }
                static func bind(value: Int64): Unit {
                    while (true) {
                        let offset = read<Int64>(value) ?? break
                        let size = read<Int64>(value) ?? break
                        let span = Span.at(offset, size)
                    }
                }
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func aServedBindingKeepsItsCAnnotatedCallbackType() {
        // arrange
        let macros = trimIndent(EXPANSION_MACROS)
        let fixture =
            Fixture
                .parse(
                    "//- /main.cj module=m package=m\npackage m\nimport m.ms.A\n@A struct Bound {}\n${macros}"
                )
        let db = deriveDatabase(fixture)
        let file = db.sourceFile(fixture.file("/main.cj").fileId).getOrThrow()
        let output =
            trimIndent(
                #"
            struct Bound {}
            @C
            func initialize(value: Int32): Int32 { value }
            func setInit(callback: CFunc<(Int32) -> Int32>): Unit {}
            extend Bound {
                static func initializeClass(): Unit { setInit(initialize) }
            }
            "#
            )
        answer(db, file, "A", output, [])

        // act
        let found = diagnostics(db, file.fileId(db))

        // assert
        @Expect(String.join(found.map { one => one.message }, delimiter: "\n"), "")
    }
}
