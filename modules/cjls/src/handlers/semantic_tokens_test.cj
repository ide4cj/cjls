package cjls.handlers

import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import stdxx.Nullable
import rope.{Encoding, Rope}
import loupe.*
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange
import cjls.server.*

// indices into the legend: types
let KEYWORD: UInt32 = 0
let COMMENT: UInt32 = 1
let NUMBER: UInt32 = 3
let OPERATOR: UInt32 = 4
let CLASS: UInt32 = 8
let VARIABLE: UInt32 = 17
// and bits of modifiers
let DECLARATION: UInt32 = 1
let READONLY: UInt32 = 4

func semanticTokensData(state: ServerState, uri: String): ?Array<UInt32> {
    match (handleSemanticTokensFull(state.snapshot(), SemanticTokensParams(textDocument: TextDocumentIdentifier(uri: uri)))) {
        case Nullable.Value(tokens) => tokens.data
        case Nullable.Null => None
    }
}

@Test
class SemanticTokensEncodingTest {
    @TestCase
    func tokensOnALineAreRelativeToTheOneBefore() {
        // arrange
        let tokens = [
            HighlightedRange(TextRange(0, 3), HighlightTag.Keyword),
            HighlightedRange(TextRange(4, 5), HighlightTag.Symbol(StructureKind.Variable),
                modifiers: HighlightModifiers.NONE.plus(HighlightModifier.Declaration).plus(HighlightModifier.Readonly)),
            HighlightedRange(TextRange(8, 9), HighlightTag.NumberLiteral)
        ]

        // act
        let result = semanticTokens(Rope("let a = 1"), tokens, Encoding.Utf16, false)

        // assert
        @Expect(result.data, [0, 0, 3, KEYWORD, 0, 0, 4, 1, VARIABLE, DECLARATION | READONLY, 0, 4, 1, NUMBER, 0])
    }

    @TestCase
    func aPackageAnUnresolvedNameAndAVarGoAsTheLegendsOwnTypesAndModifier() {
        // arrange
        let legend = semanticTokensLegend()
        let tokens = [
            HighlightedRange(TextRange(0, 1), HighlightTag.Namespace),
            HighlightedRange(TextRange(2, 3), HighlightTag.UnresolvedReference),
            HighlightedRange(TextRange(4, 5), HighlightTag.Symbol(StructureKind.Variable),
                modifiers: HighlightModifiers.NONE.plus(HighlightModifier.Mutable))
        ]

        // act
        let data = semanticTokens(Rope("a b c"), tokens, Encoding.Utf16, false).data

        // assert - D19's types keep their indices, the new ones come after
        @Expect(legend.tokenTypes[Int64(data[3])], "namespace")
        @Expect(legend.tokenTypes[Int64(data[8])], "unresolvedReference")
        @Expect(legend.tokenTypes[Int64(data[13])], "variable")
        @Expect(legend.tokenModifiers[6], "mutable")
        @Expect(data[14], 1u32 << 6)
    }

    @TestCase
    func aClientAugmentingItsGrammarGetsOnlyWhatTheGrammarCannotName() {
        // arrange
        let documentation = HighlightModifiers.NONE.plus(HighlightModifier.Documentation)
        let variable = HighlightedRange(TextRange(4, 5), HighlightTag.Symbol(StructureKind.Variable))
        let docComment = HighlightedRange(TextRange(10, 16), HighlightTag.Comment, modifiers: documentation)
        let tokens = [
            HighlightedRange(TextRange(0, 3), HighlightTag.Keyword),
            variable,
            HighlightedRange(TextRange(6, 7), HighlightTag.Operator),
            HighlightedRange(TextRange(8, 9), HighlightTag.NumberLiteral),
            docComment,
            HighlightedRange(TextRange(17, 20), HighlightTag.StringLiteral),
            HighlightedRange(TextRange(21, 24), HighlightTag.Comment)
        ]

        // act
        let augmenting = overSyntax(tokens, true)
        let alone = overSyntax(tokens, false)

        // assert - a comment the grammar cannot tell documents is kept
        @Expect(augmenting, [variable, docComment])
        @Expect(alone, tokens)
    }

