package loupe

import std.unittest.*
import std.unittest.testmacro.*

/**
 * Where a name in a body is declared (step 6 of #48): its locals, the members of the type around it,
 * then its file's scope.
 */
@Test
class BodyDefinitionTest {
    @TestCase
    func aParameter() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(x: Int64): Int64 { $0x }
            //     ^ def
            "#)
    }

    @TestCase
    func aLetOfTheBody() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(): Int64 {
                let x = 1
            //      ^ def
                $0x
            }
            "#)
    }

    @TestCase
    func aLetInANestedBlockShadowsAParameter() {
        // N59
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(x: Int64): Int64 {
                if (true) {
                    let x = 2
            //          ^ def
                    return $0x
                }
                x
            }
            "#)
    }

    @TestCase
    func aLocalIsNotSeenBeforeItsDeclaration() {
        // N60
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            let x = "global"
            //  ^ def
            func f(): String {
                let y = $0x
                let x = 1
                y
            }
            "#)
    }

    @TestCase
    func aVariableIsNotSeenInItsOwnInitializer() {
        // N61
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            let x = 5
            //  ^ def
            func f(): Int64 {
                let x = $0x + 1
                x
            }
            "#)
    }

    @TestCase
    func aLocalFunctionCallsItself() {
        // N60
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(): Int64 {
                func g(n: Int64): Int64 {
            //       ^ def
                    if (n == 0) { 0 } else { $0g(n - 1) }
                }
                g(3)
            }
            "#)
    }

    @TestCase
    func aLocalFunctionDoesNotSeeOneDeclaredAfterIt() {
        // N60
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(): Int64 {
                func a(): Int64 { $0b() }
            //                    ^ no definition
                func b(): Int64 { 1 }
                a()
            }
            "#)
    }

    @TestCase
    func localFunctionsOfOneBlockOverload() {
        // N63
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(): Int64 {
                func g(n: Int64): Int64 { n }
            //       ^ def
                func g(s: String): Int64 { 0 }
            //       ^ def
                $0g(1)
            }
            "#)
    }

    @TestCase
    func aLocalFunctionAndOneOfThePackageOverload() {
        // N63
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func g(s: String): Int64 { 0 }
            //   ^ def
            func f(): Int64 {
                func g(n: Int64): Int64 { n }
            //       ^ def
                $0g(1)
            }
            "#)
    }

    @TestCase
    func aLocalVariableStopsTheFunctions() {
        // N63
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func g(s: String): Int64 { 0 }
            func f(): Int64 {
                let g = {n: Int64 => n}
            //      ^ def
                $0g(1)
            }
            "#)
    }

    @TestCase
    func aVariableOfThePackageStopsTheLocalFunctions() {
        // N63
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            let g = 1
            func f(): Int64 {
                func g(n: Int64): Int64 { n }
            //       ^ def
                $0g(1)
            }
            "#)
    }

    @TestCase
    func aLocalFunctionHidesAConstructor() {
        // N63
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A {}
            func f(): Int64 {
                func A(x: Int64): Int64 { x }
            //       ^ def
                $0A(1)
            }
            "#)
    }

    @TestCase
    func aLambdasParameterShadowsALocal() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(): Int64 {
                let x = 1
                let g = {x: String => $0x}
            //           ^ def
                x
            }
            "#)
    }

    @TestCase
    func aBindingOfACaseInItsGuard() {
        // N62
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(o: ?Int64): Int64 {
                match (o) {
                    case Some(v) where $0v > 0 => v
            //                ^ def
                    case _ => 0
                }
            }
            "#)
    }

    @TestCase
    func aBindingOfATypePattern() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(o: Int64): Int64 {
                match (o) {
                    case n: Int64 => $0n
            //           ^ def
                }
            }
            "#)
    }

    @TestCase
    func aBindingOfAnIfLetIsNotSeenInItsElse() {
        // N62
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(o: ?Int64): Int64 {
                if (let Some(v) <- o) { v } else { $0v }
            //                                     ^ no definition
            }
            "#)
    }

    @TestCase
    func aBindingOfAnIfLetAlongItsConditions() {
        // N62
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(o: ?Int64): Int64 {
                if (let Some(a) <- o && $0a > 0) { a } else { 0 }
            //               ^ def
            }
            "#)
    }

    @TestCase
    func theVariableOfAForIsNotSeenInWhatItIteratesOver() {
        // N62
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(x: Array<Int64>): Unit {
            //     ^ def
                for (x in $0x) {}
            }
            "#)
    }

    @TestCase
    func theVariableOfAForInItsGuard() {
        // N62
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(xs: Array<Int64>): Unit {
                for (i in xs where $0i > 0) {}
            //       ^ def
            }
            "#)
    }

    @TestCase
    func theBindingOfACatch() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class E {}
            func f(): Unit {
                try {} catch (e: E) { $0e }
            //                ^ def
            }
            "#)
    }

    @TestCase
    func aResourceInItsTry() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class R {}
            func f(): Unit {
                try (r = R()) { $0r }
            //       ^ def
            }
            "#)
    }

    @TestCase
    func aDefaultValueSeesAnEarlierParameter() {
        // N67
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(a: Int64, b!: Int64 = $0a): Int64 { b }
            //     ^ def
            "#)
    }

    @TestCase
    func aNameInAnInterpolation() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(x: Int64): String { "x is ${$0x}" }
            //     ^ def
            "#)
    }

    @TestCase
    func aLoneNameOfAPatternIsAConstructorEvenUnderALocal() {
        // N72
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            enum C { Red | Green }
            //       ^^^ def
            func f(c: C): Int64 {
                let Red = 5
                match (c) {
                    case $0Red => Red
                    case _ => 0
                }
            }
            "#)
    }

    @TestCase
    func aLoneNameOfAPatternBindsWhenNoConstructorHasIt() {
        // N72
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func g(): Int64 { 1 }
            func f(o: Int64): Int64 {
                match (o) {
                    case g => $0g
            //           ^ def
                }
            }
            "#)
    }

    @TestCase
    func aLetOfAConstructorsNameBinds() {
        // N72
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            enum E { None }
            func f(): Int64 {
                let None = 3
            //      ^^^^ def
                $0None
            }
            "#)
    }

    @TestCase
    func aConstructorOfAnEnumAnotherFileImports() {
        // N73
        checkDefinition(#"
            //- /p/e.cj module=m package=m.p
            package m.p
            public enum E { A(Int64) | B }
            //              ^ def
            //- /a.cj module=m package=m
            package m
            import m.p.E
            //- /b.cj module=m package=m
            package m
            func f(): Unit {
                let x = $0A(1)
            }
            "#)
    }

    @TestCase
    func aTypeParameterAsAValue() {
        // N74
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            interface I { static func make(): Int64 }
            func f<T>(): Int64 where T <: I { $0T.make() }
            //     ^ def
            "#)
    }

    @TestCase
    func aLocalShadowsATypeParameterAsAValue() {
        // N74
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f<T>(): Int64 {
                let T = "s"
            //      ^ def
                $0T.size
            }
            "#)
    }

    @TestCase
    func aMethodsTypeParameterShadowsAFieldAsAValue() {
        // N74
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            interface I { static func make(): Int64 }
            class A {
                var T = "s"
                func f<T>(): Int64 where T <: I { $0T.make() }
            //         ^ def
            }
            "#)
    }

    @TestCase
    func aFieldShadowsTheClasssTypeParameterAsAValue() {
        // N74
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A<x> {
                var x = 1
            //      ^ def
                func f(): Int64 { $0x }
            }
            "#)
    }

    @TestCase
    func aFunctionOfThePackage() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func g(): Int64 { 1 }
            //   ^ def
            func f(): Int64 { $0g() }
            "#)
    }

    @TestCase
    func aVariableOfThePackageInAnotherOnesInitializer() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            let a = 1
            //  ^ def
            let b = $0a + 1
            "#)
    }

    @TestCase
    func aTypeInABody() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {}
            //    ^ def
            func f(): Unit {
                let c: $0C = C()
            }
            "#)
    }

    @TestCase
    func aTypeParameterOfALocalFunction() {
        // N68
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(): Unit {
                func g<T>(x: T): T {
            //         ^ def
                    let y: $0T = x
                    y
                }
            }
            "#)
    }

    @TestCase
    func aTypeParameterOfTheFunctionInItsBody() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f<T>(x: T): Unit {
            //     ^ def
                let y: $0T = x
            }
            "#)
    }

    @TestCase
    func aFieldOfTheClass() {
        // N69
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A {
                var x = 1
            //      ^ def
                func f(): Int64 { $0x }
            }
            "#)
    }

    @TestCase
    func aLocalShadowsAField() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A {
                var x = 1
                func f(): String {
                    let x = "s"
            //          ^ def
                    $0x
                }
            }
            "#)
    }

    @TestCase
    func aParameterShadowsAField() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A {
                var x = 1
                init(x: Int64) { this.x = $0x }
            //       ^ def
            }
            "#)
    }

    @TestCase
    func aFieldOfTheSuperclass() {
        // N69
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            open class B {
                protected var y = 1
            //                ^ def
            }
            class A <: B {
                func f(): Int64 { $0y }
            }
            "#)
    }

    @TestCase
    func aMemberShadowsAFunctionOfThePackage() {
        // N69
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func g(s: String): String { s }
            class A {
                var g = 1
            //      ^ def
                func f(): Unit { $0g("") }
            }
            "#)
    }

    @TestCase
    func anInstanceMemberIsFoundInAStaticFunction() {
        // N69
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            let x = "g"
            class A {
                var x = 1
            //      ^ def
                static func f(): String { $0x }
            }
            "#)
    }

    @TestCase
    func aPrivateMemberOfTheSuperclassIsFound() {
        // N69
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            let y = "g"
            open class B {
                private var y = 1
            //              ^ def
            }
            class A <: B {
                func f(): String { $0y }
            }
            "#)
    }

    @TestCase
    func aMemberFunctionAndOneOfThePackageOverload() {
        // N70
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func g(s: String): String { s }
            //   ^ def
            class A {
                func g(n: Int64): Int64 { n }
            //       ^ def
                func f(): Unit { $0g(1) }
            }
            "#)
    }

    @TestCase
    func aMemberOfTheTypeAnExtendExtends() {
        // N69
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A {
                var x = 1
            //      ^ def
            }
            extend A {
                func f(): Int64 { $0x }
            }
            "#)
    }

    @TestCase
    func aMemberOfAnotherExtend() {
        // N69
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A {}
            extend A {
                func a(): Int64 { 1 }
            //       ^ def
            }
            extend A {
                func b(): Int64 { $0a() }
            }
            "#)
    }

    @TestCase
    func aMemberOfAnExtendInTheTypesBody() {
        // N69
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A {
                func b(): Int64 { $0a() }
            }
            extend A {
                func a(): Int64 { 1 }
            //       ^ def
            }
            "#)
    }

    @TestCase
    func aMemberOfAnExtendOfAPrimitiveType() {
        // N69
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            extend Int64 {
                func a(): Int64 { 1 }
            //       ^ def
            }
            extend Int64 {
                func b(): Int64 { $0a() }
            }
            "#)
    }

    @TestCase
    func aDefaultMemberOfAnInterface() {
        // N69
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            interface I {
                func a(): Int64 { 1 }
            //       ^ def
            }
            class A <: I {
                func f(): Int64 { $0a() }
            }
            "#)
    }

    @TestCase
    func aMemberOfAnInterfaceAnExtendAdds() {
        // N69
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            interface I {
                func a(): Int64 { 1 }
            //       ^ def
            }
            class A {}
            extend A <: I {}
            extend A {
                func f(): Int64 { $0a() }
            }
            "#)
    }

    @TestCase
    func aMemberParameterOfThePrimaryConstructor() {
        // N69
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A {
                A(let x: Int64) {}
            //        ^ def
                func f(): Int64 { $0x }
            }
            "#)
    }

    @TestCase
    func aConstructorOfTheEnumInItsMember() {
        // N69, N72
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            enum C {
                Red | Green
            //  ^^^ def
                func f(): Int64 { match (this) { case $0Red => 1 case Green => 2 } }
            }
            "#)
    }

    @TestCase
    func aFieldInALambdaOfAMethod() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A {
                var x = 1
            //      ^ def
                func f(): Int64 { {=> $0x}() }
            }
            "#)
    }

    @TestCase
    func aFieldInAnotherFieldsInitializer() {
        // N71
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A {
                var a = $0b
                var b = 1
            //      ^ def
            }
            "#)
    }

    @TestCase
    func aFieldInAGetter() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A {
                var x = 1
            //      ^ def
                prop p: Int64 {
                    get() { $0x }
                }
            }
            "#)
    }

    @TestCase
    func theParameterOfASetter() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A {
                var x = 1
                mut prop p: Int64 {
                    get() { x }
                    set(v) { x = $0v }
            //          ^ def
                }
            }
            "#)
    }
}
