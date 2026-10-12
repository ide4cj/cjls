package cjls.handlers

import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import stdxx.Nullable
import rope.{Encoding, Rope}
import loupe.{Fold, FoldKind, TextRange}
import cjls.lsp_types.*
import cjls.server.*

/**
 * `startLine:startCharacter..endLine:endCharacter kind`, a column or the kind left out when there is
 * none.
 */
func shown(range: FoldingRange): String {
    let column = {character: ?UInt32 => character.map {it => ":${it}"} ?? ""}
    let kind = range.kind.map {it => " ${it.value}"} ?? ""
    "${range.startLine}${column(range.startCharacter)}..${range.endLine}${column(range.endCharacter)}${kind}"
}

func shownFolds(text: String, folds: Array<Fold>, encoding!: Encoding = Encoding.Utf16,
    lineFoldingOnly!: Bool = true, limit!: ?Int64 = None): Array<String> {
    foldingRanges(Rope(text), folds, encoding, lineFoldingOnly, limit).map {it => shown(it)}
}

func documentFolds(state: ServerState, uri: String): ?Array<String> {
    match (handleFoldingRange(state.snapshot(), FoldingRangeParams(textDocument: TextDocumentIdentifier(uri: uri)))) {
        case Nullable.Value(ranges) => ranges.map {it => shown(it)}
        case Nullable.Null => None
    }
}

func foldingCapabilities(lineFoldingOnly: ?Bool, rangeLimit: ?UInt32): ClientCapabilities {
    ClientCapabilities(textDocument: TextDocumentClientCapabilities(
        foldingRange: FoldingRangeClientCapabilities(lineFoldingOnly: lineFoldingOnly, rangeLimit: rangeLimit)))
}

@Test
class FoldingRangeTranslationTest {
    /**
     * `(encoding, column of {)`: the emoji is four bytes and two UTF-16 units.
     */
    @TestCase[row in [(Encoding.Utf8, "0:5..1:1"), (Encoding.Utf16, "0:3..1:1")]]
    func columnsAreCountedInTheEncodingAgreedOn(row: (Encoding, String)) {
        // arrange
        let (encoding, expected) = row

        // act
        let result = shownFolds("😀 {\n}", [Fold(TextRange(5, 8), FoldKind.Block)], encoding: encoding,
            lineFoldingOnly: false)

        // assert
        @Expect(result, [expected])
    }

    @TestCase
    func aClientFoldingLinesOnlyGetsLinesAndKindsForCommentsAndImportsAlone() {
        // arrange
        let text = "// a\n// b\nimport a.b\nimport c.d\nmain() {\n}"
        let folds = [Fold(TextRange(0, 9), FoldKind.Comment), Fold(TextRange(10, 31), FoldKind.Imports),
            Fold(TextRange(39, 42), FoldKind.Block)]

        // act
        let result = shownFolds(text, folds)

        // assert
        @Expect(result, ["0..1 comment", "2..3 imports", "4..5"])
    }

    @TestCase
    func aFoldFollowedOnItsLastLineEndsALineEarlier() {
        // arrange - `} else {`, then a `}` with only spaces after it
        let text = "if (c) {\n    a\n} else {\n    b\n}  "
        let folds = [Fold(TextRange(7, 16), FoldKind.Block), Fold(TextRange(22, 31), FoldKind.Block)]

        // act
        let result = shownFolds(text, folds)

        // assert
        @Expect(result, ["0..1", "2..4"])
    }

    @TestCase
    func aFoldLeftWithOneLineIsDropped() {
        // act
        let result = shownFolds("f({\n}, {\n})", [Fold(TextRange(2, 5), FoldKind.Block), Fold(TextRange(7, 10),
            FoldKind.Block)])

        // assert - the second ends with `)` after it
        @Expect(result, Array<String>())
    }

    @TestCase
    func theLimitKeepsTheFirstByStart() {
        // arrange
        let text = "{\n{\n}\n}\n{\n}"
        let folds = [Fold(TextRange(0, 7), FoldKind.Block), Fold(TextRange(2, 5), FoldKind.Block),
            Fold(TextRange(8, 11), FoldKind.Block)]

        // act
        let result = shownFolds(text, folds, lineFoldingOnly: false, limit: 2)

        // assert
        @Expect(result, ["0:0..3:1", "1:0..2:1"])
    }
}

@Test
class FoldingRangeTest {
    @TestCase
    func anOpenDocumentFoldsByItsTree() {
        // arrange
        let state = opened("class A {\n    func f() {\n        1\n    }\n}\n")

        // act
        let result = documentFolds(state, URI).getOrThrow()

        // assert - columns, as the client said nothing
        @Expect(result, ["0:8..4:1", "1:13..3:5"])
    }

    @TestCase
    func aDocumentTheServerDoesNotKnowHasNoFolds() {
        // act, assert
        @Expect(documentFolds(ServerState(), URI).isNone())
    }

    @TestCase
    func foldingIsAdvertised() {
        // act
        let result = handleInitialize(ServerState(), Client(), NoopLogger(),
            InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null,
                capabilities: ClientCapabilities()))

        // assert
        match (result.capabilities.foldingRangeProvider) {
            case Some(BooleanOrFoldingRangeOptionsOrFoldingRangeRegistrationOptions.AsBoolean(it)) => @Expect(it)
            case _ => @Fail("no folding advertised")
        }
    }

    @TestCase[row in [
        (foldingCapabilities(true, 100), true, Some(100)),
        (foldingCapabilities(Option<Bool>.None, Option<UInt32>.None), false, Option<Int64>.None),
        (ClientCapabilities(), false, None)
    ]]
    func whatTheClientSaysOfFoldingIsKept(row: (ClientCapabilities, Bool, ?Int64)) {
        // arrange
        let (capabilities, lineFoldingOnly, limit) = row
        let state = ServerState()

        // act
        handleInitialize(state, Client(), NoopLogger(),
            InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null,
                capabilities: capabilities))

        // assert
        @Expect(state.lineFoldingOnly, lineFoldingOnly)
        @Expect(state.foldingRangeLimit, limit)
    }

    @TestCase
    func aClientFoldingLinesOnlyGetsThemFromTheSnapshot() {
        // arrange
        let state = opened("func f() {\n    1\n}\n")
        state.lineFoldingOnly = true
        state.foldingRangeLimit = 0

        // act, assert
        @Expect(documentFolds(state, URI), Some(Array<String>()))
    }
}
