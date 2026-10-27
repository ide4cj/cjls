package loupe

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*
import loupe.hir.{overriddenMembers}
import loupe.syntax.parse

/**
 * Checks the hierarchy of the name at the `$0` of `fixture` is its annotations: `super` under each member it
 * overrides or implements (`overriddenMembers`), `impl` under each implementation `implementationsAt` finds; the
 * packages of std named by `binaries` read from the SDK.
 */
func checkHierarchy(fixture: String, binaries!: Array<String> = []): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database(binaries: binaries.map { name => stdCjoRead(name, stdCjo(name)) })
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let file = db.sourceFile(cursor.fileId).getOrThrow()
    let token =
        tokenAt(parse(db, file).syntaxNode(), cursor.offset) ??
            throw FixtureException("no name at $0")
    let annotations = ArrayList<Annotation>()
    for (definition in meaningsAt(db, file, token)) {
        if (let DeclDef(id) <- definition) {
            for (one in overriddenMembers(db, id)) {
                let target = declTarget(db, one) ?? continue
                annotations.add(Annotation(target.fileId, target.focusRange, "super"))
            }
        }
    }
    for (target in implementationsAt(db, cursor.fileId, cursor.offset)) {
        annotations.add(Annotation(target.fileId, target.focusRange, "impl"))
    }
    expectAnnotations(fixture, annotations.toArray())
}

