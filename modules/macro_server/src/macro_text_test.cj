package macro_server

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import cjsyntax.{parse, tokenize}

let AT_START = PositionData(fileId: 1, line: 1, column: 1)

/**
 * A token as a round trip compares them: its kind's name, its `#`s and its value.
 */
func kindsAndValues(tokens: Array<TokenData>, numbers: TokenNumbers): Array<String> {
    tokens.map {t => "${numbers.names[Int64(t.kind)]} #${t.delimiterNum} |${t.value ?? ""}|"}
}

/**
 * Where the tokens of `text` and those of their printed text first part, or `None` if they do not.
 */
func roundTripDifference(text: String, numbers: TokenNumbers): ?String {
    let tokens = macroTokens(text, numbers, AT_START)
    let printed = printMacroTokens(tokens, numbers)
    firstDifference(kindsAndValues(macroTokens(printed.text, numbers, AT_START), numbers),
        kindsAndValues(tokens, numbers))
}

/**
 * Pieces of Cangjie, those that glue to their neighbours above all, that a random text is made of.
 */
let PIECES: Array<String> = [
    ">", "=", ">>", ">=", "!", "in", "?", "??", ".", "..", "a", "b1", "1", "1.5", "$", "x", "@", "#", "(", ")", "[",
    "]", "<", "-", "*", "&", "|", ":", "\"s\"", "'s'", "\"a\${b}c\"", "#\"r\"#", "\"\"\"\nm\"\"\"", "r'c'", "b'x'",
    "J\"j\"", "`class`", "_", "true", "=>", "&&", "|>", "::", "\n", "{", "}", ",", ";", "This", "main", "!in "
]

let SEPARATORS: Array<String> = ["", " ", "\n"]

/**
 * The text random `picks` make of `PIECES`, each followed by a separator.
 */
func piecesText(picks: Array<UInt8>): String {
    let text = StringBuilder()
    for (p in picks) {
        let n = Int64(p)
        text.append(PIECES[n % PIECES.size])
        text.append(SEPARATORS[n / PIECES.size % SEPARATORS.size])
    }
    text.toString()
}

func tokenOf(numbers: TokenNumbers, name: String, value: String, delimiterNum!: UInt32 = 1): TokenData {
    TokenData(kind: numbers.numberOf(name), value: value, delimiterNum: delimiterNum)
}

@Test
@Configure[randomSeed: 176, generationSteps: 2000]
class PrintMacroTokensTest {
    let numbers = sdkNumbers()

    @TestCase[
        text in [
            "a >> b >= c >>= d >== e >=> f > g ?? h ??? i ? j",
            ">=>> >=>= >=>== >>=> >>=>= >==> >>> {x: Array<Int64>=> x} Array<Array<Int64>>",
            "x !in y; x ! in y; x !inside; x !in\ty; x !in(y); x !in\r\ny; x !in [y]; x !in ",
            "\"a\${b + \"c\${d}e\"}f\" 'q' 'a\"b' \"it's\" J\"j\" r'a' r\"b\" r\"'\" b'x' b\"y\"",
            "#\"raw\"# ##\"r#\"2\"## #'s'# #'a\"b'# #\"multi\nline\"#",
            "\"\"\"\nmulti \${x}\n\"\"\" '''\r\n  m '' \r\n''' \"\"\"\n\n\"\"\" '''\na\"\"\"b'''",
            "true false public open common features x::y This main perform",
            "`class` _ $x $(y) @! @Foo[1](2) a?.b?[0] a?(1) x.0 1.5.f() 1 .. 2 a...b",
            "// c\n/* b */ a\r\n\n\n b /* \n */ c",
            "1 0x1F 1.5 1e3 2i8 1.0f32 \"é\" é /*é*/ y",
            "quote($x + $(y) $ z) a / / b a * / b a / * b"
        ]
    ]
    func thePrintedTextIsCutIntoTheSameTokens(text: String): Unit {
        // act, assert
        @Expect(roundTripDifference(text, numbers), None<String>)
    }

    @TestCase[picks in random()]
    func aRandomTextLexedWithoutAnErrorIsCutIntoTheSameTokens(picks: Array<UInt8>): Unit {
        // arrange
        let text = piecesText(picks)
        if (!tokenize(text).lexErrors().isEmpty()) {
            return
        }

        // act, assert
        @Expect(roundTripDifference(text, numbers), None<String>)
    }

