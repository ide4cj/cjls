package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

@Test
class VArrayConstructorsTest {
    @TestCase
    func directConstructorsGiveTheirInitializerItsExpectedType() {
        checkInference(
            #"
            package m
            func element(i: Int64): Int8 { Int8(i) }
            //           ^ Int64
            func test(): Unit {
                let a = VArray<Int8, $2>(repeat: 1)
            //      ^ VArray<Int8, $2>
                let b = VArray<Int8, $2>({ i => Int8(i) })
            //      ^ VArray<Int8, $2>
            //                             ^ Int64
                let c = VArray<Int8, $2> { i => Int8(i) }
            //      ^ VArray<Int8, $2>
            //                             ^ Int64
                let d = VArray<Int8, $2>() { i => Int8(i) }
            //      ^ VArray<Int8, $2>
            //                               ^ Int64
                let e = VArray<Int8, $2>(element)
            //      ^ VArray<Int8, $2>
            }
            "#
        )
    }

    @TestCase
    func aliasesConstructTheExpandedType() {
        checkInference(
            #"
            package m
            type Pair = VArray<Int8, $2>
            type Other = Pair
            func test(): Unit {
                let a = Pair(repeat: 1)
            //      ^ VArray<Int8, $2>
                let b = Pair { i => Int8(i) }
            //      ^ VArray<Int8, $2>
            //                 ^ Int64
                let c = Other({ i => 1 })
            //      ^ VArray<Int8, $2>
            //                  ^ Int64
                let d: ?Pair = Other(repeat: 1)
            //      ^ Option<VArray<Int8, $2>>
            }
            "#
        )
    }

    @TestCase
    func qualifiedAliasesResolveWhileALocalValueKeepsItsOwnCallSignature() {
        checkInference(
            #"
            //- /types.cj module=m package=m.types
            package m.types
            public type Pair = VArray<Int8, $2>
            //- /main.cj module=m package=m
            package m
            import m.types
            import m.types.Pair as Two
            func test(): Unit {
                let a = types.Pair(repeat: 1)
            //      ^ VArray<Int8, $2>
                let b = Two { i => Int8(i) }
            //      ^ VArray<Int8, $2>
            //                ^ Int64
                let Two = { i: Int64 => i }
            //      ^^^ (Int64) -> Int64
            //              ^ Int64
                let c = Two(1)
            //      ^ Int64
            }
            "#
        )
    }

    @TestCase
    func aConstructorKeepsItsTypeWhileOuterOverloadsAreTried() {
        checkInference(
            #"
            package m
            type Pair = VArray<Int8, $2>
            func choose(a: Pair): Int8 { a[0] }
            //          ^ VArray<Int8, $2>
            func choose(a: VArray<Int64, $2>): Int64 { a[0] }
            //          ^ VArray<Int64, $2>
            func test(): Unit {
                let picked = choose(Pair { i => 1 })
            //      ^^^^^^ Int8
            //                             ^ Int64
            }
            "#
        )
    }
}
