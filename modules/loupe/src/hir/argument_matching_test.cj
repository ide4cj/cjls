package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*

/**
 * A call's arguments matched to an overload's parameters in order and by name, a parameter by name
 * left out of a default value (#254, #240), and the other gaps #48's step 8c′b's gate found on
 * std's sources (#277, #249). Each case checked on cjc 1.3.0-alpha.20261002 first.
 */
@Test
class ArgumentMatchingTest {
    @TestCase
    func aNamedArgumentIsInferredAgainstItsParameter() {
        checkInference(#"
            package m
            class P { let name = 1 }
            //            ^^^^ Int64
            func gen<T>(x!: T): T { x }
            //          ^ T
            func sortBy<T>(xs: Array<T>, by!: (T, T) -> Bool): Unit {}
            //             ^^ Array<T>
            //                           ^^ (T, T) -> Bool
            func apply(f!: (Int64) -> Int64): Int64 { f(1) }
            //         ^ (Int64) -> Int64
            func small(x!: Int8): Int8 { x }
            //         ^ Int8
            func g(ps: Array<P>): Unit {
            //     ^^ Array<P>
                let b = gen(x: 1u8)
            //      ^ UInt8
                let c = apply(f: {y => y + 1})
            //      ^ Int64
            //                    ^ Int64
                sortBy(ps, by: {a, b => a.name < b.name})
            //                  ^ P
            //                     ^ P
                let a = small(x: 1)
            //      ^ Int8
            }
            "#)
    }

    @TestCase
    func anOverloadIsTakenByNamesAndDefaultValues() {
        checkInference(#"
            package m
            import std.collection.ArrayList
            class C {
                func r(at!: Int64): Int64 { at }
            //         ^^ Int64
                func r(range: Range<Int64>): Unit {}
            //         ^^^^^ Range<Int64>
            }
            func s(a: Int64, b!: Int64 = 0): Int64 { a + b }
            //     ^ Int64
            //               ^ Int64
            func s(a: String): String { a }
            //     ^ String
            func test(c: C): Unit {
            //        ^ C
                let r1 = c.r(at: 1)
            //      ^^ Int64
                let s1 = s(1)
            //      ^^ Int64
                let l = ArrayList<String>()
            //      ^ ArrayList<String>
                let added = l.add("a")
            //      ^^^^^ Unit
            }
            "#)
    }

    @TestCase
    func anExtendOfAnAliasExtendsTheTypeItExpandsTo() {
        checkInference(#"
            package m
            type Small = Int16
            extend Small {
                func twice(): Int16 { this * 2 }
            }
            func f(): Unit {
                let n: Int16 = 21
            //      ^ Int16
                let t = n.twice()
            //      ^ Int16
            }
            "#)
    }

    @TestCase
    func branchesOfAnOptionAndOfItsArgumentAreJoinedIntoTheOption() {
        // #249
        checkInference(#"
            package m
            class C { var b = 1 }
            //            ^ Int64
            func test(c: Bool, o: ?Int64, a: ?C): Unit {
            //        ^ Bool
            //                 ^ Option<Int64>
            //                            ^ Option<C>
                let j1 = if (c) { o } else { 1 }
            //      ^^ Option<Int64>
                let j2 = if (c) { a?.b } else { 1 }
            //      ^^ Option<Int64>
                let j3 = if (c) { 1 } else { o }
            //      ^^ Option<Int64>
            }
            "#)
    }

    @TestCase
    func aForeignFunctionIsACFuncAsAValue() {
        checkInference(#"
            package m
            foreign func abs(x: Int32): Int32
            //               ^ Int32
            func g(o: ?Int64): Unit {
            //     ^ Option<Int64>
                let q = abs
            //      ^ CFunc<(Int32) -> Int32>
                let joined = if (true) { o } else { 1 }
            //      ^^^^^^ Option<Int64>
            }
            "#)
    }

    @TestCase
    func aVariadicFunctionOfACjoTakesTheElementsOfItsArray() {
        checkInference(#"
            package m
            import std.collection.ArrayList
            func g(s: String): Unit {
            //     ^ String
                let a = String.fromUtf8(97u8, 98u8)
            //      ^ String
                let b = String.fromUtf8()
            //      ^ String
                let c = String.fromUtf8([97u8])
            //      ^ String
                let d = Float64.max(1.0, 2.0)
            //      ^ Float64
                let e = Float64.max(1.0, 2.0, 3.0, 4.0)
            //      ^ Float64
                // cjc: ArrayList<Int64>, its type argument solved from the elements
                let f = ArrayList.of(1, 2, 3)
            //      ^ ArrayList<{unknown}>
                let h = ArrayList<Int64>.of()
            //      ^ ArrayList<Int64>
                // cjc: String, of `trimStart(set: Array<Rune>)` among its three overloads (#254)
                let t = s.trimStart(r'a', r'b')
            //      ^ {unknown}
                // cjc: String, the same one
                let u = s.trimStart(r'a')
            //      ^ {unknown}
            }
            "#)
    }
}
