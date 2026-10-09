package loupe.hir

import std.collection.*
import std.sync.AtomicInt64
import std.unittest.*
import std.unittest.testmacro.*
import calca.*
import calca.macros.*
import cjsyntax.CjSyntaxNode
import cjsyntax.ast.AnyHasName
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.fixture.*
import loupe.syntax.parse
import rope.Rope

/**
 * Checks the types inference gives the bodies of `fixture` are its annotations: `//^ Int64` under
 * the name of each local, and of each function or variable whose type its signature does not
 * write. `std.core` and `std.collection` are packages of the project.
 */
func checkInference(fixture: String): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core")),
        stdCjoRead("std.collection", stdCjo("std.collection"))])
    let actual = ArrayList<Annotation>()
    for (file in parsed.files) {
        let source = db.sourceFile(file.fileId).getOrThrow()
        let root = parse(db, source).syntaxNode()
        for (item in itemTree(db, source).items) {
            annotateTypes(db, source, root, item, actual)
        }
    }
    expectAnnotations(fixture, actual.toArray())
}

/**
 * Adds the annotations of the body of `item`, and of its members', to `actual`.
 */
func annotateTypes(db: AnalysisDatabase, source: SourceFile, root: CjSyntaxNode, item: Item,
    actual: ArrayList<Annotation>): Unit {
    let fileId = source.fileId(db)
    let def = DefId(db, ItemFile.Source(source), item.id)
    match (item.kind) {
        case Func | Main | Var | Prop | Init | PrimaryInit =>
            let isUnwritten = signatureTypes(db, def).ty.isNone() && item.kind != ItemKind.Init &&
                item.kind != ItemKind.PrimaryInit
            if (isUnwritten && let Some(node) <- itemIdMap(db, source).node(item.id, root) &&
                let Some(name) <- AnyHasName.cast(node).flatMap {it => it.name()}) {
                actual.add(Annotation(fileId, name.syntax.textRange, declaredTyOf(db, def).text(db)))
            }
            let lowered = bodyWithSourceMap(db, def)
            let result = inferBody(db, def)
            let pkg = packageOfFile(db, source).getOrThrow()
            for (i in 0..lowered.body.locals.size) {
                let local = lowered.body.locals[i]
                // a pattern's lone name of a constructor is none (N72)
                if (local.lone && !ctorsNamed(db, pkg, local.name).isEmpty()) {
                    continue
                }
                if (let Some(Some(ptr)) <- lowered.sourceMap.locals.get(i) && let Some(node) <- ptr.tryToNode(root)) {
                    actual.add(Annotation(fileId, node.textRange, result.locals[i].text(db)))
                }
            }
        case _ => ()
    }
    for (member in item.members) {
        annotateTypes(db, source, root, member, actual)
    }
}

let inferenceReaderRuns = AtomicInt64(0)

/**
 * A query reading the inference of a body, as a hover will; it counts its runs.
 */
@CalcaTracked
func exprTyCount(db: AnalysisDatabase, def: DefId): Int64 {
    inferenceReaderRuns.fetchAdd(1)
    inferBody(db, def).exprs.size
}

/**
 * The types of the bodies (step 8b of #48, D55): each expression's synthesized, or checked against
 * the type expected of it; what cjc reports as an error, an error type. Each case compiled with cjc
 * 1.3.0-alpha.20260918 first: one of no `cjc:` comment compiles.
 */
