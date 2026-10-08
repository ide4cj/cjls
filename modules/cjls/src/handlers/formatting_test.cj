package cjls.handlers

import std.unittest.*
import std.unittest.testmacro.*
import stdxx.Nullable
import cjls.lsp_types.*
import cjls.server.*

func formattingEdits(state: ServerState, uri: String): ?Array<TextEdit> {
    let params = DocumentFormattingParams(textDocument: TextDocumentIdentifier(uri: uri),
        options: FormattingOptions(tabSize: 2, insertSpaces: true))
    match (handleFormatting(state.snapshot(), params)) {
        case Nullable.Value(edits) => edits
        case Nullable.Null => None
    }
}

@Test
class FormattingTest {
    @TestCase
    func theEditsAreInTheColumnsAgreedOnAndIgnoreTheClientsIndent() {
        // arrange - the emoji is two UTF-16 units and four bytes
        let state = opened("func f() { /* 😀 */\nx\n}\n")

        // act
        let edits = formattingEdits(state, URI).getOrThrow()

        // assert
        @Expect(edits.size, 1)
        @Expect(edits[0].range.start.line, 0)
        @Expect(edits[0].range.start.character, 19)
        @Expect(edits[0].range.end.line, 1)
        @Expect(edits[0].range.end.character, 0)
        @Expect(edits[0].newText, "\n    ")
    }

    @TestCase
    func aDocumentWithSyntaxErrorsOrNotKnownIsNotFormatted() {
        // act, assert
        @Expect(formattingEdits(opened("func f( {\n"), URI).isNone())
        @Expect(formattingEdits(ServerState(), URI).isNone())
    }
}
