package loupe

import std.unittest.*
import std.unittest.testmacro.*

/**
 * A name in a `quote`'s interpolations, `$(e)` and `$x`, read as code where the macro runs (#195); the rest of
 * the quote is tokens, resolved where the macro is expanded, and nothing in it resolves here.
 */
@Test
class QuoteDefinitionTest {
    @TestCase
    func aParameterInAnInterpolation() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            macro package m
            import std.ast.*
            public macro M(input: Tokens): Tokens {
            //             ^^^^^ def
                quote(f($($0input)))
            }
            "#)
    }

    @TestCase
    func aLocalNamedByADollar() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            macro package m
            import std.ast.*
            public macro M(input: Tokens): Tokens {
                let name = input
            //      ^^^^ def
                quote(let $0$name = 1)
            }
            "#)
    }

    @TestCase
    func aBackquotedNameNamedByADollar() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            macro package m
            import std.ast.*
            public macro M(input: Tokens): Tokens {
            //             ^^^^^ def
                quote($0$`input`)
            }
            "#)
    }

    @TestCase
    func aNameInAQuoteInAnInterpolation() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            macro package m
            import std.ast.*
            public macro M(input: Tokens): Tokens {
            //             ^^^^^ def
                quote(a + $(quote(b + $0$input)))
            }
            "#)
    }

    @TestCase
    func aNameOutsideTheInterpolationsHasNoDefinition() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            macro package m
            import std.ast.*
            public macro M(input: Tokens): Tokens {
                quote($0input + $input)
            //          ^^^^^ no definition
            }
            "#)
    }

    @TestCase
    func anEscapedDollarIsATokenWithNoDefinition() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            macro package m
            import std.ast.*
            public macro M(input: Tokens): Tokens {
                quote(\$0$input)
            //           ^^^^^^ no definition
            }
            "#)
    }
}