@Test
class InferTest {
    @TestCase
    func aLiteralIsOfItsSuffixElseOfTheTypeExpectedElseInt64OrFloat64() {
        checkInference(#"
            package m
            func f(): Unit {
                let a = 1
            //      ^ Int64
                let b = 1.0
            //      ^ Float64
                let c: Int8 = 1
            //      ^ Int8
                let d = 1u8
            //      ^ UInt8
                let e = 0x10i16
            //      ^ Int16
                let g = 1.5f32
            //      ^ Float32
                let h = b'a'
            //      ^ UInt8
                let i = r'a'
            //      ^ Rune
                let j = true
            //      ^ Bool
                let k = "s${a}"
            //      ^ String
                let l = ()
            //      ^ Unit
                let m: ?UInt8 = 1
            //      ^ Option<UInt8>
                let n: Float32 = 1.0
            //      ^ Float32
            }
            "#)
    }

    @TestCase
    func anIntegerLiteralIsNoFloat() {
        checkInference(#"
            package m
            func f(): Unit {
                // cjc: cannot convert an integer literal to type 'Float64'
                let a: Float64 = 1
            //      ^ Float64
            }
            "#)
    }

    @TestCase
    func anOperatorOfTheLanguageTakesALiteralToTheTypeOfItsOtherSide() {
        checkInference(#"
            package m
            func f(a: Int64, c: Int8, g: Bool): Unit {
            //     ^ Int64
            //               ^ Int8
            //                        ^ Bool
                let q = 1 + 2
            //      ^ Int64
                let r = c + 1
            //      ^ Int8
                let s = 1 + c
            //      ^ Int8
                let t = a < 2
            //      ^ Bool
                let u = !g
            //      ^ Bool
                let v = -c
            //      ^ Int8
                let w = a is Int64
            //      ^ Bool
                let x = a as Int8
            //      ^ Option<Int8>
                let y = Int8(a)
            //      ^ Int8
                let z = g && a > 0
            //      ^ Bool
                let p = 2 ** 3
            //      ^ Int64
            }
            "#)
    }

    @TestCase
    func tuplesArraysAndRanges() {
        checkInference(#"
            package m
            func f(n: UInt8): Unit {
            //     ^ UInt8
                let a = (1, "a")
            //      ^ (Int64, String)
                let b = [1, 2]
            //      ^ Array<Int64>
                let c: Array<UInt8> = [1, 2]
            //      ^ Array<UInt8>
                let d = 0..10
            //      ^ Range<Int64>
                let e = 0..n
            //      ^ Range<UInt8>
                let g = (1, "s")[1]
            //      ^ String
                let h: (Int8, Float32) = (1, 2.0)
            //      ^ (Int8, Float32)
            }
            "#)
    }

    @TestCase
    func theBranchesOfAnIfOrAMatchAreJoined() {
        checkInference(#"
            package m
            open class Base {}
            class A <: Base {}
            class B <: Base {}
            func f(c: Bool, o: ?Int64): Unit {
            //     ^ Bool
            //              ^ Option<Int64>
                let a = if (c) { 1 } else { 2 }
            //      ^ Int64
                let b = if (c) { 1 }
            //      ^ Unit
                let d = if (c) { A() } else { B() }
            //      ^ Base
                let e = if (c) { 1 } else { return }
            //      ^ Int64
                let g = match (o) {
            //      ^ Int64
                    case Some(v) => v
            //                ^ Int64
                    case None => 0
                }
                let h = match {
            //      ^ Int64
                    case c => 1
                    case _ => 2
                }
                let i = try { 1 } catch (_: Exception) { 2 }
            //      ^ Int64
                let j: ?Int64 = if (c) { 1 } else { None }
            //      ^ Option<Int64>
                let k: Base = if (c) { A() } else { B() }
            //      ^ Base
            }
            "#)
    }

    @TestCase
    func branchesOfNoOneLeastCommonSupertypeAreAnError() {
        checkInference(#"
            package m
            interface I {}
            class C <: I {}
            class D <: I {}
            func f(c: Bool): Unit {
            //     ^ Bool
                // cjc: types Class-C and Class-D of the two branches of this 'if' expression mismatch
                let a = if (c) { C() } else { D() }
            //      ^ {unknown}
                // cjc: types Int64 and UInt8 of the two branches of this 'if' expression mismatch
                let b = if (c) { 1 } else { 2u8 }
            //      ^ {unknown}
                // cjc: inconsistent element type for array literal
                let d = [1, 2u8]
            //      ^ Array<{unknown}>
            }
            "#)
    }

    @TestCase
    func aCycleOfSupertypesGrowingTheirArgumentsEnds() {
        checkInference(#"
            package m
            // cjc: inheritance cycle detected: 'A->B->A'
            open class A<T> <: B<A<T>> {}
            open class B<T> <: A<B<T>> {}
            func f(c: Bool, a: A<Int64>, b: B<Int64>): Unit {
            //     ^ Bool
            //              ^ A<Int64>
            //                           ^ B<Int64>
                let x = if (c) { a } else { b }
            //      ^ {unknown}
            }
            "#)
    }

    @TestCase
    func whatJumpsIsNothingAndALoopOrAnAssignmentUnit() {
        checkInference(#"
            package m
            func f(c: Bool): Unit {
            //     ^ Bool
                var n = 0
            //      ^ Int64
                let a = while (c) {}
            //      ^ Unit
                let b = (n = 2)
            //      ^ Unit
                let d = throw Exception()
            //      ^ Nothing
                let e = do { n++ } while (c)
            //      ^ Unit
            }
            "#)
    }

    @TestCase
    func aTypeNotWrittenIsInferredFromTheBody() {
        checkInference(#"
            package m
            func noRet() { 1 }
            //   ^^^^^ Int64
            func noRetUnit() { let x = 1 }
            //   ^^^^^^^^^ Unit
            //                     ^ Int64
            func returns(c: Bool) {
            //   ^^^^^^^ Int64
            //           ^ Bool
                if (c) {
                    return 1
                }
                2
            }
            func onlyReturns() { return "s" }
            //   ^^^^^^^^^^^ String
            let global = noRet()
            //  ^^^^^^ Int64
            var later = returns(true)
            //  ^^^^^ Int64
            func f(): Unit {
                let a = noRet()
            //      ^ Int64
                let b = global
            //      ^ Int64
                let c = noRetUnit()
            //      ^ Unit
                func inner() { 1.0 }
            //       ^^^^^ () -> Float64
                let d = inner()
            //      ^ Float64
            }
            "#)
    }

    @TestCase
    func aFunctionCallingItselfOfNoReturnTypeIsAnError() {
        checkInference(#"
            package m
            // cjc: unable to infer return type, please add type annotation (twice: here and at the call)
            func rec(n: Int64) { if (n == 0) { 0 } else { rec(n - 1) } }
            //   ^^^ {unknown}
            //       ^ Int64
            // cjc: the same, at `ping` and at its call in `pong`
            func ping() { pong() }
            //   ^^^^ {unknown}
            func pong() { ping() }
            //   ^^^^ {unknown}
            func f(): Unit {
                let a = rec(1)
            //      ^ {unknown}
                let b = ping()
            //      ^ {unknown}
            }
            "#)
    }

    @TestCase
    func aMemberOfAValueIsLookedUpFromItsType() {
        checkInference(#"
            package m
            import std.collection.*
            open class Base {
                public func me(): This { this }
                public var count = 0
            //             ^^^^^ Int64
            }
            class A <: Base {
                func sup() { super.count }
            //       ^^^ Int64
                func self() { this }
            //       ^^^^ A
            }
            struct P {
                let x = 1
            //      ^ Int64
                func me() { this }
            //       ^^ P
            }
            class K {
                prop p: Int64 {
                    get() { 1 }
                }
            }
            func f(list: ArrayList<Int64>): Unit {
            //     ^^^^ ArrayList<Int64>
                let a = A().me()
            //      ^ A
                let b = A().sup()
            //      ^ Int64
                let c = A().self()
            //      ^ A
                let d = P().x
            //      ^ Int64
                let e = P().me()
            //      ^ P
                let g = K().p
            //      ^ Int64
                let h = list.size
            //      ^ Int64
                let i = list.get(0)
            //      ^ Option<Int64>
                let j = A().count
            //      ^ Int64
            }
            "#)
    }

    @TestCase
    func aMemberOfAGenericTypeIsSeenWithItsArguments() {
        checkInference(#"
            package m
            open class Box<T> {
                public Box(public let value: T) {}
            //                        ^^^^^ T
                public func get(): T { value }
            }
            class IntBoxes <: Box<Array<Int64>> {
                init() { super([]) }
                func first() { value }
            //       ^^^^^ Array<Int64>
            }
            extend<T> Box<T> {
                public func pair(): (T, T) { (value, value) }
            }
            extend Box<Int64> {
                public func plusOne(): Int64 { value + 1 }
            }
            func f(ib: IntBoxes, bi: Box<Int64>): Unit {
            //     ^^ IntBoxes
            //                   ^^ Box<Int64>
                let a = ib.get()
            //      ^ Array<Int64>
                let b = ib.pair()
            //      ^ (Array<Int64>, Array<Int64>)
                let c = bi.plusOne()
            //      ^ Int64
                let d = ib.value
            //      ^ Array<Int64>
                let e = Box<String>("s").get()
            //      ^ String
                let g = bi.pair()
            //      ^ (Int64, Int64)
            }
            "#)
    }

    @TestCase
    func anExtendOfAnotherInstanceIsNotTheValuesMember() {
        checkInference(#"
            package m
            class Box<T> {}
            extend Box<Int64> {
                func only(): Int64 { 1 }
            }
            func f(b: Box<String>): Unit {
            //     ^ Box<String>
                // cjc: 'only' is not a member of class 'Box<String>'
                let a = b.only()
            //      ^ {unknown}
            }
            "#)
    }

    @TestCase
    func aMemberOfATypeOfTheLanguageIsItsExtends() {
        checkInference(#"
            package m
            extend Int64 {
                func twice() { this * 2 }
            //       ^^^^^ Int64
            }
            func f(): Unit {
                let a = 3.twice()
            //      ^ Int64
                let b = Int64.Max
            //      ^ Int64
            }
            "#)
    }

    @TestCase
    func aLambdaTakesItsParametersFromTheFunctionTypeExpected() {
        checkInference(#"
            package m
            func takes(f: (Int64, String) -> Bool): Unit {}
            //         ^ (Int64, String) -> Bool
            func f(): Unit {
                let a = {x: Int64 => x + 1}
            //      ^ (Int64) -> Int64
            //           ^ Int64
                let b: (Int64) -> Int64 = {x => x}
            //      ^ (Int64) -> Int64
            //                             ^ Int64
                let c = { => 1 }
            //      ^ () -> Int64
                let d = {x: Int64 => if (x > 0) { return 1 }; 2}
            //      ^ (Int64) -> Int64
            //           ^ Int64
                takes({p, q => p > 0 && q.size > 0})
            //         ^ Int64
            //            ^ String
                let e = spawn { 1 }
            //      ^ Future<Int64>
            }
            "#)
    }

    @TestCase
    func aPatternBindsThePartsOfTheTypeItMatches() {
        checkInference(#"
            package m
            enum E { | A(Int64) | B }
            func f(arr: Array<String>, o: ?Int64, e: E): Unit {
            //     ^^^ Array<String>
            //                         ^ Option<Int64>
            //                                    ^ E
                for (s in arr) {}
            //       ^ String
                for (i in 0..10) {}
            //       ^ Int64
                for ((y, z) in [(1, true)]) {}
            //        ^ Int64
            //           ^ Bool
                if (let Some(v) <- o) {}
            //               ^ Int64
                let (y1, y2) = (1, "a")
            //       ^^ Int64
            //           ^^ String
                match (e) {
                    case A(n) => ()
            //             ^ Int64
                    case B => ()
                }
                match (o) {
                    case Some(w) => ()
            //                ^ Int64
                    case None => ()
                }
                try {
                    ()
                } catch (x: Exception) {
            //           ^ Exception
                    ()
                }
            }
            "#)
    }

    @TestCase
    func aConstructorIsOfItsTypeItsArgumentsWrittenOrExpected() {
        checkInference(#"
            package m
            enum E { | A(Int64) | B }
            class G<T> {}
            func f(): Unit {
                let a = E.A(1)
            //      ^ E
                let b = E.B
            //      ^ E
                let c: ?Int64 = None
            //      ^ Option<Int64>
                let d: Option<Int64> = Some(1)
            //      ^ Option<Int64>
                let e = G<Int64>()
            //      ^ G<Int64>
                let g: G<String> = G()
            //      ^ G<String>
            }
            "#)
    }

    @TestCase
    func aSetterTakesItsPropertysType() {
        checkInference(#"
            package m
            class K {
                mut prop q: String {
                    get() { "" }
                    set(v) {}
            //          ^ String
                }
            }
            "#)
    }

    @TestCase
    func aTypeArgumentNotWrittenIsTheJoinOfWhatIsPassed() {
        checkInference(#"
            package m
            open class Base {}
            class D1 <: Base {}
            class D2 <: Base {}
            class Box<T> {
                public Box(public let value: T) {}
            //                        ^^^^^ T
            }
            func gen<T>(a: T): T { a }
            //          ^ T
            func pair<T>(a: T, b: T): T { a }
            //           ^ T
            //                 ^ T
            func f(): Unit {
                let a = Box(1)
            //      ^ Box<Int64>
                let b = gen("s")
            //      ^ String
                let c = gen<Int8>(1)
            //      ^ Int8
                let d = Some(D1())
            //      ^ Option<D1>
                let e = pair(D1(), D2())
            //      ^ Base
                let g = pair(Box(D1()), Box(D2()))
            //      ^ Object
                let h = pair(D1(), Box(1))
            //      ^ Object
                let i = Box(Box(1))
            //      ^ Box<Box<Int64>>
                let k = Box(1).value
            //      ^ Int64
                let j = gen({x: Int64 => x})
            //      ^ (Int64) -> Int64
            //               ^ Int64
            }
            "#)
    }

    @TestCase
    func aLiteralPassedTakesTheTypeOfAnotherArgumentOrOfTheTypeExpected() {
        checkInference(#"
            package m
            class Box<T> {
                public Box(public let value: T) {}
            //                        ^^^^^ T
            }
            func gen<T>(a: T): T { a }
            //          ^ T
            func pair<T>(a: T, b: T): T { a }
            //           ^ T
            //                 ^ T
            func f(): Unit {
                let a = pair(1, 2u8)
            //      ^ UInt8
                let b = pair(-1, 2i16)
            //      ^ Int16
                let c = pair(1.0, 2.0f32)
            //      ^ Float32
                let d: Int8 = gen(1)
            //      ^ Int8
                let e: ?Int64 = gen(1)
            //      ^ Option<Int64>
                let g: Box<Int16> = Box(1)
            //      ^ Box<Int16>
                let h = gen(1)
            //      ^ Int64
            }
            "#)
    }

    @TestCase
    func aTypeArgumentIsTheTypeExpectedOrABoundWhenNothingIsPassed() {
        checkInference(#"
            package m
            open class Base {}
            class D1 <: Base {}
            class Box<T> {
                public Box(public let value: T) {}
            //                        ^^^^^ T
            }
            func none<T>(): Option<T> { None }
            func mk<T>(): Array<T> { [] }
            func mkb<T>(): Option<T> where T <: Base { None }
            func idb<T>(x: T): T where T <: Base { x }
            //          ^ T
            func gen<T>(a: T): T { a }
            //          ^ T
            func f(): Unit {
                let a: Array<Int64> = mk()
            //      ^ Array<Int64>
                let b: Option<String> = none()
            //      ^ Option<String>
                let c = mkb()
            //      ^ Option<Base>
                let d = idb(D1())
            //      ^ D1
                let e: Box<Base> = Box(D1())
            //      ^ Box<Base>
                let g: Base = gen(D1())
            //      ^ Base
            }
            "#)
    }

    @TestCase
    func aValueIsBoxedIntoTheOptionOfAParameter() {
        checkInference(#"
            package m
            open class Base {}
            class D1 <: Base {}
            func takeOpt<T>(o: ?T): T { o.getOrThrow() }
            //              ^ Option<T>
            func pair<T>(a: T, b: T): T { a }
            //           ^ T
            //                 ^ T
            func f(): Unit {
                let a = takeOpt(1)
            //      ^ Int64
                let b = takeOpt(Some(D1()))
            //      ^ D1
                let c = takeOpt(D1())
            //      ^ D1
                let d = pair(Some(1), None)
            //      ^ Option<Int64>
            }
            "#)
    }

    @TestCase
    func aLambdaWaitsForTheTypesOfItsParameters() {
        checkInference(#"
            package m
            class Box<T> {
                public Box(public let value: T) {}
            //                        ^^^^^ T
                public func map<R>(g: (T) -> R): Box<R> { Box(g(value)) }
            //                     ^ (T) -> R
            }
            func apply<T, R>(x: T, g: (T) -> R): R { g(x) }
            //               ^ T
            //                     ^ (T) -> R
            func first<T>(g: (T) -> Int64, x: T): Int64 { g(x) }
            //            ^ (T) -> Int64
            //                             ^ T
            func f(): Unit {
                let a = apply(1, {x => x.toString()})
            //      ^ String
            //                    ^ Int64
                let b = first({y => y + 1}, 2)
            //      ^ Int64
            //                 ^ Int64
                let c = Box(1).map({z => z > 0})
            //      ^ Box<Bool>
            //                      ^ Int64
                let d = apply("s", {w: String => w.size})
            //      ^ Int64
            //                      ^ String
            }
            "#)
    }

    @TestCase
    func anArgumentOfNoTypeAloneIsCheckedAgainstWhatTheOthersSolved() {
        checkInference(#"
            package m
            func none<T>(): Option<T> { None }
            func pair<T>(a: T, b: T): T { a }
            //           ^ T
            //                 ^ T
            func f(): Unit {
                let a = pair(none(), Some(1))
            //      ^ Option<Int64>
                let b = pair(None, Some("s"))
            //      ^ Option<String>
            }
            "#)
    }

    @TestCase
    func aTypeArgumentIsSolvedThroughTuplesSelfBoundsAndOtherParameters() {
        checkInference(#"
            package m
            open class Base {}
            class D1 <: Base {}
            func gen<T>(a: T): T { a }
            //          ^ T
            func fstOf<A, B>(p: (A, B)): A { p[0] }
            //               ^ (A, B)
            func maxOf<T>(a: T, b: T): T where T <: Comparable<T> { if (a > b) { a } else { b } }
            //            ^ T
            //                  ^ T
            func tag<T>(x: T, name: String): T { x }
            //          ^ T
            //                ^^^^ String
            func named<T>(x: T, n!: Int64): T { x }
            //            ^ T
            //                  ^ Int64
            func f(): Unit {
                let a = fstOf((1, "s"))
            //      ^ Int64
                let b = maxOf(1, 2)
            //      ^ Int64
                let c = maxOf("a", "b")
            //      ^ String
                let d = tag(1, "a")
            //      ^ Int64
                let e = named(1, n: 2)
            //      ^ Int64
                let g = gen(0x1p3)
            //      ^ Float64
                let h: ?Base = gen(D1())
            //      ^ Option<Base>
                // `Nothing`: cjc compiles `let _: Int64 = i`
                let i = gen(throw Exception())
            //      ^ Nothing
            }
            "#)
    }

    @TestCase
    func whatWaitsIsCheckedOnlyOnceItsParameterIsKnown() {
        checkInference(#"
            package m
            func none<T>(): Option<T> { None }
            func pair<T>(a: T, b: T): T { a }
            //           ^ T
            //                 ^ T
            func lam<T>(g: (T) -> Unit): Unit {}
            //          ^ (T) -> Unit
            func pick<T, R>(a: Option<T>, b: T, g: (T) -> R): R { g(b) }
            //              ^ Option<T>
            //                            ^ T
            //                                  ^ (T) -> R
            func f(): Unit {
                let a = pick(None, 1, {x => x.toString()})
            //      ^ String
            //                         ^ Int64
                // cjc: unable to infer generic argument of this function
                lam(
                    // cjc: parameters of this lambda expression must have type annotations
                    {y => ()})
            //       ^ {unknown}
                // cjc: unable to infer generic argument of this function
                let b = pair(none(), none())
            //      ^ {unknown}
            }
            "#)
    }

    @TestCase
    func aRecursiveCallSolvesItsTypeParameterAsItself() {
        checkInference(#"
            package m
            func rec<T>(x: T): T {
            //          ^ T
                let y = rec(x)
            //      ^ T
                y
            }
            "#)
    }

    @TestCase
    func whatNothingTellsOrNoTypeMeetsIsAnError() {
        checkInference(#"
            package m
            import std.collection.ArrayList
            func none<T>(): Option<T> { None }
            func pair<T>(a: T, b: T): T { a }
            //           ^ T
            //                 ^ T
            func f(): Unit {
                // cjc: unable to infer generic argument of this function
                let a = none()
            //      ^ Option<{unknown}>
                // cjc: unable to infer generic argument of this function
                let b = ArrayList()
            //      ^ ArrayList<{unknown}>
                b.add(1)
                // cjc: unable to infer generic argument of this function
                let c = pair(1, "s")
            //      ^ {unknown}
                // cjc: unable to infer generic argument of this function
                let d = pair(1, 2.0)
            //      ^ {unknown}
            }
            "#)
    }

    @TestCase
    func aCallTakesTheOverloadItsArgumentsFit() {
        // N115
        checkInference(#"
            package m
            func f(x: Int64): Int64 { x }
            //     ^ Int64
            func f(x: String): String { x }
            //     ^ String
            func f(x: Int64, y: Int64): Bool { true }
            //     ^ Int64
            //               ^ Int64
            func o(x: ?Int64): Int64 { 1 }
            //     ^ Option<Int64>
            func o(x: String): String { "" }
            //     ^ String
            func z<T>(a: T, b: T): T { a }
            //        ^ T
            //              ^ T
            func z(a: Int64, b: String): Bool { true }
            //     ^ Int64
            //               ^ String
            func test(): Unit {
                let a = f(1)
            //      ^ Int64
                let b = f("s")
            //      ^ String
                let c = f(1, 2)
            //      ^ Bool
                let d = o(1)
            //      ^ Int64
                // the generic one's `T` is no type both are
                let e = z(1, "s")
            //      ^ Bool
            }
            "#)
    }

    @TestCase
    func ofSeveralThatFitTheMostSpecificIsTaken() {
        // N119
        checkInference(#"
            package m
            open class Base {}
            class D <: Base {}
            func g(x: Base): Int64 { 1 }
            //     ^ Base
            func g(x: D): String { "" }
            //     ^ D
            func n(x: Int8): Int8 { x }
            //     ^ Int8
            func n(x: Int64): Int64 { x }
            //     ^ Int64
            func r(x: Float32): Float32 { x }
            //     ^ Float32
            func r(x: Float64): Float64 { x }
            //     ^ Float64
            func q<T>(x: T): String { "" }
            //        ^ T
            func q(x: Int64): Int64 { x }
            //     ^ Int64
            func test(): Unit {
                let a = g(D())
            //      ^ String
                let b = g(Base())
            //      ^ Int64
                let c = n(1)
            //      ^ Int64
                let d = n(1i8)
            //      ^ Int8
                let e = r(1.0)
            //      ^ Float64
                let f = q(1)
            //      ^ Int64
                let h = q("s")
            //      ^ String
            }
            "#)
    }

    @TestCase
    func theNearestLevelWhereAnOverloadFitsDecides() {
        // N117: a local, the members, the package, the imported
        checkInference(#"
            package m
            func f(x: Int64): Int64 { x }
            //     ^ Int64
            func g(x: Int64): Int64 { x }
            //     ^ Int64
            func println(x: Int8): Int8 { x }
            //           ^ Int8
            open class A { public func m(x: Int64): Int64 { x } }
            //                           ^ Int64
            class B <: A {
                public func m(x: Int8): Int8 { x }
            //                ^ Int8
                func f(x: Int8): Int8 { x }
            //         ^ Int8
                func g(x: String): String { x }
            //         ^ String
                func test(): Unit {
                    let a = f(1)
            //          ^ Int8
                    let b = g(1)
            //          ^ Int64
                    // the members of a type and of its supertypes are one level
                    let c = this.m(1)
            //          ^ Int64
                    let d = println(1)
            //          ^ Int8
                    let p = println("s")
            //          ^ Unit
                    func f(x: Int16): Int16 { x }
            //           ^ (Int16) -> Int16
            //             ^ Int16
                    let e = f(1)
            //          ^ Int16
                }
            }
            "#)
    }

    @TestCase
    func overloadsNoneOfWhichIsMostSpecificAreAmbiguous() {
        // N120
        checkInference(#"
            package m
            open class Base {}
            interface I {}
            class D <: Base & I {}
            func f(x: Base): Int64 { 1 }
            //     ^ Base
            func f(x: I): String { "" }
            //     ^ I
            func g(x: Int8): Int8 { x }
            //     ^ Int8
            func g(x: Int16): Int16 { x }
            //     ^ Int16
            func h(a: (Int64) -> Int64): Int64 { 1 }
            //     ^ (Int64) -> Int64
            func h(a: (String) -> String): String { "" }
            //     ^ (String) -> String
            func test(): Unit {
                // cjc: ambiguous match for function call 'f'
                let a = f(D())
            //      ^ {unknown}
                // cjc: ambiguous match for function call 'g'
                let b = g(1)
            //      ^ {unknown}
                // cjc: ambiguous match for function call 'h'
                let c = h({x => x})
            //      ^ {unknown}
            //             ^ {unknown}
                let d = h({x: Int64 => x})
            //      ^ Int64
            //             ^ Int64
                // cjc: cannot convert an integer literal to type 'Class-Base'
                let e = f(1)
            //      ^ {unknown}
            }
            "#)
    }

    @TestCase
    func anOverloadedCallInAnArgumentIsTakenForEachCandidateTried() {
        // N115 nested: the inner call's overload by the type the outer candidate expects
        checkInference(#"
            package m
            func p(x: Int64, y: String): Int64 { 1 }
            //     ^ Int64
            //               ^ String
            func p(x: String, y: String): String { "" }
            //     ^ String
            //                ^ String
            func k(x: String): Int64 { 1 }
            //     ^ String
            func k(x: Int64): String { "" }
            //     ^ Int64
            func h(x: Int64): Int64 { x }
            //     ^ Int64
            func h(x: Int32): String { "" }
            //     ^ Int32
            func test(): Unit {
                let s = "a"
            //      ^ String
                let n = 1
            //      ^ Int64
                let a = p(k(s), s)
            //      ^ Int64
                let b = p(k(n), s)
            //      ^ String
                let c: String = p(h(1), s)
            //      ^ String
                // cjc: ambiguous match for function call 'p'
                let d = p(h(1), s)
            //      ^ {unknown}
            }
            "#)
    }

    @TestCase
    func aLambdaFitsAFunctionReturningUnitWhateverItsBlockIs() {
        // N118
        checkInference(#"
            package m
            func k(h: () -> Unit): Int64 { 1 }
            //     ^ () -> Unit
            func k(h: () -> Bool): String { "" }
            //     ^ () -> Bool
            func test(): Unit {
                // `**=` of an integer takes a `UInt64`
                let a = k({ => var y = 2; y **= 2u64 })
            //      ^ Int64
            //                     ^ Int64
                let b = k({ => 1 })
            //      ^ Int64
            }
            "#)
    }

    @TestCase
    func tuplesAreCovariantAndFunctionsContravariantInTheirParameters() {
        // N116
        checkInference(#"
            package m
            open class Base {}
            class D <: Base {}
            func t(x: (Base, Int64)): Int64 { 1 }
            //     ^ (Base, Int64)
            func t(x: String): String { "" }
            //     ^ String
            func w(h: (D) -> Base): Int64 { 1 }
            //     ^ (D) -> Base
            func w(h: String): String { "" }
            //     ^ String
            func test(): Unit {
                let p = (D(), 1)
            //      ^ (D, Int64)
                let a = t(p)
            //      ^ Int64
                let hb = { x: Base => D() }
            //      ^^ (Base) -> D
            //             ^ Base
                let b = w(hb)
            //      ^ Int64
            }
            "#)
    }

    @TestCase
    func whatACandidateTriedWritesIsUndoneAndInferredAgainForTheOneTaken() {
        // A27: a member, a call of overloads and an argument of one type in the candidates tried
        checkInference(#"
            package m
            class Box {
                let n = 1
            //      ^ Int64
                func get(): Int64 { 1 }
            }
            class P {
                P(let p: Int64) {}
            //        ^ Int64
                let q = 2
            //      ^ Int64
                func f(x: Int64): Int64 { x }
            //         ^ Int64
                func f(x: String): String { x }
            //         ^ String
                func run(): Unit {
                    let a = f(p)
            //          ^ Int64
                    let b = f(q)
            //          ^ Int64
                }
            }
            let gv = 1
            //  ^^ Int64
            func f(x: Int64): Int64 { x }
            //     ^ Int64
            func f(x: String): String { x }
            //     ^ String
            func n2(x: Bool, y: Int8): Int8 { y }
            //      ^ Bool
            //               ^ Int8
            func n2(x: Bool, y: Int64): Int64 { y }
            //      ^ Bool
            //               ^ Int64
            func test(b: Box): Unit {
            //        ^ Box
                let a = f(b.get())
            //      ^ Int64
                let d = f(f(1))
            //      ^ Int64
                let e = f(gv)
            //      ^ Int64
                let g = f(b.n)
            //      ^ Int64
                let y = n2(true, 1)
            //      ^ Int64
                let s: String = "x" * 3
            //      ^ String
            }
            "#)
    }

    @TestCase
    func theBranchesOfALambdaReturningUnitAreOfAnyType() {
        // N118
        checkInference(#"
            package m
            func k(h: () -> Unit): Int64 { 1 }
            //     ^ () -> Unit
            func k(h: () -> Bool): String { "" }
            //     ^ () -> Bool
            func test(c: Bool): Unit {
            //        ^ Bool
                let u = k({ => if (c) { 1 } else { "s" } })
            //      ^ Int64
                let w = k({ => match (c) { case true => 1 case false => 2 } })
            //      ^ Int64
                let x = k({ => unsafe { 1 } })
            //      ^ Int64
            }
            "#)
    }

    @TestCase
    func aTypeArgumentUnknownIsAlikeToAny() {
        // a tuple's or a function's part unknown in an argument of a type hides nothing
        checkInference(#"
            package m
            func h(x: Array<(Int64, String)>): Int64 { 1 }
            //     ^ Array<(Int64, String)>
            func h(x: String): String { "" }
            //     ^ String
            func h2(x: Array<(Int64) -> String>): Int64 { 1 }
            //      ^ Array<(Int64) -> String>
            func h2(x: String): String { "" }
            //      ^ String
            func f(x: Int64): Int64 { x }
            //     ^ Int64
            func f(x: String): String { x }
            //     ^ String
            func test(): Unit {
                // cjc: undeclared identifier 'nope'
                let t = [(1, nope)]
            //      ^ Array<(Int64, {unknown})>
                let z = h(t)
            //      ^ Int64
                // cjc: undeclared identifier 'nope'
                let fs = [{x: Int64 => nope}]
            //      ^^ Array<(Int64) -> {unknown}>
            //             ^ Int64
                let z2 = h2(fs)
            //      ^^ Int64
                // cjc: ambiguous use of 'f'
                let v = f
            //      ^ {unknown}
                // cjc: no matching function declaration for function reference 'f'
                let fv: (Bool) -> Bool = f
            //      ^^ (Bool) -> Bool
            }
            "#)
    }

    @TestCase
    func anIndexIsACallOfTheOperatorItsTypeDeclares() {
        // N122: but a tuple's by a literal and a `VArray`'s, `a[i]` is `a.[](i)`, chosen as a call's
        checkInference(#"
            package m
            import std.collection.*
            class Grid {
                operator func [](i: Int64): String { "" }
            //                   ^ Int64
                operator func [](s: String): Int64 { 1 }
            //                   ^ String
                operator func [](i: Int64, j: Int64): Bool { true }
            //                   ^ Int64
            //                             ^ Int64
                operator func [](i: Int64, value!: String): Unit {}
            //                   ^ Int64
            //                             ^^^^^ String
            }
            struct Narrow {
                operator func [](i: Int8): String { "" }
            //                   ^ Int8
            }
            func test(): Unit {
                let a = [1, 2, 3]
            //      ^ Array<Int64>
                let e = a[0]
            //      ^ Int64
                let r = a[0..2]
            //      ^ Array<Int64>
                let v: VArray<Int64, $2> = [1, 2]
            //      ^ VArray<Int64, $2>
                let ve = v[1]
            //      ^^ Int64
                let l = ArrayList<String>()
            //      ^ ArrayList<String>
                let le = l[0]
            //      ^^ String
                let m = HashMap<String, Bool>()
            //      ^ HashMap<String, Bool>
                let me = m["k"]
            //      ^^ Bool
                let s = "abc"
            //      ^ String
                let b = s[0]
            //      ^ UInt8
                let sub = s[0..1]
            //      ^^^ String
                let g = Grid()
            //      ^ Grid
                let g1 = g[1]
            //      ^^ String
                let g2 = g["x"]
            //      ^^ Int64
                let g3 = g[1, 2]
            //      ^^ Bool
                let n = Narrow()[1]
            //      ^ String
                let t = (1, "s")
            //      ^ (Int64, String)
                let t1 = t[1]
            //      ^^ String
                let i = 1
            //      ^ Int64
                // cjc: tuple index must be an integer literal
                let ti = t[i]
            //      ^^ {unknown}
            }
            "#)
    }

    @TestCase
    func anAssignmentToAnIndexCallsTheOperatorTakingAValue() {
        // N124: `a[i] = v` is `a.[](i, value: v)`, of a `[]` taking `value!` last
        checkInference(#"
            package m
            import std.collection.*
            class Grid {
                operator func [](i: Int64): String { "" }
            //                   ^ Int64
                operator func [](i: Int64, j: Int64): Bool { true }
            //                   ^ Int64
            //                             ^ Int64
                operator func [](i: Int64, value!: String): Unit {}
            //                   ^ Int64
            //                             ^^^^^ String
            }
            struct Ro {
                operator func [](i: Int64): Int8 { 1 }
            //                   ^ Int64
            }
            func test(): Unit {
                let g = Grid()
            //      ^ Grid
                let u = (g[1] = "v")
            //      ^ Unit
                // cjc: cannot assign to this subscript expression
                let w = (g[1] = 2)
            //      ^ Unit
                // cjc: cannot assign to this subscript expression
                Ro()[0] = match (g[0]) { case s => s }
            //                                ^ String
                let a = [1, 2, 3]
            //      ^ Array<Int64>
                let au = (a[0] = 5)
            //      ^^ Unit
                let cu = (a[0] += 1)
            //      ^^ Unit
                let l = ArrayList<String>()
            //      ^ ArrayList<String>
                l[0] += "x"
                g[1] += "x"
            }
            "#)
    }

    @TestCase
    func anOperatorOfATypeIsACallOfItsMember() {
        // N122, N123: `a + b` is `a.+(b)`, `-a` `a.-()`, of its type's or an `extend`'s, chosen as a
        // call's: by the right, by the type expected; one not declared is none
        checkInference(#"
            package m
            struct V {
                V(let x: Int64) {}
            //        ^ Int64
                operator func +(o: V): V { V(x + o.x) }
            //                  ^ V
                operator func +(n: Int8): String { "" }
            //                  ^ Int8
                operator func -(): V { this }
                operator func -(o: V): Bool { true }
            //                  ^ V
                operator func !(): Int64 { 1 }
                operator func ==(o: V): Bool { true }
            //                   ^ V
                operator func <(o: V): String { "" }
            //                  ^ V
                operator func *(n: Int32): Int64 { 1 }
            //                  ^ Int32
                operator func *(n: Int64): V { this }
            //                  ^ Int64
            }
            extend V {
                operator func /(o: V): Float64 { 1.0 }
            //                  ^ V
            }
            open class B {
                operator func +(o: B): Int64 { 1 }
            //                  ^ B
            }
            class C <: B {}
            extend Int64 {
                operator func +(s: String): String { s }
            //                  ^ String
            }
            func test(): Unit {
                let v = V(1)
            //      ^ V
                let add = v + v
            //      ^^^ V
                let lit = v + 1
            //      ^^^ String
                let neg = -v
            //      ^^^ V
                let sub = v - v
            //      ^^^ Bool
                let not = !v
            //      ^^^ Int64
                let eq = v == v
            //      ^^ Bool
                // cjc: invalid binary operator '!=' on type 'Struct-V' and 'Struct-V'
                let ne = v != v
            //      ^^ {unknown}
                let lt = v < v
            //      ^^ String
                let mul = v * 1
            //      ^^^ V
                let mi: Int64 = v * 1
            //      ^^ Int64
                let div = v / v
            //      ^^^ Float64
                let inherited = C() + C()
            //      ^^^^^^^^^ Int64
                let ext = 1 + "s"
            //      ^^^ String
                let str = "a" + "b"
            //      ^^^ String
                let rep = "a" * 3
            //      ^^^ String
                let tup = (1, 2) == (1, 2)
            //      ^^^ Bool
                let opt = Some(1) == None
            //      ^^^ Bool
                // cjc: invalid binary operator '+' on type 'Struct-V' and 'Struct-String'
                let bad = v + "s"
            //      ^^^ {unknown}
            }
            "#)
    }

    @TestCase
    func anOperatorOfATypeParameterIsItsBoundsAndOfAGenericTypeItsArguments() {
        // N122
        checkInference(#"
            package m
            interface Addable<T> {
                operator func +(o: T): T
            //                  ^ T
            }
            func sum<T>(a: T, b: T) where T <: Addable<T> {
            //   ^^^ Unit
            //          ^ T
            //                ^ T
                let s = a + b
            //      ^ T
            }
            struct Box<T> {
                Box(let t: T) {}
            //          ^ T
                operator func [](i: Int64): T { t }
            //                   ^ Int64
                operator func +(o: Box<T>): Box<T> { this }
            //                  ^ Box<T>
            }
            func test(): Unit {
                let b = Box(1)
            //      ^ Box<Int64>
                let e = b[0]
            //      ^ Int64
                let bb = b + b
            //      ^^ Box<Int64>
                let s = Box("s")[0]
            //      ^ String
            }
            "#)
    }

    @TestCase
    func aLiteralLeftOfAnOperatorOfAnotherTypeIsOfItsDefaultType() {
        // N125: the language's tried first, then the left synthesized alone; the right a call's
        // argument, the type expected its return type's
        checkInference(#"
            package m
            struct V {
                V(let x: Int64) {}
            //        ^ Int64
                operator func +(n: Int8): Int8 { n }
            //                  ^ Int8
                operator func +(n: Int16): V { this }
            //                  ^ Int16
                operator func [](i: Int8): String { "" }
            //                   ^ Int8
                operator func <<(n: Int64): V { this }
            //                   ^ Int64
            }
            extend Int8 {
                operator func *(o: V): String { "" }
            //                  ^ V
            }
            extend Int64 {
                operator func -(o: V): Bool { true }
            //                  ^ V
            }
            func test(): Unit {
                let v = V(1)
            //      ^ V
                // cjc: invalid binary operator '*' on type 'Int64' and 'Struct-V'; of `Int64`'s one `*`,
                // `*(Duration)`, its return type, as a call of one candidate's (D55)
                let l8 = 3 * v
            //      ^^ Duration
                let l64 = 3 - v
            //      ^^^ Bool
                let a: Int8 = v + 1
            //      ^ Int8
                let b: V = v + 1
            //      ^ V
                // cjc: invalid binary operator '+' on type 'Struct-V' and 'Int16'
                let c = v + 1
            //      ^ {unknown}
                let i = v[1]
            //      ^ String
                let sh = v << 2
            //      ^^ V
            }
            "#)
    }

    @TestCase
    func aCompoundAssignmentOfATypesOperatorAssignsWhatItGives() {
        // N126: `x op= v` is `x = x.op(v)`
        checkInference(#"
            package m
            struct V {
                V(let x: Int64) {}
            //        ^ Int64
                operator func +(o: V): V { V(x + o.x) }
            //                  ^ V
                operator func -(n: Int64): Int64 { 1 }
            //                  ^ Int64
                operator func *(n: UInt8): V { this }
            //                  ^ UInt8
            }
            class Cell {
                var v = V(1)
            //      ^ V
            }
            func f(x: Unit): Int64 { 1 }
            //     ^ Unit
            func f(x: String): String { "" }
            //     ^ String
            func test(): Unit {
                var v = V(1)
            //      ^ V
                v += v
                let u = (v += v)
            //      ^ Unit
                // cjc: type incompatible in this compound assignment expression
                v -= 1
                v *= 2
                Cell().v += V(2)
                var arr = [V(1)]
            //      ^^^ Array<V>
                arr[0] += V(2)
                let o: ?V = v + v
            //      ^ Option<V>
                let fu = f(v += v)
            //      ^^ Int64
            }
            "#)
    }

    @TestCase
    func theLanguagesOperatorsAreBetweenItsTypesAndTheRestTheTypesOwn() {
        // N125, N126: arithmetic of numbers, an index of a tuple by a literal of any base, of a
        // `VArray` assigned as the language's
        checkInference(#"
            package m
            extend Int64 {
                operator func +(s: String): String { s }
            //                  ^ String
            }
            func test(): Unit {
                let n = 1
            //      ^ Int64
                // cjc: invalid binary operator '*' on type 'Float64' and 'Int64'; of `Float64`'s one
                // `*`, `*(Duration)`, its return type (D55)
                let fl = 1.5 * n
            //      ^^ Duration
                let ext = n + "s"
            //      ^^^ String
                // cjc: invalid binary operator '&' on type 'Bool' and 'Bool'
                let bits = true & false
            //      ^^^^ {unknown}
                var b = true
            //      ^ Bool
                b &&= false
                let bu = (b ||= true)
            //      ^^ Unit
                var m = 1
            //      ^ Int64
                // cjc: cannot convert a floating-point literal to type 'Int64'
                m += 1.5
                var va: VArray<Int64, $2> = [1, 2]
            //      ^^ VArray<Int64, $2>
                let vu = (va[1] = 4)
            //      ^^ Unit
                let t = (1, "s")
            //      ^ (Int64, String)
                let hex = t[0x1]
            //      ^^^ String
                let t3 = (1, "s", true)
            //      ^^ (Int64, String, Bool)
                let bin = t3[0b1]
            //      ^^^ String
                let oct = t3[0o2]
            //      ^^^ Bool
                let suffixed = t3[1i64]
            //      ^^^^^^^^ String
                // cjc: cannot convert a floating-point literal to type 'Int64'
                let float = t3[1.5]
            //      ^^^^^ {unknown}
            }
            "#)
    }

    @TestCase
    func anIntegerLiteralIsReadInItsBase() {
        @Expect(integerOf("0xAf"), Some(175))
        @Expect(integerOf("0o17"), Some(15))
        @Expect(integerOf("0b1_01"), Some(5))
        @Expect(integerOf("2u8"), Some(2))
        @Expect(integerOf("0o9"), None)
        @Expect(integerOf("0x"), None)
        @Expect(integerOf("99999999999999999999"), None)
    }

    @TestCase
    func anOperatorOfTheLanguageIsKeptWhateverFailsInsideItsOperands() {
        // its operands fitting it, a check failing deeper is no reason to try a type's operator
        checkInference(#"
            package m
            func g(x: Int64): Int64 { x }
            //     ^ Int64
            func test(b: UInt8, c: Bool): Unit {
            //        ^ UInt8
            //                  ^ Bool
                // cjc: mismatched types
                let sum = b + (if (c) { g("s"); 1 } else { 2 })
            //      ^^^ UInt8
            }
            "#)
    }

    @TestCase
    func coalescingIsTheValueOfItsLeftOrItsRightCheckedAgainstIt() {
        // N127: the left synthesized alone, an `Option<T>`; the right checked against `T`, or against
        // the type expected, of which `T` is a subtype; no join; right-associative, looser than `||`
        checkInference(#"
            package m
            open class Base {}
            class Derived <: Base {}
            func test(a: ?Int64, a8: ?Int8, aa: ??Int64, d: ?Derived, b: Base, flag: ?Bool): Unit {
            //        ^ Option<Int64>
            //                   ^^ Option<Int8>
            //                              ^^ Option<Option<Int64>>
            //                                           ^ Option<Derived>
            //                                                        ^ Base
            //                                                                 ^^^^ Option<Bool>
                let i = a ?? 1
            //      ^ Int64
                let i8 = a8 ?? 1
            //      ^^ Int8
                let o = aa ?? None
            //      ^ Option<Int64>
                let s = Some(1) ?? 2
            //      ^ Int64
                let base: Base = d ?? b
            //      ^^^^ Base
                let boxed: ?Int64 = a ?? None
            //      ^^^^^ Option<Int64>
                let early = a ?? return
            //      ^^^^^ Int64
                let chained = a ?? a ?? 1
            //      ^^^^^^^ Int64
                let loose = flag ?? false || true
            //      ^^^^^ Bool
                // cjc: mismatched types: the right checked against `Derived`, the left's `T` all the same
                let x = d ?? b
            //      ^ Derived
                // cjc: mismatched types: `a ?? a` an `Int64`, no `Option`
                let grouped = (a ?? a) ?? 1
            //      ^^^^^^^ {unknown}
                // cjc: type of left operand does not support coalescing operation
                let n = 1 ?? 2
            //      ^ {unknown}
                // cjc: mismatched types: `Int64` no `Int8`
                let narrow: Int8 = a ?? 1
            //      ^^^^^^ Int8
            }
            "#)
    }

    @TestCase
    func aPipelineCallsItsRightWithItsLeft() {
        // N128: `x |> f` is `f(x)`, a call's overloads and type arguments; left-associative
        checkInference(#"
            package m
            class C {
                func n(x: Int64): String { "" }
            //         ^ Int64
            }
            func f(x: Int64): String { "" }
            //     ^ Int64
            func s(x: String): Bool { true }
            //     ^ String
            func id<T>(x: T): T { x }
            //         ^ T
            func g(x: Int64): String { "" }
            //     ^ Int64
            func g(x: String): Bool { true }
            //     ^ String
            func h8(x: Int8): Int8 { x }
            //      ^ Int8
            func test(o: C, fn: (Int64) -> String): Unit {
            //        ^ C
            //              ^^ (Int64) -> String
                let a = 1 |> f
            //      ^ String
                let b = 1 |> g
            //      ^ String
                let c = "s" |> g
            //      ^ Bool
                let d = 1 |> id
            //      ^ Int64
                let e: Int8 = 1 |> id
            //      ^ Int8
                let lit = 1 |> h8
            //      ^^^ Int8
                let m = 1 |> o.n
            //      ^ String
                let v = 1 |> fn
            //      ^ String
                let chain = 1 |> f |> s
            //      ^^^^^ Bool
                let lambda = 1 |> {x: Int8 => x}
            //      ^^^^^^ Int8
            //                     ^ Int8
                let composed = 1 |> (f ~> s)
            //      ^^^^^^^^ Bool
                // not yet: an `Int64` to cjc, the type arguments of `first("x")` solved with what it
                // is called with, as of `first("x")([1, 2])` (N131); here solved alone, of its bound
                let generic = [1, 2] |> first("x")
            //      ^^^^^^^ ToString
            }
            func first<T>(d: String): (Iterable<T>) -> T where T <: ToString {
            //            ^ String
                {it => it.iterator().next().getOrThrow()}
            //   ^^ Iterable<T>
            }
            "#)
    }

    @TestCase
    func aLambdaReturningWhatHoldsATypeArgumentNotSolvedIsSynthesized() {
        // N132: its body tells the argument (`R` of `Option<R>`), as cjc's `filterMap {d => d as T}`
        checkInference(#"
            package m
            open class Base {}
            class Derived <: Base {}
            class Box<T> {
                func fm<R>(g: (T) -> Option<R>): Array<R> { [] }
            //             ^ (T) -> Option<R>
            }
            func test(b: Box<Base>): Unit {
            //        ^ Box<Base>
                let k = b.fm {x => x as Derived}
            //      ^ Array<Derived>
            //                ^ Base
            }
            "#)
    }

    @TestCase
    func aCompositionIsStdCoresCompositionOfItsOperandsSynthesizedAlone() {
        // N129: `f ~> g` is `std.core`'s `composition(f, g)`, `(T1) -> T3` of `(T1) -> T2` and
        // `(T2) -> T3`; an operand a lambda of a parameter not written is an error
        checkInference(#"
            package m
            open class Base {}
            class Derived <: Base {}
            func f(x: Int64): String { "" }
            //     ^ Int64
            func s(x: String): Bool { true }
            //     ^ String
            func g(x: Int64): String { "" }
            //     ^ Int64
            func g(x: String): Bool { true }
            //     ^ String
            func d(x: Int64): Derived { Derived() }
            //     ^ Int64
            func b(x: Base): Bool { true }
            //     ^ Base
            func id<T>(x: T): T { x }
            //         ^ T
            func test(): Unit {
                let a = f ~> s
            //      ^ (Int64) -> Bool
                let sub = d ~> b
            //      ^^^ (Int64) -> Bool
                let overloaded = f ~> g
            //      ^^^^^^^^^^ (Int64) -> Bool
                let three = f ~> s ~> {x: Bool => 1}
            //      ^^^^^ (Int64) -> Int64
            //                         ^ Bool
                let explicit = id<Int64> ~> f
            //      ^^^^^^^^ (Int64) -> String
                let called = (f ~> s)(1)
            //      ^^^^^^ Bool
                let expected: (Int64) -> Base = f ~> {x: String => Derived()}
            //      ^^^^^^^^ (Int64) -> Base
            //                                        ^ String
                // cjc: parameters of this lambda expression must have type annotations
                let untyped = f ~> {x => x.size}
            //      ^^^^^^^ {unknown}
            //                      ^ {unknown}
            }
            "#)
    }

    @TestCase
    func aValueOfATypeOfACallOperatorIsCalledThroughIt() {
        // N130: `k(x)` of a value of no function type is `k.()(x)`, in a pipeline and a composition
        // too
        checkInference(#"
            package m
            class K {
                operator func ()(x: Int64): Bool { true }
            //                   ^ Int64
                operator func ()(x: String): String { x }
            //                   ^ String
            }
            func f(x: Int64): String { "" }
            //     ^ Int64
            func test(k: K): Unit {
            //        ^ K
                let a = k(1)
            //      ^ Bool
                let b = k("s")
            //      ^ String
                let c = 1 |> k
            //      ^ Bool
                // cjc: type of left operand does not support coalescing operation
                let unknown = (1 ?? 2)(3)
            //      ^^^^^^^ {unknown}
                // not yet: a `(Int64) -> String` to cjc, of `k.()` the one taking a `String`; an
                // operand of a composition is not called through its `operator ()` here
                let d = f ~> k
            //      ^ (Int64) -> {unknown}
            }
            "#)
    }

    @TestCase
    func anEditElsewhereRunsNothingThatReadTheInference() {
        // arrange
        let parsed = Fixture.parse(#"
            package m
            func f(): Unit { let a = 1 }
            func g(): Unit {}
            "#)
        let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let source = db.sourceFile(parsed.files[0].fileId).getOrThrow()
        let item = itemTree(db, source).items.iterator().filter {one => one.names.contains("f")}.next().getOrThrow()
        let def = DefId(db, ItemFile.Source(source), item.id)
        exprTyCount(db, def)
        let before = inferenceReaderRuns.load()

        // act
        let text = source.text(db).toString()
        source.setText(db).to(Rope(text.replace("func g(): Unit {}", "func g(): Unit { let b = 2 }")))
        exprTyCount(db, def)

        // assert
        @Expect(inferenceReaderRuns.load(), before)
    }
}
