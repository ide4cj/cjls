package loupe

import std.unittest.*
import std.unittest.testmacro.*

@Test
class DelegationDefinitionTest {
    @TestCase
    func superSelectsTheCalledOverload() {
        checkDefinition(
            #"
            //- /base.cj module=m package=m
            package m
            open class Base {
                init(x: String) {}
                init(x: Int64) {}
            //  ^^^^ def
            }
            //- /child.cj module=m package=m
            package m
            class Child <: Base {
                init() { su$0per(1) }
            }
            "#,
            std: ["std.core"]
        )
    }

    @TestCase
    func thisSelectsTheCalledOverload() {
        checkDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            class C {
                init(x: String) {}
                init(x: Int64) {}
            //  ^^^^ def
                init() { th$0is(1) }
            }
            "#,
            std: ["std.core"]
        )
    }

    @TestCase
    func superFindsTheOnlyConstructor() {
        checkDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            open class Base { init() {} }
            //                ^^^^ def
            class Child <: Base { init() { $0super() } }
            "#
        )
    }

    @TestCase
    func thisFindsThePrimaryConstructor() {
        checkDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            class C {
                C(let x: Int64) {}
            //  ^ def
                init() { this$0(1) }
            }
            "#,
            std: ["std.core"]
        )
    }

    @TestCase
    func superSubstitutesTheGenericSuperclass() {
        checkDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            open class Base<T> {
                init(x: T) {}
            //  ^^^^ def
                init(x: String) {}
            }
            class Child <: Base<Int64> { init() { $0super(1) } }
            "#,
            std: ["std.core"]
        )
    }

    @TestCase
    func thisInAGenericClass() {
        checkDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            class C<T> {
                init(x: T) {}
            //  ^^^^ def
                init(x: T, unused: Int64) { $0this(x) }
            }
            "#
        )
    }

    @TestCase
    func superFindsABinaryConstructorInItsSources() {
        checkDefinitionInStd(
            #"
            //- /main.cj module=m package=m
            package m
            class E <: Exception {
                init() { $0super("message") }
            }
            "#,
            ["std.core"],
            ["core/exception.cj: init in `public init(message: String) {`"]
        )
    }

    @TestCase
    func aClassCallGoesToItsChosenConstructor() {
        checkDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            class C {
                init(x: String) {}
                init(x: Int64) {}
            //  ^^^^ def
            }
            func f(): C { $0C(1) }
            "#,
            std: ["std.core"]
        )
    }

    @TestCase
    func anImplicitConstructorHasNoWrittenTarget() {
        checkDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            open class Base {}
            class Child <: Base {
                init() { $0super() }
            //             ^^^^^ no definition
            }
            "#
        )
    }

    @TestCase
    func aBareThisHasNoConstructorTarget() {
        checkDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            class C {
                init() {}
                func f(): C { $0this }
            //                  ^^^^ no definition
            }
            "#
        )
    }

    @TestCase
    func aSuperReceiverHasNoConstructorTarget() {
        checkDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            open class Base { init() {} let x = 1 }
            class Child <: Base {
                init() { super() }
                func f(): Int64 { $0super.x }
            //                      ^^^^^ no definition
            }
            "#
        )
    }

    @TestCase
    func anUnresolvedDelegationHasNoTarget() {
        checkDefinition(
            #"
            //- /main.cj module=m package=m
            package m
            open class Base { init(x: Int64) {} }
            class Child <: Base {
                init() { $0super() }
            //             ^^^^^ no definition
            }
            "#
        )
    }
}