    /**
     * `(encoding, column of a)`: the emoji is four bytes, two UTF-16 units and one character.
     */
    @TestCase[row in [(Encoding.Utf8, UInt32(5)), (Encoding.Utf16, UInt32(3)), (Encoding.Utf32, UInt32(2))]]
    func columnsAreCountedInTheEncodingAgreedOn(row: (Encoding, UInt32)) {
        // arrange
        let (encoding, column) = row
        let tokens = [HighlightedRange(TextRange(5, 6), HighlightTag.TypeName),
            HighlightedRange(TextRange(7, 8), HighlightTag.TypeName)]

        // act
        let result = semanticTokens(Rope("😀 a\nb"), tokens, encoding, false)

        // assert - a new line starts its column over
        @Expect(result.data, [0, column, 1, 7, 0, 1, 0, 1, 7, 0])
    }

    @TestCase
    func aTokenOverSeveralLinesIsCutAtEachLineEndLeavingEmptyLinesOut() {
        // arrange
        let text = "/* a\n\nbc */ x"

        // act
        let result = semanticTokens(Rope(text), [HighlightedRange(TextRange(0, 11), HighlightTag.Comment)],
            Encoding.Utf16, false)

        // assert
        @Expect(result.data, [0, 0, 4, COMMENT, 0, 2, 0, 5, COMMENT, 0])
    }

    @TestCase
    func aClientTakingMultilineTokensGetsOneWhole() {
        // arrange
        let text = "/* a\n\nbc */ x"

        // act
        let result = semanticTokens(Rope(text), [HighlightedRange(TextRange(0, 11), HighlightTag.Comment)],
            Encoding.Utf16, true)

        // assert - the line breaks count
        @Expect(result.data, [0, 0, 11, COMMENT, 0])
    }
}

@Test
class SemanticTokensTest {
    @TestCase
    func aWholeDocumentIsHighlighted() {
        // arrange
        let state = opened("class A {}")

        // act
        let data = semanticTokensData(state, URI).getOrThrow()

        // assert
        @Expect(data, [0, 0, 5, KEYWORD, 0, 0, 6, 1, CLASS, DECLARATION])
    }

    @TestCase
    func aRangeGetsTheTokensItHoldsCountedFromTheDocumentStart() {
        // arrange
        let state = opened("let a = 1\nlet b = 2")
        let range = LspRange(start: Position(line: 1, character: 0), end: Position(line: 1, character: 9))

        // act
        let result = handleSemanticTokensRange(state.snapshot(),
            SemanticTokensRangeParams(textDocument: TextDocumentIdentifier(uri: URI), range: range))

        // assert
        match (result) {
            case Nullable.Value(tokens) => @Expect(tokens.data,
                [1, 0, 3, KEYWORD, 0, 0, 4, 1, VARIABLE, DECLARATION | READONLY, 0, 2, 1, OPERATOR, 0, 0, 2, 1, NUMBER, 0])
            case Nullable.Null => @Fail("no tokens for an open document")
        }
    }

    @TestCase
    func aDocumentTheServerDoesNotKnowHasNoTokens() {
        // act, assert
        @Expect(semanticTokensData(ServerState(), URI).isNone())
    }

    @TestCase
    func fullAndRangeAreAdvertisedWithTheLegend() {
        // act
        let result = handleInitialize(ServerState(), Client(), NoopLogger(),
            InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null,
                capabilities: ClientCapabilities()))

