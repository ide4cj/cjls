package loupe

import std.unittest.*
import std.unittest.testmacro.*

/**
 * Where a name after a `.` in a body is declared (step 7 of #48): after a package, a type, a type
 * parameter, `this` or `super`, as names tell; after a value, as its type does (step 8b).
 */
@Test
class FieldDefinitionTest {
    @TestCase
    func aFunctionOfAnImportedPackage() {
        // N76
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public func f(): Int64 { 1 }
            //          ^ def
            //- /main.cj module=m package=m
            package m
            import m.a
            func g(): Int64 { a.$0f() }
            "#)
    }

    @TestCase
    func aVariableOfAnImportedPackage() {
        // N76
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public var v = 1
            //         ^ def
            //- /main.cj module=m package=m
            package m
            import m.a
            func g(): Int64 { a.$0v }
            "#)
    }

    @TestCase
    func aTypeOfAnImportedPackage() {
        // N76
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {
            //           ^ def
                public static func make(): Int64 { 1 }
            }
            //- /main.cj module=m package=m
            package m
            import m.a
            func g(): Int64 { a.$0C.make() }
            "#)
    }

    @TestCase
    func aStaticMemberOfATypeOfAnImportedPackage() {
        // N76, N77
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {
                public static func make(): Int64 { 1 }
            //                     ^^^^ def
            }
            //- /main.cj module=m package=m
            package m
            import m.a
            func g(): Int64 { a.C.$0make() }
            "#)
    }

    @TestCase
    func aPackageByItsAlias() {
        // N76
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public func f(): Int64 { 1 }
            //          ^ def
            //- /main.cj module=m package=m
            package m
            import m.a as z
            func g(): Int64 { z.$0f() }
            "#)
    }

    @TestCase
    func noConstructorRightAfterAPackage() {
        // N76: `a.E.Red`, not `a.Red`
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public enum E { Red | Blue }
            //- /main.cj module=m package=m
            package m
            import m.a
            func g(): Unit { a.$0Red }
            //                   ^^^ no definition
            "#)
    }

    @TestCase
    func aConstructorThroughATypeOfAPackage() {
        // N76, N77
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public enum E { Red | Blue }
            //              ^^^ def
            //- /main.cj module=m package=m
            package m
            import m.a
            func g(): Unit { a.E.$0Red }
            "#)
    }

    @TestCase
    func noPackageUnderAPackage() {
        // N76
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            //- /a/b/b.cj module=m package=m.a.b
            package m.a.b
            public class D {}
            //- /main.cj module=m package=m
            package m
            import m.a
            func g(): Unit { a.$0b.D() }
            //                 ^ no definition
            "#)
    }

    @TestCase
    func aDeclarationThePackageDoesNotSee() {
        // N76: internal to `m.a`, which `m.b` is not under
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            func hid(): Unit {}
            //- /b/b.cj module=m package=m.b
            package m.b
            import m.a
            func g(): Unit { a.$0hid() }
            //                   ^^^ no definition
            "#)
    }

    @TestCase
    func aLocalHidesAnImportedPackage() {
        // N75: `a.f` is `K`'s, which takes `a`'s type
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public func f(): Int64 { 1 }
            //- /main.cj module=m package=m
            package m
            import m.a
            class K { func f(): Bool { true } }
            //             ^ def
            func g(): Unit {
                let a = K()
                a.$0f()
            }
            "#)
    }

