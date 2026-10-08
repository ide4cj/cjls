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
