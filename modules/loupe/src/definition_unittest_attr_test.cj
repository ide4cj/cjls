package loupe

import std.unittest.*
import std.unittest.testmacro.*

/**
 * What std.unittest's macros on a declaration take as code in their `[...]` (#191): `x in src`'s `x` the parameter it
 * names, `src` a name of the scope around the declaration; `@Types`' type parameter and types; `@Tag`'s identifiers
 * nothing.
 */
@Test
class UnittestAttrDefinitionTest {
    @TestCase
    func theParameterOfADataArgOfATestCaseGoesToTheParameter() {
        checkDefinitionWithUnittest(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            class C {
                @TestCase[$0x in data()]
                func f(x: Int64): Unit {}
                //     ^ def
                func data(): Array<Int64> { [1, 2] }
            }
            "#
        )
    }

    @TestCase
    func theSourceOfADataArgOfATestCaseGoesToAMemberOfTheClass() {
        checkDefinitionWithUnittest(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            class C {
                @TestCase[x in $0data()]
                func f(x: Int64): Unit {}
                func data(): Array<Int64> { [1, 2] }
                //   ^^^^ def
            }
            "#
        )
    }

    @TestCase
    func theParameterOfADataArgOfATopLevelTestGoesToTheParameter() {
        checkDefinitionWithUnittest(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test[$0x in data()]
            func f(x: Int64): Unit {}
            //     ^ def
            func data(): Array<Int64> { [1, 2] }
            "#
        )
    }

    @TestCase
    func theSourceOfADataArgOfATopLevelTestGoesToAFunctionOfTheFile() {
        checkDefinitionWithUnittest(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test[x in $0data()]
            func f(x: Int64): Unit {}
            func data(): Array<Int64> { [1, 2] }
            //   ^^^^ def
            "#
        )
    }

    @TestCase
    func theSourceOfADataArgSeesNoParameterOfTheDeclaration() {
        checkDefinitionWithUnittest(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            let x = [1]
            //  ^ def
            @Test[x in $0x]
            func f(x: Int64): Unit {}
            "#
        )
    }

    @TestCase
    func aSourceUnderAnotherMacroIsTheDeclarationsToo() {
        checkDefinitionWithUnittest(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            class C {
                @TestCase[x in $0data()]
                @Tag[Slow]
                func f(x: Int64): Unit {}
                func data(): Array<Int64> { [1, 2] }
                //   ^^^^ def
            }
            "#
        )
    }

    @TestCase
    func theTypeParameterOfTypesGoesToTheTypeParameter() {
        checkDefinitionWithUnittest(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            @Types[$0T in <A>]
            class C<T> {}
            //      ^ def
            class A {}
            "#
        )
    }

    @TestCase
    func aTypeOfTypesGoesToTheType() {
        checkDefinitionWithUnittest(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            class C {
                @TestCase
                @Types[T in <Int64, $0A>]
                func f<T>(): Unit {}
            }
            class A {}
            //    ^ def
            "#
        )
    }

    @TestCase
    func anIdentifierATagListsGoesNowhere() {
        checkDefinitionWithUnittest(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            class C {
                @TestCase
                @Tag[$0A]
                //   ^ no definition
                func f(): Unit {}
            }
            class A {}
            "#
        )
    }

    @TestCase
    func aTimeoutsExpressionGoesToWhatItNames() {
        checkDefinitionWithUnittest(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            let limit = 1
            //  ^^^^^ def
            @Test
            class C {
                @TestCase
                @Timeout[$0limit]
                func f(): Unit {}
            }
            "#
        )
    }

    @TestCase
    func anOptionOfConfigureGoesToItsKeysProperty() {
        checkDefinitionInStd(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            @Configure[$0generationSteps: 10]
            class C {}
            "#,
            ["std.core", "std.ast", "std.unittest", "std.unittest.testmacro"],
            [
                "unittest/options.cj: generationSteps in `public static prop generationSteps: KeyGenerationSteps {`"
            ]
        )
    }

    @TestCase
    func anOptionOfConfigureDeclaredByUnittestOptionGoesToItsName() {
        checkDefinitionWithUnittest(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @UnittestOption[Int64](zxc)
            //                     ^^^ def
            func f(): Unit {}
            @Test
            @Configure[$0zxc: 1]
            class C {}
            "#
        )
    }
}
