package cjformat

import std.collection.min
import std.unittest.*
import std.unittest.testmacro.*

/**
 * `before` formatted is `after`, and `after` is left as it is.
 */
func check(before: String, after: String): Unit {
    @Expect(formatText(before), Some(after))
    @Expect(formatText(after), Some(after))
    @Expect(formattingProblems("fixture", before), [])
}

/**
 * `text` as a test writes it, in a raw string: the first line break and the indent the lines share
 * left out, a last line of spaces too.
 */
func code(text: String): String {
    let lines = text.split("\n")[1..]
    let body =
        if (lines[lines.size - 1].trimAscii().isEmpty()) { lines[..lines.size - 1] } else { lines }
    let indent =
        body
            .filter { line => !line.trimAscii().isEmpty() }
            .map { line => line.size - line.trimAsciiStart().size }
            .iterator() |>
            min
    let shared = indent ?? 0
    let joined =
        String
            .join(
                body.map { line => if (line.trimAscii().isEmpty()) { "" } else { line[shared..] } },
                delimiter: "\n"
            )
    "${joined}\n"
}

@Test
class FormatTest {
    @TestCase
    func shortListsAndExpressionsIgnoreTheAuthorsLineBreaks(): Unit {
        check(
            "func f(a: Int64,\n b: Int64) {\nlet x=g(a, h(b,\nc))\n}\n",
            "func f(a: Int64, b: Int64) {\n    let x = g(a, h(b, c))\n}\n"
        )
        check(
            "func f() {\nlet x=a +\nb\nRouter()\n.route(x)\n.route(y)\n}\n",
            "func f() {\n    let x = a + b\n    Router().route(x).route(y)\n}\n"
        )
    }

    @TestCase
    func longListsBreakOneElementPerLineAtTheFixedWidth(): Unit {
        // arrange
        let a = "firstArgumentWithAVeryLongDescriptiveName"
        let b = "secondArgumentWithAVeryLongDescriptiveName"
        let c = "thirdArgumentWithAVeryLongDescriptiveName"
        let source = "func f() { call(${a}, ${b}, ${c}) }"
        let expected =
            "func f() {\n    call(\n        ${a},\n        ${b},\n        ${c}\n    )\n}\n"

        // act
        let formatted = formatText(source)
        let problems = formattingProblems("fixture", source)

        // assert
        @Expect(formatted, Some(expected))
        @Expect(problems, [])
    }

    @TestCase
    func declarationsAndEmptyBodiesHaveOneLayout(): Unit {
        check(
            "class A <: B\n{ func f():Unit\n{ if(a)\n{ g() } else { h() } } }",
            "class A <: B {\n    func f(): Unit {\n        if (a) {\n            g()\n        } else {\n            h()\n        }\n    }\n}\n"
        )
        check("func f() { }", "func f() {}\n")
    }

    @TestCase
    func lambdasFlattenOnlyWhenTheyHaveOneStatement(): Unit {
        check(
            "func f() {\nxs\n.map { x =>\nx\n}\ng(a, { y =>\ny\n})\n}",
            "func f() {\n    xs.map { x => x }\n    g(a, { y => y })\n}\n"
        )
        check(
            "let f = { x: Int64 => a(x); b(x) }",
            "let f =\n    {\n        x: Int64 =>\n        a(x);\n        b(x)\n    }\n"
        )
    }

    @TestCase
    func matchArmsKeepTheirStatementBoundaries(): Unit {
        check(
            "func f() { match(x) { case 1 => a; b\ncase 2 | 3 => c } }",
            "func f() {\n    match (x) {\n        case 1 =>\n            a;\n            b\n        case 2 | 3 => c\n    }\n}\n"
        )
    }

    @TestCase
    func commentsStayOnTheirSideOfTokens(): Unit {
        check(
            "let a = 1 // a\nlet b = 2 // b\n\n// c\nlet c = 3\n",
            "let a = 1 // a\nlet b = 2 // b\n\n// c\nlet c = 3\n"
        )
        check(
            "func f() { g(a, // first\nb) }",
            "func f() {\n    g(\n        a, // first\n        b\n    )\n}\n"
        )
        check("func f() { /* empty */ }", "func f() {\n    /* empty */\n}\n")
        check(
            "func f() {\nif(a) // c\n{g()}\n}",
            "func f() {\n    if (a) // c\n    {\n        g()\n    }\n}\n"
        )
    }

