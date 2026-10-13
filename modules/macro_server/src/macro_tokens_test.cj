package macro_server

import std.ast.{cangjieLex, getTokenKind}
import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * cjc's number of each token kind by its name, as std.ast numbers them (`getTokenKind`). std.ast
 * tells a single-quoted string from a double-quoted one, which cjc's numbering and the wire do not.
 */
let KIND_NUMBERS: HashMap<String, UInt8> = {
    =>
    let numbers = HashMap<String, UInt8>()
    for (n in 0..256) {
        try {
            numbers.addIfAbsent(getTokenKind(UInt16(n)).toString(), UInt8(n))
        } catch (_: Exception) {
            ()
        }
    }
    numbers.add("SINGLE_QUOTED_STRING_LITERAL", numbers["STRING_LITERAL"])
    numbers
}()

/**
 * The numbers of the SDK the tests run on.
 */
func sdkNumbers(): TokenNumbers {
    TokenNumbers.read(sdkPaths().tokensInc) ?? throw IllegalStateException("the SDK's Tokens.inc is not usable")
}

/**
 * A token as the tests compare them: its kind's number, where it starts, its `#`s and its value.
 */
func described(kind: UInt8, line: Int32, column: Int32, delimiterNum: UInt32, value: String): String {
    "${kind} ${line}:${column} #${delimiterNum} |${value}|"
}

func describedOurs(text: String, numbers: TokenNumbers): Array<String> {
    macroTokens(text, numbers, PositionData(fileId: 1, line: 1, column: 1)).map {
        t =>
        let begin = t.begin.getOrThrow()
        described(t.kind, begin.line, begin.column, t.delimiterNum, t.value ?? "")
    }
}

/**
 * The tokens cjc's lexer makes of `text` but its comments, or `None` if it rejects `text`.
 */
func describedCjcs(text: String): ?Array<String> {
    let tokens = try {
        cangjieLex(text)
    } catch (_: Exception) {
        return None
    }
    let cjcs = ArrayList<String>()
    for (t in tokens where t.kind.toString() != "COMMENT") {
        cjcs.add(described(KIND_NUMBERS[t.kind.toString()], t.pos.line, t.pos.column, UInt32(t.delimiterNum), t.value))
    }
    cjcs.toArray()
}

/**
 * Where `ours` and `cjcs` first part, or `None` if they do not.
 */
func firstDifference(ours: Array<String>, cjcs: Array<String>): ?String {
    for (i in 0..max(ours.size, cjcs.size)) {
        let a = if (i < ours.size) { ours[i] } else { "(none)" }
        let b = if (i < cjcs.size) { cjcs[i] } else { "(none)" }
        if (a != b) {
            return "token ${i}: ours ${a}, cjc's ${b}"
        }
    }
    None
}

func cjFilesUnder(dir: Path, into: ArrayList<Path>): Unit {
    for (info in Directory.readFrom(dir)) {
        if (info.isDirectory()) {
            cjFilesUnder(info.path, into)
        } else if (info.path.toString().endsWith(".cj")) {
            into.add(info.path)
        }
    }
}

@Test
class TokenNumbersTest {
    @TestCase
    func theSdksTokensIncNumbersTheKindsAsStdAstDoes(): Unit {
        // arrange, act
        let numbers = sdkNumbers()

        // assert
        @Expect(numbers.names.size > 150)
        for (n in 0..numbers.names.size) {
            // std.ast names `AT_EXCL` in full
            @Expect(getTokenKind(UInt16(n)).toString().replace("AT_EXCLAMATION", "AT_EXCL"), numbers.names[n])
        }
        @Expect(numbers.numberOf("ILLEGAL"), KIND_NUMBERS["ILLEGAL"])
    }

    @TestCase
    func cjlssOwnTableNumbersTheKindsAsTheSdksTokensIncDoes(): Unit {
        // act: the pinned nightly's, whatever its version (D104)
        let numbers = TokenNumbers.builtin("Cangjie Compiler: 1.3.0-alpha.20261002001050 (cjnative)").getOrThrow()

        // assert
        @Expect(numbers.names, sdkNumbers().names)
    }

