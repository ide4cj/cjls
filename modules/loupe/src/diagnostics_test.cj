package loupe

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import loupe.db.*
import loupe.fixture.*
import loupe.hir.packageOfFile
import loupe.vfs.FileId
import rope.Rope

func diagnosticsOf(text: String): Array<Diagnostic> {
    let db = AnalysisDatabase()
    db.setFileText(FileId(0), Rope(text))
    diagnostics(db, FileId(0))
}

@Test
class DiagnosticsTest {
    @TestCase
    func aFileThatParsesHasNone() {
        // act
        let result = diagnosticsOf("func f(): Int64 { 1 }\n")

        // assert
        @Expect(result.size, 0)
    }

    @TestCase
    func aSyntaxErrorIsAnErrorWhereTheParserPutIt() {
        checkDiagnostics(
            #"
            class A {
            //       | error: expected '}'
            "#
        )
    }

    @TestCase
    func emptyInterpolationsAreSyntaxErrorsAndLaterCodeStillParses() {
        checkDiagnostics(
            #"
            func f(): Unit {
                let a = "${}after${1}"
            //             | error: string interpolation cannot be empty
                let b = "${ /* empty */ ; ; }"
            //                             | error: string interpolation cannot be empty
                let c = "${; let n = 1; n;}"
            }
            "#
        )
    }

    @TestCase
    func eachFileHasItsOwn() {
        checkDiagnostics(
            #"
            //- /a.cj
              func f() {
                  let x =
            //           | error: expected an expression
              }
            //- /b.cj
            func g(): Int64 { 1 }
            //- /c.cj
              class C { func }
            //              | error: expected '('
            //              | error: expected a name
            "#
        )
    }

    @TestCase
    func theyComeInTheOrderOfTheText() {
        // act
        let result = diagnosticsOf("let a = \nlet b = \n")

        // assert
        @Expect(result.map {diagnostic => diagnostic.range}, [TextRange(7, 7), TextRange(16, 16)])
    }

    @TestCase
    func aFileTheDatabaseDoesNotKnowHasNone() {
        // arrange
        let db = AnalysisDatabase()

        // act
        let result = diagnostics(db, FileId(0))

        // assert
        @Expect(result.size, 0)
    }
}

/**
 * What is wrong with a file's scope, where cjc 1.3.0-alpha.20261002 puts it: a path that fails from
 * its start to its last name, a name brought twice or shadowed at that name, as a warning.
 */
@Test
class ScopeDiagnosticsInFileTest {
    @TestCase
    func theImportsOfAFileAreReportedWhereCjcPutsThem() {
        checkDiagnostics(
            #"
            //- /a/a.cj module=imp package=imp.a
            package imp.a
            public class C {}
            //- /b/b.cj module=imp package=imp.b
            package imp.b
            public class C {}
            //- /main.cj module=imp package=imp
            package imp
            import imp.a.C
            import imp.b.C
            //           ^ warning: imported decl 'C' is conflicted with other import
            import imp.{a.nope, b.C as D}
            //     ^^^^^^^^^^^ error: 'nope' is not accessible in package 'imp.a'
            //                         ^ warning: imported decl 'D' is shadowed, it will be ignored by compiler
            class D {}
            "#
        )
    }
}

/**
 * What inference finds wrong, reported as cjc does (#48's 8c′b): a mismatch and a count of
 * arguments, between types known wholly. Each case compiled with cjc 1.3.0-alpha.20261002 first.
 */
@Test
class InferenceDiagnosticsTest {
    @TestCase
    func arrayLiteralsAreCheckedAgainstTheExpectedVArray() {
        // #491: checking only the annotated local's type misses a mismatch on its initializer.
        checkDiagnostics(
            #"
            package m
            type Pair = VArray<Int8, $2>
            func pair(): Pair { [1, 2] }
            func take(a: Pair, b!: Pair): Unit {}
            func choose(a: VArray<Int8, $1>): Int8 { 1 }
            func choose(a: Pair): Int64 { 2 }
            func test(): Unit {
                let a: VArray<Int64, $4> = [1, 2, 3, 4]
                for (i in 0..4) {
                    print("${a[i]}, ")
                }
                var b: Pair = [1, 2]
                b = [3, 4]
                let c: ?Pair = [5, 6]
                // Whitespace keeps the zero size distinct from the fixture's cursor marker.
                let d: VArray<Int8, $ 0> = []
                let e: VArray<Pair, $1> = [[1, 2]]
                take([1, 2], b: [3, 4])
                let selected: Int64 = choose([1, 2])
                let ordinary = [1, 2]
                let narrow: Array<Int8> = [1, 2]
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func aVArrayLiteralStillChecksItsElementsAndLength() {
        checkDiagnostics(
            #"
            package m
            func test(s: String): Unit {
                let a: VArray<Int8, $2> = [1, s]
            //                                ^ error: mismatched types: expected 'Int8', found 'String'
                let b: VArray<Int8, $2> = [1]
            //                            ^^^ error: mismatch 'VArray' type's size: expected size is 2, found 1
                let c: VArray<Int8, $2> = [1, 2, 3]
            //                            ^^^^^^^^^ error: mismatch 'VArray' type's size: expected size is 2, found 3
                let d: VArray<Int8, $1> = []
            //                            ^^ error: mismatch 'VArray' type's size: expected size is 1, found 0
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func aValueOfAnotherTypeThanTheOneExpectedIsAMismatch() {
        checkDiagnostics(
            #"
            package m
            func f(a: Int64, b: String): Int64 { a }
            func g(): Unit {
                let x: Int64 = "s"
            //                 ^^^ error: mismatched types: expected 'Int64', found 'String'
                let y: String = f(1, "a")
            //                  ^^^^^^^^^ error: mismatched types: expected 'String', found 'Int64'
                var z = 1
                z = "q"
            //      ^^^ error: mismatched types: expected 'Int64', found 'String'
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func aQuoteIsCheckedInItsInterpolationsOnly() {
        // #195: the rest is tokens, checked where the macro is expanded
        checkDiagnostics(
            #"
            package m
            import std.ast.*
            func f(a: Int64): Tokens { quote() }
            func g(): Tokens {
                quote(f("s") + $(f("s")))
            //                     ^^^ error: mismatched types: expected 'Int64', found 'String'
            }
            "#,
            binaries: ["std.core", "std.ast"]
        )
    }

    @TestCase
    func anIntegerLiteralWhereNoNumberIsExpectedCannotBeConverted() {
        checkDiagnostics(
            #"
            package m
            class C { func m(x: Bool): Unit {} }
            func f(a: Int64, b: String): Unit {}
            func g(): Unit {
                f(1, 2)
            //       ^ error: cannot convert an integer literal to type 'String'
                C().m(1)
            //        ^ error: cannot convert an integer literal to type 'Bool'
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func tooFewOrTooManyArgumentsOfOneFunctionAreReportedOverTheArguments() {
        checkDiagnostics(
            #"
            package m
            func f(a: Int64, b: String): Int64 { a }
            class K { init(a: Int64) {} }
            enum E { | A(Int64) | B }
            func t(a: Int64, f: () -> Unit): Unit {}
            func g(): Unit {
                f(1)
            //   ^^^ error: missing argument for parameter list '(Int64, String)' in call: expected 2 arguments, found 1
                f(1, "a", 3)
            //   ^^^^^^^^^^^ error: extra argument given for parameter list '(Int64, String)' in call: expected 2 arguments, found 3
                K()
            //   ^^ error: missing argument for parameter list '(Int64)' in call: expected 1 argument, found 0
                E.A(1, 2)
            //     ^^^^^^ error: extra argument given for parameter list '(Int64)' in call: expected 1 argument, found 2
                let h: (Int64) -> Unit = {x => ()}
                h()
            //   ^^ error: missing argument for parameter list '(Int64)' in call: expected 1 argument, found 0
                t(1, {=> ()}) {}
            //   ^^^^^^^^^^^^^^^ error: extra argument given for parameter list '(Int64, () -> Unit)' in call: expected 2 arguments, found 3
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func anArgumentPassedByAWrongNameOrByNoneIsReportedAtTheArgument() {
        checkDiagnostics(
            #"
            package m
            func f(a: Int64, b!: Int64, c!: Int64 = 0): Int64 { a }
            func g(a: Int64, xs: Array<Int64>): Int64 { a }
            func k(a: Int64, h!: (Int64) -> Int64): Int64 { a }
            func test(): Unit {
                f(1, b: 2, z: 3)
            //             ^^^^ error: unknown named argument prefix 'z:'
                f(1, b: 2, b: 3)
            //             ^^^^ error: named argument prefix 'b:' cannot appeared more than once in call
                f(1, 2)
            //       ^ error: missing argument prefix 'b:' or 'c:' for named parameter
                f(1, 2, 3)
            //       ^ error: missing argument prefix 'b:' or 'c:' for named parameter
                f(1)
            //   ^^^ error: missing arguments for parameter list '(Int64, Int64, Int64)' in call: expected 3 arguments, found 1
                let h = {x: Int64 => x}
                h(x: 1)
            //    ^^^^ error: named argument cannot be used in variable function call
                // a variadic one that fits not: what its arguments as they are found
                g(1, 2, "s")
            //   ^^^^^^^^^^^ error: extra argument given for parameter list '(Int64, Array<Int64>)' in call: expected 2 arguments, found 3
                g(1, 2, b: 3)
            //          ^^^^ error: unknown named argument prefix 'b:'
                g()
            //   ^^ error: missing arguments for parameter list '(Int64, Array<Int64>)' in call: expected 2 arguments, found 0
                k(1, h: {x => x}) { x => x }
            //   ^^^^^^^^^^^^^^^^^^^^^^^^^^^ error: extra argument given for parameter list '(Int64, (Int64) -> Int64)' in call: expected 2 arguments, found 3
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func aParameterOfABinaryWhoseDefaultIsNoConstantMayBeLeftOut() {
        checkDiagnostics(
            #"
            package m
            import std.time.DateTime
            func g(): Unit {
                // `timeZone!: TimeZone = TimeZone.Local`, whose value the `.cjo` does not hold
                let now = DateTime.now()
            }
            "#,
            binaries: ["std.core", "std.time"]
        )
    }

    @TestCase
    func whatCjcAcceptsIsNoError() {
        checkDiagnostics(
            #"
            package m
            func v(a: Int64, b: Array<Int64>): Unit {}
            func w(b: Array<Int64>): Unit {}
            func named(a: Int64, b!: Int64 = 0): Unit {}
            func h(a: Int64): Unit {}
            func h(a: String): Unit {}
            func t(a: Int64, f: () -> Unit): Unit {}
            struct S { init(a: Int64, b!: Bool = false) {} }
            func g(): Unit {
                v(1, 2, 3)
                v(1)
                w()
                named(1)
                named(1, b: 2)
                S(1)
                h("s")
                t(1) {}
                let any: Any = S(1)
                let s: ToString = 1
                let o: ?Int64 = 1
                let u: Unit = h(1)
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func whatTheGateOfStdsSourcesFoundIsNoError() {
        checkDiagnostics(
            #"
            package m
            foreign func abs(x: Int32): Int32
            interface K<T> {}
            struct W <: K<Int64> & K<String> {}
            class C {
                func f(): This { this }
            }
            type Small = Int16
            extend Small {
                func twice(): Int16 { this * 2 }
            }
            class R {
                func r(at!: Int64): Int64 { at }
                func r(range: Range<Int64>): Unit {}
            }
            func s(a: Int64, b!: Int64 = 0): Int64 { a + b }
            func s(a: String): String { a }
            func g(o: ?Int64, c: R): Unit {
                let q = abs
                let l: CFunc<(Int32) -> Int32> = {x: Int32 => x}
                let one: Byte = 'a'
                let r: Rune = "x"
                let shifted: UInt64 = 1 << 3
                let k: K<String> = W()
                let joined: ?Int64 = if (true) { o } else { 1 }
                let it: Iterable<Int8> = [0, 1]
                let t: ?(Int64, ?String) = (1, "s")
                let n: Int16 = 21
                let tw: Int16 = n.twice()
                let r1: Int64 = c.r(at: 1)
                let s1: Int64 = s(1)
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func nothingIsReportedAboutATypeNotKnown() {
        checkDiagnostics(
            #"
            package m
            func f(a: Int64): Unit {}
            func g(): Unit {
                let x: Int64 = nope
                f(nope)
                f(missing())
                let y: Nope = 1
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func aVariadicFunctionOfACjoIsCalledWithItsArraysElements() {
        checkDiagnostics(
            #"
            package m
            import std.collection.ArrayList
            // cjc: no error
            func g(s: String): Unit {
                let a = String.fromUtf8(97u8, 98u8)
                let b = String.fromUtf8()
                let c = String.fromUtf8([97u8])
                let d = Float64.max(1.0, 2.0)
                let e = Float64.max(1.0, 2.0, 3.0, 4.0)
                let f = ArrayList.of(1, 2, 3)
                let h = ArrayList<Int64>.of()
                let t = s.trimStart(r'a', r'b')
                let u = s.trimStart(r'a')
            }
            "#,
            binaries: ["std.core", "std.collection"]
        )
    }

    @TestCase
    func aFileOfNoPackageCallsAVariadicFunctionOfStdCoreWithItsArraysElements() {
        // arrange - a project with the SDK's std, and a file in none of its packages: one under
        // `target`, or above the root
        let fixture =
            Fixture
                .parse(
                    #"
            //- /m/m.cj module=m package=m
            package m
            "#
                )
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let loose = FileId(fixture.files.size)
        db
            .setFileText(
                loose,
                Rope(
                    "func g(): Unit {\n    let d = Float64.max(1.0, 2.0)\n    let e = Float64.max(1.0, 2.0, 3.0, 4.0)\n}\n"
                )
            )

        // act
        let result = diagnostics(db, loose).map { one => one.message }

        // assert - cjc: none, `others` taking any number of elements
        @Expect(result, Array<String>())
    }

    @TestCase
    func aNamedParameterLeftOutIsMissingWithTheNamesPassedAfterIt() {
        checkDiagnostics(
            #"
            package m
            func f(a!: Int64, b!: Int64, c!: Int64): Unit {}
            func g(): Unit {
                f(b: 1, c: 2)
            //   ^^^^^^^^^^^^ error: missing argument for parameter list '(Int64, Int64, Int64)' in call: expected 3 arguments, found 2
                // a positional argument where a name is needed, the names passed after it listed
                f(1, c: 2)
            //   ^^^^^^^^^ error: missing argument for parameter list '(Int64, Int64, Int64)' in call: expected 3 arguments, found 2
            }
            "#,
            binaries: ["std.core"]
        )
    }

    /**
     * cjc: "no matching function" on both; not reported, a macro the analysis has not read may have
     * made the member one (A32).
     */
    @TestCase
    func aMemberNoFunctionAndATypesMemberNotFoundAreNotReported() {
        checkDiagnostics(
            #"
            package m
            class A { let x = 1 }
            func g(): Unit {
                A.foo()
                let a = A()
                a.x()
            }
            "#,
            binaries: ["std.core"]
        )
    }
}

/**
 * The file `/main.cj` of `fixture` whose one `@Derive` the server answered: its output the type after the call,
 * copied, then `written`, which the macro wrote; the database and the file.
 */
func derivedByServer(fixture: String, written: String): (AnalysisDatabase, SourceFile) {
    let parsed = Fixture.parse(fixture)
    let db = deriveDatabase(parsed)
    let file = db.sourceFile(parsed.file("/main.cj").fileId).getOrThrow()
    let text = file.text(db).toString()
    let anchor = offsetIn(text, "@Derive")
    let start = text.indexOf("\n", anchor).getOrThrow() + 1
    let copied = text[start..].trimAscii()
    let output = copied + "\n" + written
    answer(
        db,
        file,
        "Derive",
        output,
        [
            MappedSpan(
                TextRange(0, copied.size),
                SpanOrigin.FromSource(TextRange(start - anchor, start - anchor + copied.size))
            ),
            MappedSpan(TextRange(copied.size + 1, output.size), SpanOrigin.FromCall)
        ]
    )
    (db, file)
}

/**
 * The bodies of an item the macro server's output replaces are read in that output alone (D132, #431).
 */
@Test
class ReplacedItemDiagnosticsTest {
    @TestCase
    func aTypeTheServersDeriveReplacedIsNotCheckedAgainstItsSourceTwin() {
        // arrange
        let (db, file) =
            derivedByServer(
                #"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Equatable]
            enum E {
                | A
                | B

                static func named(n: String): ?E {
                    match (n) {
                        case "a" => A
                        case _ => None
                    }
                }
            }
            "#,
                "extend E <: Equatable<E> {\n    public operator func ==(that: E): Bool { true }\n" +
                    "    public operator func !=(that: E): Bool { false }\n}"
            )

        // act
        let result = diagnostics(db, file.fileId(db))

        // assert
        @Expect(result.map {one => one.message}, Array<String>())
    }

    @TestCase
    func aMismatchInCopiedTextIsWhereItWasCopiedFromAndInWrittenTextAtTheCallsHead() {
        // arrange
        let (db, file) =
            derivedByServer(
                #"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Equatable]
            struct S {
                func f(): Unit {
                    let x: Int64 = "s"
                }
            }
            "#,
                "extend S <: Equatable<S> {\n    public operator func ==(that: S): Bool {\n" +
                    "        let y: Bool = \"no\"\n        y\n    }\n    public operator func !=(that: S): Bool { false }\n}"
            )
        let text = file.text(db).toString()

        // act
        let result = diagnostics(db, file.fileId(db))

        // assert
        let head = offsetIn(text, "@Derive")
        let s = offsetIn(text, "\"s\"")
        @Expect(result.map {one => "${one.range} ${one.message}"}, [
            "${TextRange(head, head + "@Derive[Equatable]".size)} mismatched types: expected 'Bool', found 'String'",
            "${TextRange(s, s + 3)} mismatched types: expected 'Int64', found 'String'"
        ])
    }

    @TestCase
    func anOutputOlderThanTheTextReportsNothingOfItsBodies() {
        // arrange
        let (db, file) =
            derivedByServer(
                #"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Equatable]
            struct S {
                func f(): Int64 { "s" }
            }
            "#,
                "extend S <: Equatable<S> {\n    public operator func ==(that: S): Bool { true }\n" +
                    "    public operator func !=(that: S): Bool { false }\n}"
            )
        let text = file.text(db).toString()

        // act
        db.setFileText(file.fileId(db), Rope(text.replace("\"s\"", "\"t\"")))
        let result = diagnostics(db, file.fileId(db))

        // assert
        @Expect(result.map {one => one.message}, Array<String>())
    }
}

/**
 * What the gate of std's sources found where cjc finds nothing (#287), each case of std's code
 * compiled with cjc 1.3.0-alpha.20261002 first; a name not known (`nope`) stands for a gap of the
 * analysis there (the variadic `max` was one before #254), which nothing around it is reported for.
 */
@Test
class StdFalseMismatchesTest {
    @TestCase
    func theDotsOfAForeignFunctionTakeAnyArgumentsMoreAfterItsParameters() {
        checkDiagnostics(
            #"
            //- /native.cj module=m package=m
            package m
            foreign func open(pathname: CString, flags: Int32, ...): Int32
            foreign func cv(pathname: CString, flags: Int32, ...): Int32
            //- /file_dir.cj module=m package=m
            package m
            private func withPath(path: String, action: (CString) -> Int32): Int32 { 0 }
            public func `open`(path: String, oflag: Int32, flag: UInt32): Int32 {
                return withPath(path) {p: CString => unsafe { open(p, oflag, flag) }}
            }
            public func `open`(path: String, oflag: Int32): Int32 {
                return withPath(path) {p: CString => unsafe { open(p, oflag) }}
            }
            func h(p: CString): Unit {
                let k: Int32 = unsafe { open(p, 1, 2, 3) }
                unsafe { cv(p) }
            //             ^^^ error: missing argument for parameter list '(CString, Int32)' in call: expected 2 arguments, found 1
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func anOperandNotKnownLeavesTheLanguagesOperatorNotAnotherDeclared() {
        checkDiagnostics(
            #"
            package m
            extend Float64 {
                operator func +(arg: UInt8): Float64 { this }
            }
            func g(a: Float64, b: Float64): Unit {
                let s = a + b * nope
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func aBinaryOperatorNoCandidateFitsIsReportedAtTheOperator() {
        // N168: by its operands' types, its operand not; a `[]` by its argument, as a call; a
        // result the type expected takes not, as any value
        checkDiagnostics(
            #"
            package m
            class T {
                operator func +(r: Int64): Bool { true }
                operator func +(r: Bool): Bool { true }
                operator func [](i: Int64): Int64 { i }
            }
            func test(t: T): Unit {
                let a = 3 * "s"
            //            ^ error: invalid binary operator '*' on type 'Int64' and 'String'
                let b = t + "s"
            //            ^ error: invalid binary operator '+' on type 'T' and 'String'
                let c = t - 1
            //            ^ error: invalid binary operator '-' on type 'T' and 'Int64'
                let d = t["x"]
            //            ^^^ error: mismatched types: expected 'Int64', found 'String'
                let e: String = t + 1
            //                  ^^^^^ error: mismatched types: expected 'String', found 'Bool'
                let f = 1 + true
            //            ^ error: invalid binary operator '+' on type 'Int64' and 'Bool'
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func anArgumentNotKnownTakesNoneOfSeveralOverloads() {
        checkDiagnostics(
            #"
            package m
            func abs(x: Int64): Int64 { x }
            func abs(x: Float64): Float64 { x }
            func g(): Unit {
                let x = nope
                if (abs(x) > 0.5) {}
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func thisCallsAPrimaryConstructorOfAParameterByNameWithItsDefault() {
        checkDiagnostics(
            #"
            package m
            class Configuration {}
            class Printer {
                Printer(isColored: Bool, isOther!: Bool = true) {}
                init(configuration: Configuration) {
                    this(!false)
                }
            }
            "#,
            binaries: ["std.core"]
        )
    }
}

@Test
class ExpressionMacroDiagnosticsTest {
    @TestCase
    func generatedVArraySizeErrorsPointAtTheCallHead() {
        // arrange
        let (db, file) =
            expansionDatabase(
                #"
            package m
            import m.ms.*
            func f(): Unit { let x: VArray<Int64, $2> = @B(0) }
            "#
            )
        answer(db, file, "B", "[1]", [MappedSpan(TextRange(0, 3), SpanOrigin.FromCall)])
        let text = file.text(db).toString()

        // act
        let result = diagnostics(db, file.fileId(db))

        // assert
        @Expect(result.map {one => text[one.range.start..one.range.end]}, ["@B"])
        @Expect(result.map {one => one.message}, ["mismatch 'VArray' type's size: expected size is 2, found 1"])
    }

    @TestCase
    func copiedVArraySizeErrorsPointAtTheCopiedArgument() {
        // arrange
        let (db, file) =
            expansionDatabase(
                #"
            package m
            import m.ms.*
            func f(): Unit { let x: VArray<Int64, $2> = @B([1]) }
            "#
            )
        let text = file.text(db).toString()
        let start = offsetIn(text, "[1]") - offsetIn(text, "func f")
        answer(
            db,
            file,
            "B",
            "[1]",
            [MappedSpan(TextRange(0, 3), SpanOrigin.FromSource(TextRange(start, start + 3)))]
        )

        // act
        let result = diagnostics(db, file.fileId(db))

        // assert
        @Expect(result.map {one => text[one.range.start..one.range.end]}, ["[1]"])
        @Expect(result.map {one => one.message}, ["mismatch 'VArray' type's size: expected size is 2, found 1"])
    }

    @TestCase
    func generatedTypeErrorsPointAtTheCallHead() {
        // arrange
        let (db, file) =
            expansionDatabase(
                #"
            package m
            import m.ms.*
            func f(): Unit { let x: Int64 = @B(1) }
            "#
            )
        answer(db, file, "B", "true", [MappedSpan(TextRange(0, 4), SpanOrigin.FromCall)])
        let text = file.text(db).toString()

        // act
        let result = diagnostics(db, file.fileId(db))

        // assert
        @Expect(result.map {one => text[one.range.start..one.range.end]}, ["@B"])
        @Expect(result.map {one => one.message}, ["mismatched types: expected 'Int64', found 'Bool'"])
    }

    @TestCase
    func copiedTypeErrorsPointAtTheCopiedArgument() {
        // arrange
        let (db, file) =
            expansionDatabase(
                #"
            package m
            import m.ms.*
            func f(): Unit { let x: Int64 = @B(true) }
            "#
            )
        let text = file.text(db).toString()
        let start = offsetIn(text, "true") - offsetIn(text, "func f")
        answer(
            db,
            file,
            "B",
            "true",
            [MappedSpan(TextRange(0, 4), SpanOrigin.FromSource(TextRange(start, start + 4)))]
        )

        // act
        let result = diagnostics(db, file.fileId(db))

        // assert
        @Expect(result.map {one => text[one.range.start..one.range.end]}, ["true"])
        @Expect(result.map {one => one.message}, ["mismatched types: expected 'Int64', found 'Bool'"])
    }

    @TestCase
    func errorsInGeneratedStatementsPointAtTheirOwnCall() {
        // arrange
        let (db, file) =
            expansionDatabase(
                #"
            package m
            import m.ms.*
            func f(): Unit { @B(1) }
            "#
            )
        let output = "let x: Bool = 1"
        answer(db, file, "B", output, [MappedSpan(TextRange(0, output.size), SpanOrigin.FromCall)])
        let text = file.text(db).toString()

        // act
        let result = diagnostics(db, file.fileId(db))

        // assert
        @Expect(result.map {one => text[one.range.start..one.range.end]}, ["@B"])
        @Expect(result.size, 1)
    }
    @TestCase
    func invalidExpressionOutputReportsItsParseErrorsAtTheCall() {
        // arrange
        let (db, file) =
            expansionDatabase(
                #"
            package m
            import m.ms.*
            func f(): Unit { let x = @B(1) }
            "#
            )
        let output = "func local() {}"
        answer(db, file, "B", output, [MappedSpan(TextRange(0, output.size), SpanOrigin.FromCall)])
        let text = file.text(db).toString()

        // act
        let result = diagnostics(db, file.fileId(db))

        // assert
        @Expect(!result.isEmpty())
        @Expect(result.all {one => one.message.startsWith("macro expansion:")})
        @Expect(result.all {one => text[one.range.start..one.range.end] == "@B"})
    }

    @TestCase
    func aGeneratedLocalUsedAfterTheCallNavigatesToTheCallInSource() {
        // arrange
        let (db, file) =
            expansionDatabase(
                #"
            package m
            import m.ms.*
            func f(): Unit {
                @B(1)
                let result = made
            }
            "#
            )
        let output = "let made = 1"
        answer(db, file, "B", output, [MappedSpan(TextRange(0, output.size), SpanOrigin.FromCall)])
        let text = file.text(db).toString()

        // act
        let targets = definitionAt(db, file.fileId(db), offsetIn(text, "made"))

        // assert
        @Expect(targets.size, 1)
        @Expect(targets[0].expansion.isNone())
        @Expect(text[targets[0].focusRange.start..targets[0].focusRange.end], "@B")
    }
}

@Test
class PackageHeaderDiagnosticsTest {
    @TestCase
    func aNonMacroHeaderInAMacroPackageIsAnError() {
        checkDiagnostics(
            #"
            //- /a.cj module=m package=m
            macro package m
            //- /b.cj module=m package=m
              package m
            //^^^^^^^ error: package name with macro should be consistent in the same package.
            "#
        )
    }

    @TestCase
    func aMacroHeaderInAnOrdinaryPackageIsAnError() {
        checkDiagnostics(
            #"
            //- /main.cj module=m package=m
            package m
            main() {}
            //- /tmp.cj module=m package=m
              macro package m
            //^^^^^ error: package name with macro should be consistent in the same package.
            "#
        )
    }

    @TestCase
    func libraryHeadersAreComparedInPathOrderRatherThanLoadOrder() {
        checkDiagnostics(
            #"
            //- /b.cj module=m package=m
              macro package m
            //^^^^^ error: package name with macro should be consistent in the same package.
            //- /a.cj module=m package=m
            package m
            public func value(): Int64 { 1 }
            "#
        )
    }

    @TestCase
    func consistentHeadersHaveNoError() {
        checkDiagnostics(
            #"
            //- /a.cj module=m package=m
            macro package m
            //- /b.cj module=m package=m
            macro package m
            //- /other.cj module=m package=m.other
            package m.other
            "#
        )
    }

    @TestCase
    func aHeaderEditUpdatesTheOtherFilesDiagnostic() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /a.cj module=m package=m
            package m
            //- /b.cj module=m package=m
            package m
            "#
                )
        let db = fixture.database()
        let first = fixture.file("/a.cj").fileId
        let second = fixture.file("/b.cj").fileId

        // act
        let before = diagnostics(db, second)

        // assert
        @Expect(before.isEmpty())

        // act: the first file sets the expected header kind
        db.setFileText(first, Rope("macro package m"))
        let inconsistent = diagnostics(db, second)

        // assert
        @Expect(inconsistent.map {one => one.message},
            ["package name with macro should be consistent in the same package."])

        // act: restoring the header clears the cached diagnostic
        db.setFileText(first, Rope("package m"))
        let restored = diagnostics(db, second)

        // assert
        @Expect(restored.isEmpty())

        // act: a later macro header must not change the first file's diagnostic
        db.setFileText(second, Rope("macro package m"))
        let firstErrors = diagnostics(db, first)
        let secondErrors = diagnostics(db, second)

        // assert
        @Expect(firstErrors.isEmpty())
        @Expect(secondErrors.map {one => one.message},
            ["package name with macro should be consistent in the same package."])

        // act: removing the first header makes the later macro header the reference
        db.setFileText(first, Rope(""))
        let afterRemoval = diagnostics(db, second)

        // assert
        @Expect(afterRemoval.isEmpty())

        // act: restoring an earlier ordinary header changes the reference again
        db.setFileText(first, Rope("package m"))
        let afterRestore = diagnostics(db, second)

        // assert
        @Expect(afterRestore.map {one => one.message},
            ["package name with macro should be consistent in the same package."])
    }

    @TestCase
    func explicitPackageMetadataTakesPrecedenceOverHeaders() {
        // arrange
        let fixture = Fixture.parse("//- /main.cj module=m package=m\npackage m")
        let db = fixture.database()
        let id = fixture.files[0].fileId
        let file =
            db.sourceFile(id) ?? throw IllegalStateException("the fixture file was not loaded")
        let pkg =
            packageOfFile(db, file) ??
                throw IllegalStateException("the fixture file has no package")

        // act: metadata requires a macro header despite ordinary headers in the files
        pkg.setIsMacro(db).to(Some(true))
        let missingMacro = diagnostics(db, id)

        // assert
        @Expect(missingMacro.map {one => one.message},
            ["file in macro package 'm' must declare 'macro package'"])

        // act: metadata forbids a macro header despite a macro header in the file
        pkg.setIsMacro(db).to(Some(false))
        db.setFileText(id, Rope("macro package m"))
        let unexpectedMacro = diagnostics(db, id)

        // assert
        @Expect(unexpectedMacro.map {one => one.message},
            ["file in ordinary package 'm' must not declare 'macro package'"])
        @Expect(unexpectedMacro[0].range, TextRange(0, 5))
    }
}
