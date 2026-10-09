package loupe

import std.unittest.*
import std.unittest.testmacro.*

/**
 * A name in an expression macro's arguments, read as an argument list before any expansion (#174), the macro
 * itself opaque; arguments that do not parse as one are tokens, and nothing in them resolves.
 */
@Test
class MacroArgumentDefinitionTest {
    @TestCase
    func aLocalInAComparison() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(): Unit {
                let a = 1
            //      ^ def
                @Expect($0a == 2)
            }
            "#)
    }

    @TestCase
    func aFunctionCalledInTheSecondArgument() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func g(): Int64 { 1 }
            //   ^ def
            func f(): Unit {
                @Expect(1, $0g())
            }
            "#)
    }

    @TestCase
    func aNamedArgument() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(d: Float64): Unit {
            //     ^ def
                @Expect(1.0, 1.1, delta: $0d)
            }
            "#)
    }

    @TestCase
    func aLocalInABlockWithoutAnArrow() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(x: Int64): Unit {
            //     ^ def
                @AssertThrows[Exception]({
                    let y = $0x
                })
            }
            "#)
    }

    @TestCase
    func aLetOfTheBlockSeenAfterIt() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(): Unit {
                @AssertThrows({
                    let y = 1
            //          ^ def
                    throw Exception("${$0y}")
                })
            }
            "#)
    }

    @TestCase
    func theInnerCallOfTwoNested() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(v: Bool): Unit {
            //     ^ def
                @A[x] @Assert($0v)
            }
            "#)
    }

    @TestCase
    func aMemberOfAValue() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
                let size = 1
            //      ^^^^ def
            }
            func f(c: C): Unit {
                @Expect(c.$0size, 1)
            }
            "#)
    }

    @TestCase
    func nothingInArgumentsThatDoNotParse() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f(T: Int64): Unit {
                @M($0T in [Int64])
            //       ^ no definition
            }
            "#)
    }
}

/**
 * The macro a call names (#175): looked up as a macro, in its file's scope, whatever the call is on or in.
 */
@Test
class MacroNameDefinitionTest {
    @TestCase
    func aMacroOnADeclarationOfTheFile() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.*
            @$0M
            class C {}
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro M(input: Tokens): Tokens { input }
            //           ^ def
            "#)
    }

    @TestCase
    func aMacroOnAMember() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.M
            class C {
                @$0M
                func f(): Unit {}
            }
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro M(input: Tokens): Tokens { input }
            //           ^ def
            "#)
    }

    @TestCase
    func aMacroCalledInABody() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.M
            func f(): Int64 {
                @$0M(1)
            }
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro M(input: Tokens): Tokens { input }
            //           ^ def
            "#)
    }

    @TestCase
    func aMacroAfterThePackageImportedByItsName() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            import m.ms
            @ms.$0M
            class C {}
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro M(input: Tokens): Tokens { input }
            //           ^ def
            "#)
    }

    @TestCase
    func aMacroUnderAnAlias() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.M as N
            @$0N
            class C {}
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro M(input: Tokens): Tokens { input }
            //           ^ def
            "#)
    }

    @TestCase
    func aFunctionOfTheMacrosNameIsNotTheMacro() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.*
            func M(): Unit {}
            @$0M
            class C {}
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro M(input: Tokens): Tokens { input }
            //           ^ def
            "#)
    }

    @TestCase
    func aMacroNotImportedHasNoDefinition() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
                @Ma$0c
            //   ^^^ no definition
                func f(): Unit {}
            }
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro Mac(input: Tokens): Tokens { input }
            "#)
    }
}