@Test
class ImplementationTest {
    @TestCase
    func aClassMemberOverridesWithoutTheKeywordAndASameNamedOverloadDoesNot() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            open class Base {
                public open func f(n: Int64): Int64 { n }
            //                   ^ super
            }
            open class Mid <: Base {
                public open func $0f(n: Int64): Int64 { n + 1 }
                public func f(b: Bool): Int64 { 0 }
            }
            class Sub <: Mid {
                public override func f(n: Int64): Int64 { n + 2 }
            //                       ^ impl
            }
            "#
        )
    }

    @TestCase
    func anInterfaceMemberIsImplementedByAClassAndAStruct() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            interface I {
                func $0g(): Int64
            }
            class A <: I {
                public func g(): Int64 { 1 }
            //              ^ impl
            }
            struct S <: I {
                public func g(): Int64 { 2 }
            //              ^ impl
            }
            "#
        )
    }

    @TestCase
    func aClassMemberImplementsWhatAnInterfaceOfItsSupertypeDeclares() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            interface I {
                func g(): Int64
            //       ^ super
            }
            interface J <: I {}
            open class A <: J {
                public open func $0g(): Int64 { 1 }
            }
            class B <: A {
                public func g(): Int64 { 2 }
            //              ^ impl
            }
            "#
        )
    }

    @TestCase
    func anExtendInAnotherPackageImplementsWithTheTypesMemberAndItsOwn() {
        // cjc takes an `extend` of an interface in the type's package or the interface's only
        checkHierarchy(
            #"
            //- /a/a.cj module=m package=m.a
            package m.a
            public interface I {
                func $0g(): Int64
            }
            extend Int64 <: I {
                public func g(): Int64 { this }
            //              ^ impl
            }
            //- /b/b.cj module=m package=m.b
            package m.b
            import m.a.I
            public open class C {
                public open func g(): Int64 { 1 }
            //                   ^ impl
            }
            extend C <: I {}
            //- /c/c.cj module=m package=m.c
            package m.c
            import m.b.C
            class D <: C {
                public func g(): Int64 { 2 }
            //              ^ impl
            }
            "#
        )
    }

    @TestCase
    func aMemberOfAnExtendImplementsWhatTheExtendDeclares() {
        checkHierarchy(
            #"
            //- /a/a.cj module=m package=m.a
            package m.a
            public interface I {
                func g(): Int64
            //       ^ super
            }
            //- /a/ext.cj module=m package=m.a
            package m.a
            extend Int64 <: I {
                public func $0g(): Int64 { this }
            }
            "#
        )
    }

    @TestCase
    func aMemberOfAClassImplementsWhatAnExtendInAnotherPackageDeclares() {
        checkHierarchy(
            #"
            //- /a/a.cj module=m package=m.a
            package m.a
            public interface I {
                func g(): Int64
            //       ^ super
            }
            //- /b/b.cj module=m package=m.b
            package m.b
            import m.a.I
            public open class C {
                public open func $0g(): Int64 { 1 }
            }
            extend C <: I {}
            //- /c/c.cj module=m package=m.c
            package m.c
            import m.b.C
            class D <: C {
                public func g(): Int64 { 2 }
            //              ^ impl
            }
            "#
        )
    }

    @TestCase
    func aTypesMemberImplementsWhatAnExtendItsFileSeesDeclares() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            interface I {
                func g(): Int64
            //       ^ super
            }
            class C {
                public func $0g(): Int64 { 1 }
            }
            //- /b.cj module=m package=m
            package m
            extend C <: I {}
            "#
        )
    }

    @TestCase
    func theImplementationsOfAnInterfaceAreTheTypesBelowItAndTheExtendsDeclaringIt() {
        checkHierarchy(
            #"
            //- /a/a.cj module=m package=m.a
            package m.a
            public interface $0I {}
            public open class C <: I {}
            //                ^ impl
            extend Int64 <: I {}
            //     ^^^^^ impl
            //- /b/b.cj module=m package=m.b
            package m.b
            import m.a.C
            class D <: C {}
            //    ^ impl
            "#
        )
    }

    @TestCase
    func ofAGenericSupertypeTheParametersAreSeenWithItsArguments() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            interface G<T> {
                func $0h(x: T): Int64
            }
            class X <: G<Int64> {
                public func h(x: Int64): Int64 { x }
            //              ^ impl
                public func h(x: Bool): Int64 { 0 }
            }
            class Y<U> <: G<Array<U>> {
                public func h(x: Array<U>): Int64 { 0 }
            //              ^ impl
                public func h(x: U): Int64 { 1 }
            }
            "#
        )
    }

    @TestCase
    func aMemberOfAGenericSupertypeIsFoundUpWithItsArguments() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            interface G<T> {
                func h(x: T): Int64
            //       ^ super
            }
            class X <: G<Int64> {
                public func $0h(x: Int64): Int64 { x }
            }
            "#
        )
    }

    @TestCase
    func anOverloadOfAGenericSupertypesMemberIsNotFoundUp() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            interface G<T> {
                func h(x: T): Int64
            }
            class X <: G<Int64> {
                public func h(x: Int64): Int64 { x }
                public func $0h(x: Bool): Int64 { 0 }
            }
            "#
        )
    }

    @TestCase
    func aStaticMemberIsRedefinedWithOrWithoutTheKeyword() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            open class Base {
                public static func $0t(): Int64 { 1 }
            }
            open class Mid <: Base {
                public static func t(): Int64 { 2 }
            //                     ^ impl
            }
            class Sub <: Mid {
                public redef static func t(): Int64 { 3 }
            //                           ^ impl
            }
            "#
        )
    }

    @TestCase
    func anInterfacesStaticMemberCalledThroughATypeParameterIsImplemented() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            interface S {
                static func s(): Int64
            }
            class C <: S {
                public static func s(): Int64 { 7 }
            //                     ^ impl
            }
            func viaT<T>(): Int64 where T <: S {
                T.$0s()
            }
            "#
        )
    }

    @TestCase
    func aPropertyIsImplemented() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            interface P {
                prop $0p: Int64
            }
            class Q <: P {
                public prop p: Int64 {
            //              ^ impl
                    get() { 3 }
                }
            }
            "#
        )
    }

    @TestCase
    func aGenericFunctionIsImplementedWhateverItsTypeParametersAreNamed() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            interface I {
                func $0id<T>(x: T): T
            }
            class C <: I {
                public func id<U>(x: U): U { x }
            //              ^^ impl
            }
            "#
        )
    }

    @TestCase
    func aTypeBelowAnInterfaceOnTwoPathsIsFoundOnce() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            interface $0I {}
            interface J <: I {}
            //        ^ impl
            interface K <: I {}
            //        ^ impl
            class C <: J & K {}
            //    ^ impl
            "#
        )
    }

    @TestCase
    func theImplementationsOfAnInterfaceOfStdAreLookedForInTheProjectAndInStd() {
        // std's own, whose sources are not read here, have nowhere to go
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            class C <: $0ToString {
            //    ^ impl
                public func toString(): String { "" }
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func aStructALocalAndAnOperatorHaveNoImplementations() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            struct $0S {}
            "#
        )
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            func f(): Unit { let $0x = 1 }
            "#
        )
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            func f(): Int64 { 1 $0+ 2 }
            "#
        )
    }

    @TestCase
    func aNameThatIsNoMemberHasNoImplementations() {
        checkHierarchy(
            #"
            //- /a.cj module=m package=m
            package m
            func $0top(): Int64 { 1 }
            "#
        )
    }
}
