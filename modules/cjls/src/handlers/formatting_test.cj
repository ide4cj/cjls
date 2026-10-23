package cjls.handlers

import std.unittest.*
import std.unittest.testmacro.*
import stdxx.Nullable
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange
import cjls.server.*

func formattingEdits(state: ServerState, uri: String): ?Array<TextEdit> {
    let params =
        DocumentFormattingParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            options: FormattingOptions(tabSize: 2, insertSpaces: true)
        )
    match (handleFormatting(state.snapshot(), params)) {
        case Nullable.Value(edits) => edits
        case Nullable.Null => None
    }
}

func rangeFormattingEdits(state: ServerState, uri: String, range: LspRange): ?Array<TextEdit> {
    let params =
        DocumentRangeFormattingParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            range: range,
            options: FormattingOptions(tabSize: 2, insertSpaces: true)
        )
    match (handleRangeFormatting(state.snapshot(), params)) {
        case Nullable.Value(edits) => edits
        case Nullable.Null => None
    }
}

@Test
class FormattingTest {
    @TestCase
    func theEditsAreInTheColumnsAgreedOnAndIgnoreTheClientsIndent() {
        // arrange - the emoji is two UTF-16 units and four bytes
        let state = opened("let s = \"😀\"  +  \"x\"\n")

        // act
        let edits = formattingEdits(state, URI).getOrThrow()

        // assert
        @Expect(edits.size, 1)
        @Expect(edits[0].range.start.line, 0)
        @Expect(edits[0].range.start.character, 13)
        @Expect(edits[0].range.end.line, 0)
        @Expect(edits[0].range.end.character, 16)
        @Expect(edits[0].newText, "+")
    }

    @TestCase
    func aDocumentWithSyntaxErrorsOrNotKnownIsNotFormatted() {
        // act, assert
        @Expect(formattingEdits(opened("func f( {\n"), URI).isNone())
        @Expect(formattingEdits(ServerState(), URI).isNone())
    }

    @TestCase
    func aRangeExpandsToItsStatementAndUsesTheAgreedColumns() {
        // The selected emoji occupies two UTF-16 columns; the following statement is untouched.
        let state = opened("func f() {\nlet s = \"😀\"  +  \"x\"\ny\n}\n")
        let range =
            LspRange(start: Position(line: 1, character: 9), end: Position(line: 1, character: 11))
        let edits = rangeFormattingEdits(state, URI, range).getOrThrow()
        @Expect(edits.size, 1)
        @Expect(edits[0].range.start.line, 1)
        @Expect(edits[0].range.start.character, 0)
        @Expect(edits[0].range.end.line, 1)
        @Expect(edits[0].range.end.character, 16)
        @Expect(edits[0].newText, "    let s = \"😀\" +")
    }

    @TestCase
    func aRangeOfADocumentWithSyntaxErrorsOrNotKnownIsNotFormatted() {
        // arrange
        let range =
            LspRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1))

        // act, assert
        @Expect(rangeFormattingEdits(opened("func f( {\n"), URI, range).isNone())
        @Expect(rangeFormattingEdits(ServerState(), URI, range).isNone())
    }
}