    @TestCase
    func eachTokensRangeIsItsTextAndItsPositionsAreTheServers(): Unit {
        // arrange
        let tokens = macroTokens("f(a, \"s\")\n#\"r\"# . x", numbers, PositionData(fileId: 3, line: 5, column: 7))

        // act
        let printed = printMacroTokens(tokens, numbers)

        // assert
        @Expect(printed.text, "f(a, \"s\")\n#\"r\"# .x")
        @Expect(printed.tokens.map {t => printed.text[t.range.start..t.range.end]},
            ["f", "(", "a", ",", "\"s\"", ")", "\n", "#\"r\"#", ".", "x"])
        @Expect(printed.tokens[4].begin.map {p => "${p.fileId} ${p.line}:${p.column}"}, "3 5:12")
        @Expect(printed.tokens[4].end.map {p => "${p.line}:${p.column}"}, "5:15")
        @Expect(printed.tokens[9].begin.map {p => "${p.line}:${p.column}"}, "6:9")
    }

    @TestCase
    func namesAndCallsArePrintedAsWrittenAndOtherTokensASpaceApart(): Unit {
        // arrange
        let text = "@Derive[ToString]\nextend<T> A<T> <: B<Array<T>> where T <: C { func f(x: T) { x.g(1)[0] + -1 } }"

        // act
        let printed = printMacroTokens(macroTokens(text, numbers, AT_START), numbers)

        // assert
        @Expect(printed.text,
            "@Derive[ToString]\nextend <T> A<T> <: B<Array<T >> where T <: C { func f(x: T) { x.g(1)[0] + - 1 } }")
    }

    @TestCase
    func aLiteralAMacroBuiltIsPrintedSoThatItLexesBack(): Unit {
        // arrange
        let tokens = [
            tokenOf(numbers, "STRING_LITERAL", "a\"b"),
            tokenOf(numbers, "STRING_LITERAL", "a\nb"),
            tokenOf(numbers, "MULTILINE_STRING", "x\"\"\"y"),
            tokenOf(numbers, "MULTILINE_RAW_STRING", "q\"#", delimiterNum: 2),
            tokenOf(numbers, "RUNE_LITERAL", "'"),
            tokenOf(numbers, "JSTRING_LITERAL", "j"),
            tokenOf(numbers, "IDENTIFIER", "class"),
            tokenOf(numbers, "NL", "")
        ]

        // act
        let printed = printMacroTokens(tokens, numbers)

        // assert
        @Expect(printed.text, "'a\"b' \"a\\nb\" '''\nx\"\"\"y''' ##\"q\"#\"## r\"'\" J\"j\" `class`\n")
    }

    /**
     * Every file of this repository and of std's sources (`.corpora/cangjie_runtime`, D65) that cjsyntax lexes
     * without an error.
     */
    @TestCase
    func theTokensOfEveryFileArePrintedIntoTextCutIntoThem(): Unit {
        // arrange
        let std = Path(".corpora/cangjie_runtime/stdlib")
        if (!exists(std)) {
            throw IllegalStateException("cangjie_runtime is not in .corpora/: run `python3 tests/corpora/fetch.py`")
        }
        let files = ArrayList<Path>()
        cjFilesUnder(Path("modules"), files)
        cjFilesUnder(std, files)

        // act
        var compared = 0
        let differences = ArrayList<String>()
        for (file in files) {
            let text = String.fromUtf8(File.readFrom(file))
            if (!tokenize(text).lexErrors().isEmpty()) {
                continue
            }
            compared++
            if (let Some(difference) <- roundTripDifference(text, numbers)) {
                differences.add("${file}: ${difference}")
            }
        }

        // assert
        @Expect(compared > 1000)
        @Expect(String.join(differences.toArray()[..min(differences.size, 20)], delimiter: "\n"), "")
    }

    @TestCase
    func whatTheServerAnswersForADeriveIsParsedWithoutAnError(): Unit {
        // arrange
        let paths = sdkPaths()
        let server = startMacroServer(paths)
        let result = server.connection.expand(
            deriveCall(paths, "Equatable", "class A { let x: Int64 = 1; let s: String = \"a\" }"))
        server.close()

        // act
        let printed = printMacroTokens(result.tks, numbers)

        // assert
        @Expect(result.status != MACRO_FAILED)
        @Expect(printed.tokens.size, result.tks.size)
        @Expect(printed.text.contains("extend A <: Equatable<A> {\npublic operator func ==(other: A): Bool {"))
        @Expect(printed.text.contains("let _: Equatable<Int64> = x"))
        @Expect(parse(printed.text).errors.map {e => e.toString()}, Array<String>())
    }
}
