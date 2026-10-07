package cjformat

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * `before` formatted is `after`, and `after` is left as it is.
 */
func check(before: String, after: String) {
    @Expect(formatText(before), Some(after))
    @Expect(formatText(after), Some(after))
}

/**
 * `text` as a test writes it, in a raw string: the first line break and the indent the lines share
 * left out, a last line of spaces too.
 */
func code(text: String): String {
    let lines = text.split("\n")[1..]
    let body = if (lines[lines.size - 1].trimAscii().isEmpty()) { lines[..lines.size - 1] } else { lines }
    let indent = body.filter {line => !line.trimAscii().isEmpty()}
        .map {line => line.size - line.trimAsciiStart().size}
        .iterator() |> min
    let shared = indent ?? 0
    String.join(body.map {line => if (line.trimAscii().isEmpty()) { "" } else { line[shared..] }}, delimiter: "\n") +
        "\n"
}

@Test
class FormatTest {
    @TestCase
    func aBlockIsIndentedOneLevelPerBrace() {
        check(
            code(#"
            class A {
            func f() {
                      let x = 1
              }
            }
            "#),
            code(#"
            class A {
                func f() {
                    let x = 1
                }
            }
            "#))
    }

    @TestCase
    func aLineCarryingAStatementOnIsOneLevelIn() {
        check(
            code(#"
            func f() {
                let x = a +
                b
                Router()
                .route(x)
                .route(y)
            }
            "#),
            code(#"
            func f() {
                let x = a +
                    b
                Router()
                    .route(x)
                    .route(y)
            }
            "#))
    }

    @TestCase
    func bracketsOpenedOnOneLineIndentOneLevel() {
        check(
            code(#"
            func f() {
                let r = g(a, h(b,
                c))
                let s = g(
                h(
                b
                )
                )
            }
            "#),
            code(#"
            func f() {
                let r = g(a, h(b,
                    c))
                let s = g(
                    h(
                        b
                    )
                )
            }
            "#))
    }

    @TestCase
    func aBodyIsIndentedFromItsDeclarationsFirstLine() {
        check(
            code(#"
            func f(a: Int64,
            b: Int64): Int64 {
            a
            }
            "#),
            code(#"
            func f(a: Int64,
                b: Int64): Int64 {
                a
            }
            "#))
    }

    @TestCase
    func aConditionBrokenInsideItsParenthesesIsOneLevelIn() {
        check(
            code(#"
            func f() {
                if (a &&
                        b) {
                    c
                }
            }
            "#),
            code(#"
            func f() {
                if (a &&
                    b) {
                    c
                }
            }
            "#))
    }

    @TestCase
    func whatFollowsTheArrowOfACaseIsOneLevelIn() {
        check(
            code(#"
            func f() {
                match (x) {
                case 1 =>
                if (y) {
                z
                }
                case 2 | 3 |
                4 => w
                }
            }
            "#),
            code(#"
            func f() {
                match (x) {
                    case 1 =>
                        if (y) {
                            z
                        }
                    case 2 | 3 |
                        4 => w
                }
            }
            "#))
    }

    @TestCase
    func aLambdaIsIndentedFromItsLine() {
        check(
            code(#"
            func f() {
                xs
                    .map { x =>
                    x
                    }
                g(a, { y =>
                y
                })
            }
            "#),
            code(#"
            func f() {
                xs
                    .map { x =>
                        x
                    }
                g(a, { y =>
                    y
                })
            }
            "#))
    }

    @TestCase
    func aLambdasStatementsAreAtTheLevelOfParametersOnALineOfTheirOwn() {
        check(
            code(#"
            func f() {
                g {
                    x: Int64 =>
                        x
                }
            }
            "#),
            code(#"
            func f() {
                g {
                    x: Int64 =>
                    x
                }
            }
            "#))
    }

    @TestCase
    func insideBracketsALineCarryingAnElementOnIsOneLevelIn() {
        check(
            code(#"
            func f() {
                g(
                    "a" +
                    "b",
                    c)
                let m: HashMap<String,
                Int64> = h()
            }
            "#),
            code(#"
            func f() {
                g(
                    "a" +
                        "b",
                    c)
                let m: HashMap<String,
                    Int64> = h()
            }
            "#))
    }

    @TestCase
    func annotationsCommentsAndAMacroNameDoNotMakeADeclarationACarriedLine() {
        check(
            code(#"
            @Test
            class A {
                /**
                  * doc
                  */
                @Deprecated
                  public func f() {}
            }
            "#),
            code(#"
            @Test
            class A {
                /**
                  * doc
                  */
                @Deprecated
                public func f() {}
            }
            "#))
    }

    @TestCase
    func whatAMacroReadsAsTokensMovesAsAWhole() {
        check(
            code(#"
            class A {
              @TestCase[x in [
                    1,
                  2
              ]]
              func f(x: Int64) {
                  @Expect(x,
                     x)
              }
            }
            "#),
            code(#"
            class A {
                @TestCase[x in [
                      1,
                    2
                ]]
                func f(x: Int64) {
                    @Expect(x,
                       x)
                }
            }
            "#))
    }

    @TestCase
    func aMultiLineStringIsLeftAlone() {
        let source = "func f() {\n    let s = \"\"\"\n  a  \n        b\n\"\"\"\n}\n"
        check(source, source)
    }

    @TestCase
    func aBlockCommentMovesWithItsFirstLine() {
        check(
            "func f() {\n/*\n * a  \n */\n}\n",
            "func f() {\n    /*\n     * a\n     */\n}\n")
    }

    @TestCase
    func trailingWhitespaceGoesAndBlankLinesAreKeptToOne() {
        check("\n\nlet a = 1   \n\n\n\nlet b = 2 // c  \n\n", "let a = 1\n\nlet b = 2 // c\n")
    }

    @TestCase
    func theFileEndsInOneLineBreak() {
        check("let a = 1", "let a = 1\n")
        check("", "")
    }

    @TestCase
    func crlfLineBreaksAreKept() {
        check("func f() {\r\nx\r\n}", "func f() {\r\n    x\r\n}\r\n")
    }

    @TestCase
    func aFileWithSyntaxErrorsIsNotFormatted() {
        @Expect(formatText("func f( {"), None)
    }
}