    @TestCase
    func a1Point0SdkHasTheFirstKindsAndItsIllegalAndReadsTheKeywordsItLacksAsIdentifiers(): Unit {
        // act: as cangjie_compiler's v1.0.5 numbers them
        let numbers = TokenNumbers.builtin("Cangjie Compiler: 1.0.5 (cjnative)\nTarget: x86_64-unknown-linux-gnu").getOrThrow()

        // assert
        @Expect(numbers.names.size, 157)
        @Expect(numbers.names[..156], sdkNumbers().names[..156])
        @Expect(numbers.numberOf("ILLEGAL"), 156)
        @Expect(numbers.numberOf("COMMON"), numbers.numberOf("IDENTIFIER"))
        @Expect(numbers.numberOf("DOUBLE_COLON"), numbers.numberOf("IDENTIFIER"))
    }

    @TestCase
    func aVersionBefore1Point0OrOfNoNumbersHasNoTable(): Unit {
        // act, assert
        @Expect(TokenNumbers.builtin("Cangjie Compiler: 0.53.13 (cjnative)").isNone())
        @Expect(TokenNumbers.builtin("not a compiler").isNone())
    }

    @TestCase
    func aTokensIncLackingAKindSentIsRefused(): Unit {
        // arrange
        let text = String.fromUtf8(File.readFrom(sdkPaths().tokensInc))

        // act
        let numbers = TokenNumbers.parse(text.replace("TOKEN(NL,", "TOKEN(NEWLINE,"))

        // assert
        @Expect(numbers.isNone())
    }

    @TestCase
    func aTokensIncThatIsNotThereIsNone(): Unit {
        // act, assert
        @Expect(TokenNumbers.read(sdkPaths().tokensInc.join("missing")).isNone())
    }
}

@Test
class MacroTokensTest {
    let numbers = sdkNumbers()

    @TestCase[
        text in [
            "a >> b >= c >>= d >== e >=> f > g ?? h ??? i ? j",
            ">=>> >=>= >=>== >>=> >>=>= >==> >>> {x: Array<Int64>=> x}",
            "x !in y; x ! in y; x !inside; x !in\ty; x !in(y); x !in\r\ny; x !in",
            "\"a\${b + \"c\${d}e\"}f\" 'q' J\"j\" r'a' r\"b\" b'x' b\"y\"",
            "#\"raw\"# ##\"r#\"2\"## #'s'#",
            "\"\"\"\nmulti \${x}\n\"\"\" '''\r\n  m '' \r\n'''",
            "true false public open common features x::y This main perform",
            "`class` _ $x $(y) @! @Foo[1](2)",
            "// c\n/* b */ a\r\n\n\n b /* \n */ c",
            "1 0x1F 1.5 1e3 2i8 1.0f32 \"é\" é /*é*/ y"
        ]
    ]
    func theTokensAreTheOnesCjcLexes(text: String): Unit {
        // act
        let ours = describedOurs(text, numbers)

        // assert
        @Expect(firstDifference(ours, describedCjcs(text).getOrThrow()), None<String>)
    }

    @TestCase
    func aTokenOnTheFirstLineStartsWhereTheTextDoes(): Unit {
        // act
        let tokens = macroTokens("ab cd\nef", numbers, PositionData(fileId: 7, line: 3, column: 5))

        // assert
        let placed = {p: ?PositionData => p.map {q => "${q.fileId} ${q.line}:${q.column}"} ?? ""}
        @Expect(tokens.map {t => placed(t.begin)}, ["7 3:5", "7 3:8", "7 3:10", "7 4:1"])
        @Expect(placed(tokens[1].end), "7 3:10")
    }

    /**
     * Every file of this repository and of std's sources (`.corpora/cangjie_runtime`, D65) that cjc's lexer takes.
     */
    @TestCase
    func theTokensOfEveryFileAreTheOnesCjcLexes(): Unit {
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
            let cjcs = describedCjcs(text) ?? continue
            compared++
            if (let Some(difference) <- firstDifference(describedOurs(text, numbers), cjcs)) {
                differences.add("${file}: ${difference}")
            }
        }

        // assert
        @Expect(compared > 1000)
        @Expect(String.join(differences.toArray()[..min(differences.size, 20)], delimiter: "\n"), "")
    }
}