    @TestCase
    func aLocalHidesAType() {
        // N75, N80: the local's type has `make`; cjc says an object cannot access static member 'make'
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
                static func make(): Int64 { 1 }
            //              ^^^^ def
                func other(): Bool { true }
            }
            func g(): Unit {
                let C = C()
                C.$0make()
            }
            "#)
    }

    @TestCase
    func aStaticFunctionOfAType() {
        // N77
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
                static func s(): Int64 { 1 }
            //              ^ def
            }
            func g(): Int64 { C.$0s() }
            "#)
    }

    @TestCase
    func aStaticVariableOfAType() {
        // N77
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
                static let sv = 1
            //             ^^ def
            }
            func g(): Int64 { C.$0sv }
            "#)
    }

    @TestCase
    func anInstanceMemberThroughATypeIsFound() {
        // N77: cjc finds it, then says it cannot be accessed by the type's name
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
                func i(): Int64 { 1 }
            //       ^ def
            }
            func g(): Int64 { C.$0i() }
            "#)
    }

    @TestCase
    func aConstructorThroughItsEnum() {
        // N77
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            enum Color { Red | Green(Int64) }
            //                 ^^^^^ def
            func g(): Color { Color.$0Green(1) }
            "#)
    }

    @TestCase
    func aConstructorThroughAGenericEnumWithArguments() {
        // N77
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            enum E<T> { A(T) | B }
            //                 ^ def
            func g(): E<Int64> { E<Int64>.$0B }
            "#)
    }

    @TestCase
    func aStaticFunctionOfAnEnum() {
        // N77
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            enum Color {
                Red
                static func make(): Color { Red }
            //              ^^^^ def
            }
            func g(): Color { Color.$0make() }
            "#)
    }

    @TestCase
    func aMemberOfAnExtendThroughAType() {
        // N77
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {}
            extend C {
                static func e(): Int64 { 1 }
            //              ^ def
            }
            func g(): Int64 { C.$0e() }
            "#)
    }

    @TestCase
    func aStaticMemberOfASupertypeThroughAType() {
        // N77
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            open class A {
                static func s(): Int64 { 1 }
            //              ^ def
            }
            class B <: A {}
            func g(): Int64 { B.$0s() }
            "#)
    }

    @TestCase
    func aStaticMemberThroughATypeAlias() {
        // N77
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
                static func make(): Int64 { 1 }
            //              ^^^^ def
            }
            type A = C
            func g(): Int64 { A.$0make() }
            "#)
    }

    @TestCase
    func aStaticFunctionOfATypeParameterBound() {
        // N78
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            interface I {
                static func s(): Int64
            //              ^ def
            }
            func g<T>(): Int64 where T <: I { T.$0s() }
            "#)
    }

    @TestCase
    func aStaticFunctionOfALocalFunctionsTypeParameterBound() {
        // N78
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            interface I {
                static func s(): Int64
            //              ^ def
            }
            func f(): Unit {
                func g<T>(): Int64 where T <: I { T.$0s() }
            }
            "#)
    }

    @TestCase
    func aStaticFunctionOfATypesTypeParameterBound() {
        // N78
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            interface I {
                static func s(): Int64
            //              ^ def
            }
            class K<T> where T <: I {
                func g(): Int64 { T.$0s() }
            }
            "#)
    }

    @TestCase
    func thisMeansTheMemberWhateverALocalSays() {
        // N79
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
                var x = 1
            //      ^ def
                func g(): Int64 {
                    let x = 2
                    this.$0x
                }
            }
            "#)
    }

    @TestCase
    func thisInAnExtendIsTheExtendedType() {
        // N79
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
                var x = 1
            //      ^ def
            }
            extend C {
                func g(): Int64 { this.$0x }
            }
            "#)
    }

    @TestCase
    func thisReachesAMemberOfAnotherExtend() {
        // N79
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {}
            extend C {
                func e(): Int64 { 1 }
            //       ^ def
            }
            extend C {
                func g(): Int64 { this.$0e() }
            }
            "#)
    }

    @TestCase
    func superMeansTheSuperclassNotTheOverride() {
        // N79
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            open class A {
                public open func f(): Int64 { 1 }
            //                   ^ def
            }
            class B <: A {
                public func f(): Int64 { super.$0f() }
            }
            "#)
    }

    @TestCase
    func superFindsAPrivateMemberOfTheSuperclass() {
        // N79: found, then "can not access"
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            open class A {
                private var p = 1
            //              ^ def
            }
            class B <: A {
                func g(): Int64 { super.$0p }
            }
            "#)
    }

    @TestCase
    func superReachesAnExtendOfTheSuperclass() {
        // N79
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            open class A {}
            extend A {
                func h(): Int64 { 1 }
            //       ^ def
            }
            class B <: A {
                func g(): Int64 { super.$0h() }
            }
            "#)
    }

    @TestCase
    func anOverloadOfASubclassDoesNotHideTheSuperclasss() {
        // N70; the call takes the one of as many parameters (N115)
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            open class A {
                func f(): Int64 { 1 }
            //       ^ def
            }
            class B <: A {
                func f(x: Int64): Bool { true }
                func g(): Int64 { this.$0f() }
            }
            "#)
    }

    @TestCase
    func aMemberOfAValueCalledGoesToTheOverloadTaken() {
        // N117, N119: the members of a type and its supertypes are one level, `Int64` first
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            open class A {
                public func m(x: Int64): Int64 { x }
            //              ^ def
            }
            class B <: A {
                public func m(x: Int8): Int8 { x }
            }
            func g(): Unit {
                B().$0m(1)
            }
            "#)
    }

    @TestCase
    func aMemberOfAValueByItsType() {
        // N75: the value's type tells (D55)
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class K {
                func f(): Int64 { 1 }
            //       ^ def
            }
            func g(): Int64 {
                let k = K()
                k.$0f()
            }
            "#)
    }

    @TestCase
    func aMemberOfACallByWhatItReturns() {
        // N75
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class K {
                func f(): Int64 { 1 }
            //       ^ def
            }
            func k(): K { K() }
            func g(): Int64 { k().$0f() }
            "#)
    }

    @TestCase
    func aMemberOfAStaticVariableByItsInferredType() {
        // N75, N100: `C.k` is a value, of the type of `K()`
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class K {
                func f(): Int64 { 1 }
            //       ^ def
            }
            class C {
                static let k = K()
            }
            func g(): Int64 { C.k.$0f() }
            "#)
    }

    @TestCase
    func anExtendOfAnotherInstanceOfTheTypeIsNotSeen() {
        // N86: cjc says 'only' is not a member of class 'Box<S>'
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class Box<T> {}
            class S {}
            extend Box<Int64> {
                func only(): Int64 { 1 }
            }
            func g(b: Box<S>): Int64 { b.$0only() }
            //                             ^^^^ no definition
            "#)
    }

    @TestCase
    func anOverrideHidesWhatItOverrides() {
        // N107
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            open class A {
                public open func f(): Int64 { 1 }
            }
            class B <: A {
                public override func f(): Int64 { 2 }
            //                       ^ def
            }
            func g(b: B): Int64 { b.$0f() }
            "#)
    }
}
