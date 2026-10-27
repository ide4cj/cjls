package cjls.handlers

import std.env.getTempDirectory
import std.fs.{Directory, File}
import std.unittest.*
import std.unittest.testmacro.*
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange
import cjls.server.ServerState
import jsonrpc.RpcException
import loupe.vfs.VfsPath
import stdxx.Nullable

/**
 * The handler edits for the open document, or no answer when formatting is refused.
 */
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

/**
 * The handler edits for a complete node enclosing the requested range.
 */
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
    func diskPolicyAppliesToWholeFilesAndRangesAndReloadsOnTheNextRequest(): Unit {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let uri = VfsPath.file(dir.join("a.cj")).toUri()
        let config = dir.join("cjformat.toml")
        let state = opened("func f() {\nx\n}\n", uri: uri)
        File.writeTo(config, "indent_width = 2\n".toArray())
        let range =
            LspRange(start: Position(line: 1, character: 0), end: Position(line: 1, character: 1))

        // act
        let whole = formattingEdits(state, uri).getOrThrow()
        let selected = rangeFormattingEdits(state, uri, range).getOrThrow()
        File.writeTo(config, "indent_width = 6\n".toArray())
        let reloaded = formattingEdits(state, uri).getOrThrow()
        File.writeTo(config, "indent_width = 'bad'\n".toArray())

        // assert
        @Expect(whole[0].newText, "  ")
        @Expect(selected[0].newText, "  ")
        @Expect(reloaded[0].newText, "      ")
        @AssertThrows[RpcException](formattingEdits(state, uri))
    }

    @TestCase
    func theEditsAreInTheColumnsAgreedOnAndIgnoreTheClientsIndent(): Unit {
        // arrange - the emoji is two UTF-16 units and four bytes
        let state = opened("let s = \"😀\"  +  \"x\"\n")

        // act
        let edits =
            formattingEdits(state, URI) ?? throw IllegalStateException("valid input must format")

        // assert
        @Expect(edits.size, 1)
        @Expect(edits[0].range.start.line, 0)
        @Expect(edits[0].range.start.character, 13)
        @Expect(edits[0].range.end.line, 0)
        @Expect(edits[0].range.end.character, 16)
        @Expect(edits[0].newText, "+")
    }

    @TestCase
    func aDocumentWithSyntaxErrorsOrNotKnownIsNotFormatted(): Unit {
        // arrange
        let invalid = opened("func f( {\n")
        let unknown = ServerState()

        // act
        let invalidEdits = formattingEdits(invalid, URI)
        let unknownEdits = formattingEdits(unknown, URI)

        // assert
        @Expect(invalidEdits.isNone())
        @Expect(unknownEdits.isNone())
    }

    @TestCase
    func aRangeExpandsToItsStatementAndUsesTheAgreedColumns(): Unit {
        // arrange - the selected emoji occupies two UTF-16 columns; the following statement is untouched.
        let state = opened("func f() {\nlet s = \"😀\"  +  \"x\"\ny\n}\n")
        let range =
            LspRange(start: Position(line: 1, character: 9), end: Position(line: 1, character: 11))

        // act
        let edits =
            rangeFormattingEdits(state, URI, range) ??
                throw IllegalStateException("valid range must format")

        // assert
        @Expect(edits.size, 1)
        @Expect(edits[0].range.start.line, 1)
        @Expect(edits[0].range.start.character, 0)
        @Expect(edits[0].range.end.line, 1)
        @Expect(edits[0].range.end.character, 16)
        @Expect(edits[0].newText, "    let s = \"😀\" +")
    }

    @TestCase
    func aRangeOfADocumentWithSyntaxErrorsOrNotKnownIsNotFormatted(): Unit {
        // arrange
        let range =
            LspRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1))

        let invalid = opened("func f( {\n")
        let unknown = ServerState()

        // act
        let invalidEdits = rangeFormattingEdits(invalid, URI, range)
        let unknownEdits = rangeFormattingEdits(unknown, URI, range)

        // assert
        @Expect(invalidEdits.isNone())
        @Expect(unknownEdits.isNone())
    }
}
