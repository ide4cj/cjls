package macro_server

import std.ast.{cangjieLex, getTokenKind, Token as SdkToken}
import std.collection.{ArrayList, map}
import std.unittest.*
import std.unittest.prop_test.*
import std.unittest.testmacro.*

let RELEX_NUMBERS = sdkNumbers()

/** Lexable default spellings from this SDK, plus values a macro may put in an identifier. */
func relexSources(): Array<String> {
    let sources = ArrayList<String>()
    let numbers = RELEX_NUMBERS
    for (i in 0..numbers.names.size) {
        let value = SdkToken(getTokenKind(UInt16(i))).value
        if (value.isEmpty()) {
            continue
        }
        try {
            cangjieLex(value)
            sources.add(value)
        } catch (_: Exception) {
            ()
        }
    }
    sources.add(all: ["x", "é", "`Int8`", "`class`", "true", "false", "1", "1.5", "0xff", "2i8", "1e3",
        "\"s\"", "'s'", "r'c'", "b'x'", "J\"j\"", "#\"raw\"#", "\"\"\"\ntext\"\"\"", "a.b", "a + b", "Array<Int8>", "!in ", "1.5x..", "1.5x..=", "1.5x..2"])
    sources.toArray()
}

let RELEX_SOURCES = relexSources()

/** Preserves the SDK's token values rather than deriving the expected tokens through macroTokens. */
func sdkWireTokens(source: String): Array<TokenData> {
    let tokens = cangjieLex(source)
    Array(tokens.size) {i =>
        let t = tokens[i]
        TokenData(kind: KIND_NUMBERS[t.kind.toString()], value: t.value, delimiterNum: UInt32(t.delimiterNum))
    }
}

/**
 * cjc's ProcessCombinedToken projection, with the SDK lexer as the oracle for identifier values. Positions
 * are excluded except for the adjacency inside composite operators (`joint`): this compares parser token
 * kinds, literal values and raw delimiters, not source mapping. The four split cases mirror MacroProcess.cpp;
 * identifier transformations and the printed text are lexed by the actual SDK. UNIT_LITERAL and `()`
 * compare as the same unit constant, as ParseAtom accepts both.
 */
func sdkProcessed(tokens: Array<TokenData>, relexIdentifiers!: Bool): Array<String> {
    let out = ArrayList<String>()
    let numbers = RELEX_NUMBERS
    for (t in tokens) {
        let name = numbers.names[Int64(t.kind)]
        if (relexIdentifiers && name == "IDENTIFIER") {
            out.add(all: sdkProcessed(sdkWireTokens(t.value ?? ""), relexIdentifiers: false))
            continue
        }
        let atoms: Array<String> = match (name) {
            case "COALESCING" => ["QUEST |?|", "joint QUEST |?|"]
            case "RSHIFT" => ["GT |>|", "joint GT |>|"]
            case "RSHIFT_ASSIGN" => ["GT |>|", "joint GT |>|", "joint ASSIGN |=|"]
            case "GE" => ["GT |>|", "joint ASSIGN |=|"]
            // ParseAtom accepts both UNIT_LITERAL and the lexer's `(` `)` as the same unit constant.
            case "UNIT_LITERAL" => ["LPAREN |(|", "RPAREN |)|"]
            case "COMMENT" | "END" => []
            case "NL" => ["NL"]
            case "MULTILINE_RAW_STRING" => ["${name} #${t.delimiterNum} |${t.value ?? ""}|"]
            case _ => ["${name} |${t.value ?? ""}|"]
        }
        out.add(all: atoms)
    }
    out.toArray()
}

/** The printer's text must have the same parser tokens as independently processing its input with the SDK. */
func relexDifference(tokens: Array<TokenData>): ?String {
    let expected = sdkProcessed(tokens, relexIdentifiers: true)
    let printed = printMacroTokens(tokens, RELEX_NUMBERS).text
    let actual = try {
        sdkProcessed(sdkWireTokens(printed), relexIdentifiers: false)
    } catch (_: Exception) {
        return "SDK rejected printed text: ${printed}; expected ${expected}"
    }
    firstDifference(actual, expected).map {difference => "${printed}: ${difference}"}
}

/** Chooses ordinary SDK tokens or a constructed identifier containing their entire source. */
func relexInput(picks: Array<UInt16>): Array<TokenData> {
    let numbers = RELEX_NUMBERS
    let out = ArrayList<TokenData>()
    for (pick in picks) {
        let n = Int64(pick)
        let source = RELEX_SOURCES[n / 2 % RELEX_SOURCES.size]
        if (n % 2 == 0) {
            out.add(all: sdkWireTokens(source))
        } else {
            out.add(tokenOf(numbers, "IDENTIFIER", source))
        }
    }
    out.toArray()
}