    @TestCase
    func macrosKeepTheirTokenLayoutAndMoveAsAWhole(): Unit {
        check(
            "class A {\n  @TestCase[x in [\n        1,\n      2\n  ]]\n  func f(x: Int64) {\n      @Expect(x,\n         x)\n  }\n}\n",
            "class A {\n    @TestCase[x in [\n          1,\n        2\n    ]]\n    func f(x: Int64) {\n        @Expect(x,\n           x)\n    }\n}\n"
        )
        check(
            "func f() {\n        @M(\n  x\n          y)\n}\n",
            "func f() {\n    @M(\nx\n        y)\n}\n"
        )
    }

    @TestCase
    func aQuoteOnAContinuationFrameUsesItsActualLineIndent(): Unit {
        check(
            "func f() {\n    x += quote(\n        y\n    )\n}\n",
            "func f() {\n    x += quote(\n        y\n    )\n}\n"
        )
    }

    @TestCase
    func multilineStringsAndInterpolationsAreNotRewritten(): Unit {
        // arrange
        let value = "func f() {\n    let s = \"\"\"\n  a  \n        b\n\"\"\"\n}\n"

        // act
        let problems = formattingProblems("string", value)
        let formatted = formatText(value).getOrThrow()

        // assert
        @Expect(problems, [])
        @Expect(formatted.contains("\"\"\"\n  a  \n        b\n\"\"\""))
        check(#"let x = "${a+  b}""#, #"let x = "${a+  b}""# + "\n")
    }

    @TestCase
    func blockCommentsMoveWithoutLosingInternalAlignment(): Unit {
        check("func f() {\n/*\n * a  \n */\n}\n", "func f() {\n    /*\n     * a\n     */\n}\n")
        check(
            "class A {\n        /*\n  a\n    b\n        */\n}\n",
            "class A {\n    /*\na\n  b\n      */\n}\n"
        )
    }

    @TestCase
    func blankLinesAreKeptToOneAndTheFileEndsWithANewline(): Unit {
        check("\n\nlet a = 1   \n\n\n\nlet b = 2 // c  \n\n", "let a = 1\n\nlet b = 2 // c\n")
        check("let a = 1", "let a = 1\n")
        check("", "")
        check("   \n", "")
    }

    @TestCase
    func crlfLineBreaksAreKept(): Unit {
        check("func f() {\r\nx\r\n}", "func f() {\r\n    x\r\n}\r\n")
    }

    @TestCase
    func separateMinusTokensNeverBecomeADecrement(): Unit {
        check("let x = - - - 1", "let x = - - -1\n")
    }

    @TestCase
    func comparisonsInTuplesDoNotBecomeGenericCalls(): Unit {
        // arrange
        let text = "func f() { (a < b, c >\n(d)) }"

        // act
        let problems = formattingProblems("generic follower", text)
        let formatted = formatText(text).getOrThrow()

        // assert
        @Expect(problems, [])
        @Expect(formatted.contains("c >\n"))
    }

    @TestCase
    func aLongSignatureBreaksParametersBeforeItsShortReturnType(): Unit {
        // arrange
        let source =
            "func longFunctionName(first: LongParameterType, second: LongParameterType): Option<LongReturnType> {}"
        let expected =
            "func longFunctionName(\n    first: LongParameterType,\n    second: LongParameterType\n): Option<LongReturnType> {}\n"

        // act
        let formatted = formatText(source)
        let problems = formattingProblems("fixture", source)

        // assert
        @Expect(formatted, Some(expected))
        @Expect(problems, [])
    }

    @TestCase
    func longChainsBreakBeforeDotsAndUseOneContinuationIndent(): Unit {
        // arrange
        let a = "firstVeryLongDescriptiveMethodName"
        let b = "secondVeryLongDescriptiveMethodName"
        let c = "thirdVeryLongDescriptiveMethodName"
        let source = "func f() { value.${a}().${b}().${c}() }"
        let expected =
            "func f() {\n    value\n        .${a}()\n        .${b}()\n        .${c}()\n}\n"

        // act
        let formatted = formatText(source)
        let problems = formattingProblems("fixture", source)

        // assert
        @Expect(formatted, Some(expected))
        @Expect(problems, [])
    }

    @TestCase
    func annotationsDoNotForceAShortSignatureToBreak(): Unit {
        check(
            "@Frozen\nfunc f(x:Int64):Int64 {x}",
            "@Frozen\nfunc f(x: Int64): Int64 {\n    x\n}\n"
        )
    }

    @TestCase
    func syntaxErrorsRefuseTheWholeFile(): Unit {
        // arrange
        let source = "func f( {"

        // act
        let formatted = formatText(source)

        // assert
        @Expect(formatted, None)
    }
}
