package syntax_codegen

import std.unittest.*
import std.unittest.testmacro.*

func kindsFile(): KindsFile {
    KindsFile(
        grammar: "",
        kindsOutput: "",
        kindsPackage: "",
        astOutput: "",
        astPackage: "",
        trivia: [KindEntry(name: "Ws")],
        punctuation: [
            KindEntry(name: "Plus", text: "+"),
            KindEntry(name: "Minus", text: "-"),
            KindEntry(name: "DotDot", text: ".."),
            KindEntry(name: "LBracket", text: "["),
            KindEntry(name: "RBracket", text: "]"),
            KindEntry(name: "LParen", text: "("),
            KindEntry(name: "RParen", text: ")"),
            KindEntry(name: "Comma", text: ",")
        ],
        tokens: [KindEntry(name: "Int"), KindEntry(name: "Under", text: "_", word: true)],
        keywords: [KindEntry(name: "IfKw", text: "if"), KindEntry(name: "ElseKw", text: "else", contextual: true),
            KindEntry(name: "SpawnKw", text: "spawn")],
        nodes: [KindEntry(name: "Error")]
    )
}

let EXPRS = """
    E = Lit | Bin | Idx | If | Range
    Lit = 'Int'
    Bin = lhs:E op:('+' | '-') rhs:E
    Idx = base:E '[' (E (',' E)*)? ']'
    If = 'if' E Lit ('else' (Lit | elseIf:If))?
    Range = start:E? '..' end:E?
    """

func modelOf(grammar: String): Model {
    buildModel(kindsFile(), parseGrammar(grammar))
}

func bounds(start: Array<String>, end: Array<String>): String {
    let result = StringBuilder()
    if (!start.isEmpty()) {
        result.append(" after ${String.join(start, delimiter: "|")}")
    }
    if (!end.isEmpty()) {
        result.append(" before ${String.join(end, delimiter: "|")}")
    }
    result.toString()
}

func fieldsOf(model: Model, node: String): Array<String> {
    nodeIr(model, node).fields.map {
        f => match (f) {
            case NodeField(n, t, First) => "${n}: ${t} first"
            case NodeField(n, t, Nth(i, counted)) => "${n}: ${t} #${i} of ${counted.size}"
            case NodeField(n, t, All) => "${n}: ${t} all"
            case NodeField(n, t, AllFrom(i, counted)) => "${n}: ${t} all after ${i} of ${counted.size}"
            case NodeField(n, t, Between(start, end)) => "${n}: ${t}${bounds(start, end)}"
            case NodeField(n, t, AllBetween(start, end)) => "${n}: ${t} all${bounds(start, end)}"
            case TokenField(n, k, false) => "${n}: ${k}"
            case TokenField(n, k, true) => "${n}: ${k} many"
            case TokenSetField(n, ks) => "${n}: ${String.join(ks, delimiter: "|")}"
        }
    }
}

@Test
class ModelTest {
    @TestCase
    func tokensComeFirstThenTheNodesOfTheKindsFileThenThoseOfTheGrammar() {
        // act
        let sut = modelOf(EXPRS)

        // assert
        @Expect(sut.kinds.map {k => k.name},
            ["Ws", "Plus", "Minus", "DotDot", "LBracket", "RBracket", "LParen", "RParen", "Comma", "Int", "Under",
                "IfKw", "ElseKw", "SpawnKw", "Error", "Lit", "Bin", "Idx", "If", "Range"])
    }

    @TestCase
    func aRuleListingOnlyNodesIsAnEnumOfThem() {
        // act
        let sut = modelOf(EXPRS)

        // assert
        @Expect(sut.enums.map {e => e.name}, ["E"])
        @Expect(sut.enums[0].variants.map {v => "${v.name}(${v.typeName})"},
            ["AsLit(Lit)", "AsBin(Bin)", "AsIdx(Idx)", "AsIf(If)", "AsRange(Range)"])
        @Expect(sut.kindsOf("E"), ["Lit", "Bin", "Idx", "If", "Range"])
    }

    @TestCase
    func aLabelNamesTheVariant() {
        // act
        let sut = modelOf("S = Stmt:Lit | Other:Bin\nLit = 'Int'\nBin = Lit '+' Lit")

        // assert
        @Expect(sut.enums[0].variants.map {v => v.name}, ["Stmt", "Other"])
    }

    @TestCase
    func aVariantNamedLikeATypeIsRefused() {
        // act & assert
        @AssertThrows[GrammarException](modelOf("S = X | Y\nX = 'Int'\nY = 'Int'\nAsX = 'Int'"))
    }

    @TestCase
    func childrenOfOneTypeAreToldByTheTokensBetweenThem() {
        // act
        let sut = modelOf(EXPRS)

        // assert
        @Expect(fieldsOf(sut, "Bin"), ["lhs: E before Plus|Minus", "op: Plus|Minus", "rhs: E after Plus|Minus"])
        @Expect(fieldsOf(sut, "Idx"),
            ["base: E before LBracket", "lBracketToken: LBracket", "es: E all after LBracket", "commaToken: Comma many",
                "rBracketToken: RBracket"])
        // either end may be missing: the `..` tells them
        @Expect(fieldsOf(sut, "Range"), ["start: E before DotDot", "dotDotToken: DotDot", "end: E after DotDot"])
    }

    @TestCase
    func aTokenAfterAChildBoundsItWhenTheTokenBeforeItImpliesIt() {
        // act
        let sut = modelOf("E = Lit | Spawn\nLit = 'Int'\nSpawn = 'spawn' ('(' context:E ')')? Lit")

        // assert
        @Expect(fieldsOf(sut, "Spawn")[2], "context: E after LParen before RParen")
    }

    @TestCase
    func aChildTheRuleStartsWithIsToldByPosition() {
        // act
        let sut = modelOf("E = Lit | Call\nLit = 'Int'\nCall = callee:E Lit")

        // assert
        @Expect(fieldsOf(sut, "Call"), ["callee: E first", "lit: Lit #1 of 2"])
    }

    @TestCase
    func childrenNeitherTokensNorPositionCanTellAreLeftToBeWrittenByHand() {
        // act
        let sut = modelOf(EXPRS)
        let pair = modelOf("E = Lit | Pair\nLit = 'Int'\nPair = '[' first:E ',' second:E ',' ']'")

        // assert
        // `if 1 else 2`: the condition may be missing, and nothing tells it from the `Lit` after it
        @Expect(nodeIr(sut, "If").handWritten, ["e", "lits"])
        @Expect(fieldsOf(sut, "If"), ["ifToken: IfKw", "elseToken: ElseKw", "elseIf: If after ElseKw"])
        // a token twice is no bound
        @Expect(nodeIr(pair, "Pair").handWritten, ["first", "second"])
    }

    @TestCase
    func aReferenceToNothingDeclaredIsRefused() {
        // act & assert
        @AssertThrows[GrammarException](modelOf("A = B"))
        @AssertThrows[GrammarException](modelOf("A = '*'"))
    }

    @TestCase
    func anAccessorNamedLikeAMemberOfEveryViewOrAKeywordIsRefused() {
        // act & assert
        @AssertThrows[GrammarException](modelOf("A = syntax:B\nB = 'Int'"))
        @AssertThrows[GrammarException](modelOf("A = If\nIf = 'Int'"))
    }

    @TestCase
    func aTypeIsATy() {
        // act & assert
        @Expect(fieldsOf(modelOf("A = Type\nType = 'Int'"), "A"), ["ty: Type first"])
    }
}