@Test
@Configure[generationSteps: 2000]
class MacroRelexTest {
    @TestCase
    func everyRepresentableDefaultSdkTokenKeepsItsParserMeaning(): Unit {
        let numbers = RELEX_NUMBERS
        for (i in 0..numbers.names.size) {
            let value = SdkToken(getTokenKind(UInt16(i))).value
            if (value.isEmpty()) {
                continue
            }
            let lexed = try {
                sdkWireTokens(value)
            } catch (_: Exception) {
                continue
            }
            // These experimental kinds have no spelling in the SDK's active source dialect. Their values
            // still participate as constructed identifiers; forcing the inactive kind cannot round-trip.
            if (["PERFORM", "RESUME", "THROWING", "HANDLE"].contains(numbers.names[i]) && lexed.size == 1 &&
                lexed[0].kind == numbers.numberOf("IDENTIFIER")) {
                continue
            }
            @Expect(relexDifference([TokenData(kind: UInt8(i), value: value)]), None<String>)
        }
    }

    @TestCase[source in RELEX_SOURCES]
    func aConstructedIdentifierCanBecomeAnyLexableSdkTokenOrSequence(source: String): Unit {
        @Expect(relexDifference([tokenOf(RELEX_NUMBERS, "IDENTIFIER", source)]), None<String>)
    }

    @TestCase[source in RELEX_SOURCES]
    func relexingPreservesBoundariesWithNeighbouringTokens(source: String): Unit {
        let token = tokenOf(RELEX_NUMBERS, "IDENTIFIER", source)
        for (neighbour in ["x", "1", ".", "(", "[", ">", "?", ":", ";", "!in ", "@", "$", "#\"x\"#"]) {
            let others = sdkWireTokens(neighbour)
            @Expect(relexDifference([token].concat(others)), None<String>)
            @Expect(relexDifference(others.concat([token])), None<String>)
        }
    }

    @TestCase
    func relexedTokensKeepPositionsInsideTheOriginalValue(): Unit {
        let token = TokenData(kind: RELEX_NUMBERS.numberOf("IDENTIFIER"), value: "a.b",
            begin: PositionData(fileId: 7, line: 3, column: 5), end: PositionData(fileId: 7, line: 3, column: 8))
        let printed = printMacroTokens([token], RELEX_NUMBERS)
        @Expect(printed.text, "a.b")
        @Expect(printed.tokens.map {t => printed.text[t.range.start..t.range.end]}, ["a", ".", "b"])
        @Expect(printed.tokens.map {t => t.begin.map {p => "${p.fileId} ${p.line}:${p.column}"}},
            [Some("7 3:5"), Some("7 3:6"), Some("7 3:7")])
        @Expect(printed.tokens.map {t => t.end.map {p => p.column.toString()}}, [Some("6"), Some("7"), Some("8")])
        @Expect(printMacroTokens([tokenOf(RELEX_NUMBERS, "IDENTIFIER", "a.b")], RELEX_NUMBERS).tokens
            .iterator().all {t => t.begin.isNone() && t.end.isNone()})
    }

    @TestCase[picks in random()]
    func arbitraryLexableIdentifierValuesMatchSdkPostprocessing(picks: Array<UInt8>): Unit {
        let source = piecesText(picks)
        try {
            sdkWireTokens(source)
        } catch (_: Exception) {
            return
        }
        @Expect(relexDifference([tokenOf(RELEX_NUMBERS, "IDENTIFIER", source)]), None<String>)
    }
}

/**
 * Bounds the work per generated stream: Array's default generator allows 4000 elements, and cjc's
 * comparison instrumentation retains pinned memory on enum matches (D24). Each piece invokes the lexer.
 */
struct RelexChoices <: ToString {
    RelexChoices(let picks: Array<UInt16>) {}

    public func toString(): String {
        "[${String.join(picks.map {pick => pick.toString()}, delimiter: ", ")}]"
    }
}

extend RelexChoices <: Arbitrary<RelexChoices> {
    public static func arbitrary(random: RandomSource): Generator<RelexChoices> {
        Generators.generate {
            RelexChoices(Array(random.nextInt64(33)) {_ => random.suggestUInt16()})
        }
    }
}

extend RelexChoices <: Shrink<RelexChoices> {
    public func shrink(): Iterable<RelexChoices> {
        picks.shrink() |> map {values: Array<UInt16> => RelexChoices(values)}
    }
}

@Test
@Configure[coverageGuided: true, generationSteps: 2000]
class MacroRelexCoverageGuidedTest {
    @TestCase[choices in random()]
    func arbitraryConstructedAndOrdinaryTokensMatchSdkPostprocessing(choices: RelexChoices): Unit {
        @Expect(relexDifference(relexInput(choices.picks)), None<String>)
    }
}
