package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

@Test
class GenericBoundsTest {
    @TestCase
    func anInterfacesWhereBoundsItsArgument() {
        checkInference(#"
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
            "#)
    }

    @TestCase
    func transitiveBoundsSupplyMembersAndGenericCallArguments() {
        checkInference(#"
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
            "#)
    }

    @TestCase
    func anInterfacesWhereSuppliesAnUpperBoundForCallInference() {
        // The pinned cjc infers Base even without a value argument or an expected type.
        checkInference(#"
            package m
            interface R<X> where X <: Base {}
            open class Base <: R<Base> {}
            func make<T>(): ?T where T <: R<T> { None }
            func f(): Unit {
                let value = make()
            //      ^^^^^ Option<Base>
            }
            "#)
    }

    @TestCase
    func eachInterfaceInstanceBoundsItsOwnArgument() {
        checkBounds(#"
            package m
            interface C<X> {}
            interface R<X> where X <: C<X> {}
            func f<T, U>(): Unit where T <: R<T> & R<U> {}
            "#, [["R<T>", "R<U>", "C<T>"], ["C<U>"]])
    }

    @TestCase
    func aConstraintOnAnotherArgumentDoesNotBoundTheReceiver() {
        checkBounds(#"
            package m
            interface C<X> {}
            interface R<X> where X <: C<X> {}
            func f<T, U>(): Unit where T <: R<U> {}
            "#, [["R<U>"], ["C<U>"]])
    }

    @TestCase
    func recursiveBoundsTerminateEvenWhenTheirArgumentsGrow() {
        checkBounds(#"
            package m
            interface Box<X> {}
            interface R<X> where X <: R<Box<X>> {}
            func f<T>(): Unit where T <: R<T> {}
            "#, [["R<T>", "R<Box<T>>"]])
    }

    @TestCase
    func mutuallyRecursiveInterfaceBoundsTerminate() {
        checkBounds(#"
            package m
            interface A<X> where X <: B<X> {}
            interface B<X> where X <: A<X> {}
            func f<T>(): Unit where T <: A<T> {}
            "#, [["A<T>", "B<T>"]])
    }
}

func checkBounds(text: String, expected: Array<Array<String>>): Unit {
    let fixture = Fixture.parse(text)
    let db = fixture.database()
    let source = db.sourceFile(fixture.files[0].fileId).getOrThrow()
    let item = itemTree(db, source).items.iterator().filter {one => one.names.contains("f")}.next().getOrThrow()
    let def = DefId(db, ItemFile.Source(source), item.id)
    let actual = Array(expected.size) {i => headTysOf(db, Ty(db, ParamTy(def, i))).map {ty => ty.text(db)}}
    @Expect(actual, expected)
}
