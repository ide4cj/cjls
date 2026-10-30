package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.AnalysisDatabase
import loupe.fixture.{Fixture, stdCjo, stdCjoRead}

@Test
class GenericBoundsTest {
    @TestCase
    func anInterfacesWhereBoundsItsArgument() {
        checkInference(
            #"
            package m
            interface R<T> where T <: Comparable<T> {
                static func top(): T
            }
            func f<T>(a: T, b: T): Unit where T <: R<T> {
            //        ^ T
            //              ^ T
                let greater = a > b
            //      ^^^^^^^ Bool
                let c: Comparable<T> = a
            //      ^ Comparable<T>
            }
            "#
        )
    }

    @TestCase
    func transitiveBoundsSupplyMembersAndGenericCallArguments() {
        checkInference(
            #"
            package m
            interface Make<X> {
                static func make(): X
                func value(): X
            }
            interface Step<X> where X <: Make<X> {}
            func use<U>(x: U): U where U <: Make<U> { x }
            //          ^ U
            func f<T>(x: T): Unit where T <: Step<T> {
            //        ^ T
                let a = x.value()
            //      ^ T
                let b = T.make()
            //      ^ T
                let c = use(x)
            //      ^ T
            }
            "#
        )
    }

    @TestCase
    func anInterfacesWhereSuppliesAnUpperBoundForCallInference() {
        // The pinned cjc infers Base even without a value argument or an expected type.
        checkInference(
            #"
            package m
            interface R<X> where X <: Base {}
            open class Base <: R<Base> {}
            func make<T>(): ?T where T <: R<T> { None }
            func f(): Unit {
                let value = make()
            //      ^^^^^ Option<Base>
            }
            "#
        )
    }

    @TestCase
    func eachInterfaceInstanceBoundsItsOwnArgument() {
        checkBounds(
            #"
            package m
            interface C<X> {}
            interface R<X> where X <: C<X> {}
            func f<T, U>(): Unit where T <: R<T> & R<U> {}
            "#,
            [["R<T>", "R<U>", "C<T>"], ["C<U>"]]
        )
    }

    @TestCase
    func aConstraintOnAnotherArgumentDoesNotBoundTheReceiver() {
        checkBounds(
            #"
            package m
            interface C<X> {}
            interface R<X> where X <: C<X> {}
            func f<T, U>(): Unit where T <: R<U> {}
            "#,
            [["R<U>"], ["C<U>"]]
        )
    }

    @TestCase
    func aRecursiveInterfaceWithPermutedArgumentsAddsBothBounds() {
        checkInference(
            #"
            package m
            interface R<A, B> where B <: R<B, A> & Comparable<B> {}
            func f<T, U>(a: T, b: U): Unit where T <: R<T, U> {
            //           ^ T
            //                 ^ U
                let left = a > a
            //      ^^^^ Bool
                let right = b > b
            //      ^^^^^ Bool
            }
            "#
        )
    }

    @TestCase
    func aFiniteGrowthOfArgumentsIsExpandedUntilItRepeats() {
        checkBounds(
            #"
            package m
            interface Box<X> {}
            interface Tag<X> {}
            interface R<A, B, C> where A <: R<A, Box<C>, C> & Tag<B> {}
            func f<T, U, V>(): Unit where T <: R<T, U, V> {}
            "#,
            [["R<T, U, V>", "R<T, Box<V>, V>", "Tag<U>", "Tag<Box<V>>"], [], []]
        )
    }

    @TestCase
    func growingBoundsDiscardPartialResultsAndMarkEveryParameterUnknown() {
        let (db, def) =
            boundsFixture(
                #"
            package m
            interface Box<X> {}
            interface R<A, B> where A <: R<A, Box<B>> {}
            func f<T, U>(): Unit where T <: R<T, U> {}
            "#
            )
        let result = genericBounds(db, def)
        let unknown = Ty(db, UnknownTy(UnknownReason.GenericBoundsLimit))
        @Expect(result.size, 2)
        for (i in 0..2) {
            let param = Ty(db, ParamTy(GenericOwner.Declaration(def), i))
            @Expect(result[i], TyBound(param, [unknown]))
            @Expect(firstUnknownIn(db, param), Some(unknown))
            @Expect(isSubtype(db, param, Ty(db, PrimTy("Int64")), None), true)
        }
        @Expect(hasUnknowns(db, Ty(db, TupleTy(result.map {one => one.ty}))), true)
    }

    @TestCase
    func growingBoundsPropagateUnknownThroughMembersOperatorsAndCalls() {
        let text =
            #"
            package m
            interface Box<X> {}
            interface R<A, B> where A <: R<A, Box<B>> {}
            func make<T, U>(): T where T <: R<T, U> { throw Exception() }
            func f<T, U>(x: T): Unit where T <: R<T, U> {
            //           ^ T
                let sum = x + x
            //      ^^^ {unknown}
                let member = x.missing
            //      ^^^^^^ {unknown}
                let call = x.missing()
            //      ^^^^ {unknown}
                let fromType = T.missing()
            //      ^^^^^^^^ {unknown}
                let made = make()
            //      ^^^^ {unknown}
            }
            "#
        checkInference(text)
        let (db, def) = boundsFixture(text, binaries: ["std.core"])
        let lowered = body(db, def)
        let locals = inferBody(db, def).locals
        @Expect(locals.size, 6)
        for (i in 0..locals.size where lowered.locals[i].name != "x") {
            @Expect(locals[i].kind(db), UnknownTy(UnknownReason.GenericBoundsLimit))
        }
    }

    @TestCase
    func aConcreteSubjectAddsNoFurtherAssumptions() {
        checkBounds(
            #"
            package m
            interface Box<X> {}
            interface R<X> where X <: R<Box<X>> {}
            func f<T>(): Unit where T <: R<T> {}
            "#,
            [["R<T>", "R<Box<T>>"]]
        )
    }

    @TestCase
    func mutuallyRecursiveInterfaceBoundsTerminate() {
        checkBounds(
            #"
            package m
            interface A<X> where X <: B<X> {}
            interface B<X> where X <: A<X> {}
            func f<T>(): Unit where T <: A<T> {}
            "#,
            [["A<T>", "B<T>"]]
        )
    }
}

func checkBounds(text: String, expected: Array<Array<String>>): Unit {
    let (db, def) = boundsFixture(text)
    let actual =
        Array(genericsOf(db, def).size) {
            i =>
            headTysOf(db, Ty(db, ParamTy(GenericOwner.Declaration(def), i)))
                .map { ty => ty.text(db) }
        }
    @Expect(actual, expected)
}

func boundsFixture(text: String, binaries!: Array<String> = []): (AnalysisDatabase, DefId) {
    let fixture = Fixture.parse(text)
    let db = fixture.database(binaries: binaries.map { name => stdCjoRead(name, stdCjo(name)) })
    let source = db.sourceFile(fixture.files[0].fileId).getOrThrow()
    let item =
        itemTree(db, source)
            .items
            .iterator()
            .filter { one => one.names.contains("f") }
            .next()
            .getOrThrow()
    (db, DefId(db, ItemFile.Source(source), item.id))
}
