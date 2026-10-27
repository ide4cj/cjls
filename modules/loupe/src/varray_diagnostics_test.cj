package loupe

import std.unittest.*
import std.unittest.testmacro.*

@Test
class VArrayConstructorDiagnosticsTest {
    @TestCase
    func validConstructorFormsHaveNoDiagnostics() {
        checkDiagnostics(
            #"
            package m
            type Pair = VArray<Int8, $2>
            func element(i: Int64): Int8 { Int8(i) }
            func choose(a: Pair): Int8 { a[0] }
            func choose(a: VArray<Int64, $2>): Int64 { a[0] }
            func test(): Unit {
                let a = VArray<Int8, $2>(repeat: 1)
                let b = VArray<Int8, $2>({ i => Int8(i) })
                let c = VArray<Int8, $2> { i => Int8(i) }
                let d = VArray<Int8, $2>() { i => Int8(i) }
                let e = VArray<Int8, $2>(element)
                let f = Pair(repeat: 1)
                let g = Pair { i => 1 }
                let h: ?Pair = Pair(repeat: 1)
                let zero = VArray<Int8, $ 0>(repeat: 1)
                let picked = choose(Pair { i => 1 })
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func repeatAndInitializerArgumentsAreCheckedAgainstTheirParameters() {
        checkDiagnostics(
            #"
            package m
            type Pair = VArray<Int8, $2>
            func test(s: String): Unit {
                let a = VArray<Int8, $2>(repeat: s)
            //                                   ^ error: mismatched types: expected 'Int8', found 'String'
                let b = Pair(repeat: s)
            //                       ^ error: mismatched types: expected 'Int8', found 'String'
                let c = VArray<Int8, $2>({ i => s })
            //                                  ^ error: mismatched types: expected 'Int8', found 'String'
                let d = Pair { i => s }
            //                      ^ error: mismatched types: expected 'Int8', found 'String'
                let e = VArray<Int8, $2>({ i: Int8 => i })
            //                           ^^^^^^^^^^^^^^^^ error: mismatched types: expected '(Int64) -> Int8', found '(Int8) -> Int8'
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func constructorArgumentsHaveTheRequiredCountAndNames() {
        checkDiagnostics(
            #"
            package m
            type Pair = VArray<Int8, $2>
            func test(): Unit {
                let a = VArray<Int8, $2>()
            //                          ^^ error: missing argument for parameter list '((Int64) -> Int8)' in call: expected 1 argument, found 0
                let b = Pair(repeat: 1, extra: 2)
            //              ^^^^^^^^^^^^^^^^^^^^^ error: extra argument given for parameter list '(Int8)' in call: expected 1 argument, found 2
                let c = VArray<Int8, $2>(item: 1)
            //                           ^^^^^^^ error: unknown named argument prefix 'item:'
                let d = Pair(item: 1)
            //               ^^^^^^^ error: unknown named argument prefix 'item:'
                let e = VArray<Int8, $2>(repeat: 1) { i => 1 }
            //                          ^^^^^^^^^^^^^^^^^^^^^^ error: extra argument given for parameter list '(Int8)' in call: expected 1 argument, found 2
            }
            "#,
            binaries: ["std.core"]
        )
    }
}