        // assert
        match (result.capabilities.semanticTokensProvider) {
            case Some(SemanticTokensOptionsOrSemanticTokensRegistrationOptions.AsSemanticTokensOptions(options)) =>
                @Expect(options.legend.tokenTypes[Int64(CLASS)], "class")
                @Expect(options.legend.tokenModifiers[0], "declaration")
                let full = match (options.full) {
                    case Some(BooleanOrSemanticTokensFullDelta.AsBoolean(it)) => it
                    case _ => false
                }
                let range = match (options.range) {
                    case Some(BooleanOrSemanticTokensOptionsRange.AsBoolean(it)) => it
                    case _ => false
                }
                @Expect(full)
                @Expect(range)
            case _ => @Fail("no semantic tokens advertised")
        }
    }

    @TestCase[row in [
        (ClientCapabilities(textDocument: TextDocumentClientCapabilities(semanticTokens: SemanticTokensClientCapabilities(
            requests: ClientSemanticTokensRequestOptions(), tokenTypes: [], tokenModifiers: [],
            formats: [TokenFormat.Relative], multilineTokenSupport: true))), true),
        (ClientCapabilities(textDocument: TextDocumentClientCapabilities(semanticTokens: SemanticTokensClientCapabilities(
            requests: ClientSemanticTokensRequestOptions(), tokenTypes: [], tokenModifiers: [],
            formats: [TokenFormat.Relative]))), false),
        (ClientCapabilities(), false)
    ]]
    func tokensSpanLinesOnlyForAClientThatSaysItTakesThem(row: (ClientCapabilities, Bool)) {
        // arrange
        let (capabilities, multiline) = row
        let state = ServerState()

        // act
        handleInitialize(state, Client(), NoopLogger(),
            InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null,
                capabilities: capabilities))

        // assert
        @Expect(state.multilineTokens, multiline)
    }

    @TestCase[row in [
        (ClientCapabilities(textDocument: TextDocumentClientCapabilities(semanticTokens: SemanticTokensClientCapabilities(
            requests: ClientSemanticTokensRequestOptions(), tokenTypes: [], tokenModifiers: [],
            formats: [TokenFormat.Relative], augmentsSyntaxTokens: true))), true),
        (ClientCapabilities(textDocument: TextDocumentClientCapabilities(semanticTokens: SemanticTokensClientCapabilities(
            requests: ClientSemanticTokensRequestOptions(), tokenTypes: [], tokenModifiers: [],
            formats: [TokenFormat.Relative]))), false),
        (ClientCapabilities(), false)
    ]]
    func tokensAugmentAGrammarOnlyForAClientThatSaysItHasOne(row: (ClientCapabilities, Bool)) {
        // arrange
        let (capabilities, augments) = row
        let state = ServerState()

        // act
        handleInitialize(state, Client(), NoopLogger(),
            InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null,
                capabilities: capabilities))

        // assert
        @Expect(state.augmentsSyntaxTokens, augments)
    }

    @TestCase
    func aDocumentOfAClientAugmentingItsGrammarHasNoKeywordToken() {
        // arrange
        let state = opened("class A {}")
        state.augmentsSyntaxTokens = true

        // act
        let data = semanticTokensData(state, URI).getOrThrow()

        // assert
        @Expect(data, [0, 6, 1, CLASS, DECLARATION])
    }

    @TestCase
    func aConstructorAndAConstantGoByTheTypesTheGrammarsName() {
        // arrange
        let state = opened("class A {\n    A() {}\n}\nconst K = 1")
        state.augmentsSyntaxTokens = true
        let legend = semanticTokensLegend()

        // act
        let data = semanticTokensData(state, URI).getOrThrow()

        // assert - `class A`, then the constructor `A`, then `K`
        @Expect(data.size, 15)
        @Expect(legend.tokenTypes[Int64(data[8])], "constructor")
        @Expect(legend.tokenTypes[Int64(data[13])], "constant")
        @Expect(data[14], DECLARATION | READONLY)
    }

    @TestCase[row in [
        (ClientCapabilities(workspace: WorkspaceClientCapabilities(semanticTokens: SemanticTokensWorkspaceClientCapabilities(
            refreshSupport: true))), true),
        (ClientCapabilities(workspace: WorkspaceClientCapabilities(semanticTokens: SemanticTokensWorkspaceClientCapabilities())),
            false),
        (ClientCapabilities(), false)
    ]]
    func tokensAreRefreshedOnlyForAClientThatSaysItAsksAgain(row: (ClientCapabilities, Bool)) {
        // arrange
        let (capabilities, refreshes) = row
        let state = ServerState()

        // act
        handleInitialize(state, Client(), NoopLogger(),
            InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null,
                capabilities: capabilities))

        // assert
        @Expect(state.refreshesSemanticTokens, refreshes)
    }
}
