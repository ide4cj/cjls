package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*

/**
 * A call's arguments matched to an overload's parameters in order and by name, a parameter by name
 * left out of a default value (#254, #240), a trailing lambda to the last parameter (#280), and the other gaps #48's step 8c′b's gate found on
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
                // of `trimStart(set: Array<Rune>)` among its three overloads, its elements packed (N155)
                let t = s.trimStart(r'a', r'b')
            //      ^ String
                // the same one, of one element
                let u = s.trimStart(r'a')
            //      ^ String
            }
            "#)
    }

    @TestCase
    func argumentsGoToTheirParametersByPlaceAndByNameBeforeACandidateIsTried() {
        checkInference(#"
            package m
            class T {
                init(words!: Array<Int64>) {}
            //       ^^^^^ Array<Int64>
                init(kinds: Array<String>) {}
            //       ^^^^^ Array<String>
            }
            func w(a: Int64, b!: Int64): Int64 { a }
            //     ^ Int64
            //               ^ Int64
            func w(a: Int64, c!: Int64): String { "" }
            //     ^ Int64
            //               ^ Int64
            func k(a: Int64, h!: (Int64) -> Int64): Int64 { a }
            //     ^ Int64
            //               ^ (Int64) -> Int64
            func k(a: String): String { a }
            //     ^ String
            func test(): Unit {
                let t1 = T(words: [])
            //      ^^ T
                // two of the same types but other names are two overloads, not an override
                let w1 = w(1, c: 2)
            //      ^^ String
                // a trailing lambda is passed by the name of the last parameter
                let k1 = k(1) { x => x }
            //      ^^ Int64
            //                  ^ Int64
            }
            "#)
    }

    @TestCase
    func aTrailingLambdaGoesToANamedLastParameterPastOnesOfADefaultValue() {
        checkInference(#"
            package m
            func withConfig<T>(a: String, m!: ?String = None, body!: (String, Int64) -> T): T {
            //                 ^ String
            //                            ^ Option<String>
            //                                                ^^^^ (String, Int64) -> T
                body(a + (m ?? ""), a.size)
            }
            func f(): Unit {
                // `m` left out of its default value (#280)
                let r = withConfig("x") { s, n => s.size + n }
            //      ^ Int64
            //                            ^ String
            //                               ^ Int64
                let q = withConfig("x", m: "y") { s, _ => s }
            //      ^ String
            //                                    ^ String
            }
            "#)
    }

    @TestCase
    func aVariadicParameterTakesTheTailOnlyIfNoCandidateTakesTheArgumentsAsTheyAre() {
        checkInference(#"
            package m
            func v(a: Int64, xs: Array<Int64>): Int64 { a }
            //     ^ Int64
            //               ^^ Array<Int64>
            func v(a: String): String { a }
            //     ^ String
            func u(a: Int64, xs: Array<Int64>): Int64 { a }
            //     ^ Int64
            //               ^^ Array<Int64>
            func u(a: Int64): String { "" }
            //     ^ Int64
            func e(a: Int64, xs: Array<Int64>): Int64 { a }
            //     ^ Int64
            //               ^^ Array<Int64>
            func e(a: Int64, b: Int64, c: Int64): String { "" }
            //     ^ Int64
            //               ^ Int64
            //                         ^ Int64
            func h(xs: Array<Int64>, n!: Int64 = 1): Int64 { 1 }
            //     ^^ Array<Int64>
            //                       ^ Int64
            func k(xs: Array<Int64>): Int64 { 1 }
            //     ^^ Array<Int64>
            func k(x: Int64): String { "" }
            //     ^ Int64
            func mx<T>(a: T, others: Array<T>): T { a }
            //         ^ T
            //               ^^^^^^ Array<T>
            func test(arr: Array<Int64>): Unit {
            //        ^^^ Array<Int64>
                let v1 = v(1, 2, 3)
            //      ^^ Int64
                let v2 = v(1)
            //      ^^ Int64
                let v3 = v(1, arr)
            //      ^^ Int64
                // of no elements, and of three: one that takes them as they are first
                let u1 = u(1)
            //      ^^ String
                let e1 = e(1, 2, 3)
            //      ^^ String
                let u2 = u(1, [2])
            //      ^^ Int64
                // a parameter by name after the variadic one
                let h1 = h(1, 2, n: 3)
            //      ^^ Int64
                let h2 = h(n: 3)
            //      ^^ Int64
                let k1 = k(1)
            //      ^^ String
                let m1 = mx(1, 2, 3)
            //      ^^ Int64
            }
            "#)
    }

    @TestCase
    func aParameterOfADefaultValueLeftOutGivesACandidateNoPriority() {
        checkInference(#"
            package m
            func d(a: Int64, b!: Int64 = 0): Int64 { a }
            //     ^ Int64
            //               ^ Int64
            func d(a: Int64): String { "" }
            //     ^ Int64
            func test(): Unit {
                // cjc: ambiguous match for function call 'd'
                let d1 = d(1)
            //      ^^ {unknown}
                let d2 = d(1, b: 2)
            //      ^^ Int64
            }
            "#)
    }

    @TestCase
    func aLambdaGoesToACandidateWhoseParameterThereIsAFunctionFirst() {
        checkInference(#"
            package m
            struct Lazy<T> {
                init(value: T) {}
            //       ^^^^^ T
                init(fun: () -> ?T) {}
            //       ^^^ () -> Option<T>
                init() {}
            }
            func test(): Unit {
                // a trailing lambda only to a last parameter of a function type
                let a = Lazy { 1 }
            //      ^ Lazy<Int64>
                let b = Array<Int64>(3) {i => i}
            //      ^ Array<Int64>
            //                           ^ Int64
            }
            "#)
    }

    @TestCase
    func aLocalFunctionTakesItsParametersByTheirNames() {
        checkInference(#"
            package m
            func test(): Unit {
                func g(a: Int64, b!: Int64 = 0): Int64 { a + b }
            //       ^ (Int64, Int64) -> Int64
            //         ^ Int64
            //                   ^ Int64
                let x = g(1, b: 2)
            //      ^ Int64
                let y = g(1)
            //      ^ Int64
            }
            "#)
    }

    @TestCase
    func aLambdaArgumentExcludesTheCandidatesOfFewerParametersAndMismatchesThoseOfNoFunction() {
        checkInference(#"
            package m
            func k(f: () -> Int64): Int64 { f() }
            //     ^ () -> Int64
            func k(f: () -> Int64, n: Int64): String { "" }
            //     ^ () -> Int64
            //                     ^ Int64
            func k(n!: Int64): Bool { true }
            //     ^ Int64
            func f(): Unit {
                // the first takes one argument: excluded; the third's `n` is no function: mismatched
                let a = k({ => 1 }, 2)
            //      ^ String
                let b = k({ => 1 })
            //      ^ Int64
                // by name: the candidate without a `g` is mismatched
                let c = j(g: { => 1 })
            //      ^ String
            }
            func j(f!: () -> Int64): Int64 { f() }
            //     ^ () -> Int64
            func j(g!: () -> Int64): String { "" }
            //     ^ () -> Int64
            "#)
    }
}
