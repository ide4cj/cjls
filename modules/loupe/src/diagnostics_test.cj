package loupe

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import rope.Rope
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase
import loupe.fixture.*

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
        checkDiagnostics(#"
            class A {
            //       | error: expected '}'
            "#)
    }

    @TestCase
    func eachFileHasItsOwn() {
        checkDiagnostics(#"
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
            "#)
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
        checkDiagnostics(#"
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
            "#)
    }
}

/**
 * What inference finds wrong, reported as cjc does (#48's 8c′b): a mismatch and a count of
 * arguments, between types known wholly. Each case compiled with cjc 1.3.0-alpha.20261002 first.
 */
@Test
class InferenceDiagnosticsTest {
    @TestCase
    func aValueOfAnotherTypeThanTheOneExpectedIsAMismatch() {
        checkDiagnostics(#"
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
            "#, binaries: ["std.core"])
    }

    @TestCase
    func anIntegerLiteralWhereNoNumberIsExpectedCannotBeConverted() {
        checkDiagnostics(#"
            package m
            class C { func m(x: Bool): Unit {} }
            func f(a: Int64, b: String): Unit {}
            func g(): Unit {
                f(1, 2)
            //       ^ error: cannot convert an integer literal to type 'String'
                C().m(1)
            //        ^ error: cannot convert an integer literal to type 'Bool'
            }
            "#, binaries: ["std.core"])
    }

    @TestCase
    func tooFewOrTooManyArgumentsOfOneFunctionAreReportedOverTheArguments() {
        checkDiagnostics(#"
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
            "#, binaries: ["std.core"])
    }

    @TestCase
    func whatCjcAcceptsIsNoError() {
        checkDiagnostics(#"
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
            "#, binaries: ["std.core"])
    }

    @TestCase
    func whatTheGateOfStdsSourcesFoundIsNoError() {
        checkDiagnostics(#"
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
            "#, binaries: ["std.core"])
    }

    @TestCase
    func nothingIsReportedAboutATypeNotKnown() {
        checkDiagnostics(#"
            package m
            func f(a: Int64): Unit {}
            func g(): Unit {
                let x: Int64 = nope
                f(nope)
                f(missing())
                let y: Nope = 1
            }
            "#, binaries: ["std.core"])
    }

    @TestCase
    func aFileOfNoPackageCallsAVariadicFunctionOfStdCoreWithItsArraysElements() {
        // arrange - a project with the SDK's std, and a file in none of its packages: one under
        // `target`, or above the root
        let fixture = Fixture.parse(#"
            //- /m/m.cj module=m package=m
            package m
            "#)
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let loose = FileId(fixture.files.size)
        db.setFileText(loose, Rope("func g(): Unit {\n    let d = Float64.max(1.0, 2.0)\n    let e = Float64.max(1.0, 2.0, 3.0, 4.0)\n}\n"))

        // act
        let result = diagnostics(db, loose).map {one => one.message}

        // assert - cjc: none, `others` taking any number of elements
        @Expect(result, Array<String>())
    }
}

/**
 * What the gate of std's sources found where cjc finds nothing (#287), each case of std's code
 * compiled with cjc 1.3.0-alpha.20261002 first; a name not known (`nope`) stands for a gap of the
 * analysis there (the variadic `max` of #254), which nothing around it is reported for.
 */
@Test
class StdFalseMismatchesTest {
    @TestCase
    func theDotsOfAForeignFunctionTakeAnyArgumentsMoreAfterItsParameters() {
        checkDiagnostics(#"
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
            "#, binaries: ["std.core"])
    }

    @TestCase
    func anOperandNotKnownLeavesTheLanguagesOperatorNotAnotherDeclared() {
        checkDiagnostics(#"
            package m
            extend Float64 {
                operator func +(arg: UInt8): Float64 { this }
            }
            func g(a: Float64, b: Float64): Unit {
                let s = a + b * nope
            }
            "#, binaries: ["std.core"])
    }

    @TestCase
    func anArgumentNotKnownTakesNoneOfSeveralOverloads() {
        checkDiagnostics(#"
            package m
            func abs(x: Int64): Int64 { x }
            func abs(x: Float64): Float64 { x }
            func g(): Unit {
                let x = nope
                if (abs(x) > 0.5) {}
            }
            "#, binaries: ["std.core"])
    }

    @TestCase
    func thisCallsAPrimaryConstructorOfAParameterByNameWithItsDefault() {
        checkDiagnostics(#"
            package m
            class Configuration {}
            class Printer {
                Printer(isColored: Bool, isOther!: Bool = true) {}
                init(configuration: Configuration) {
                    this(!false)
                }
            }
            "#, binaries: ["std.core"])
    }
}
