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
