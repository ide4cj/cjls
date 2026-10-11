package cjls.handlers

import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import stdxx.Nullable
import cjls.lsp_types.*
import cjls.server.*

func hoverOf(state: ServerState, path: Path, line: UInt32, character: UInt32): Nullable<Hover> {
    handleHover(state.snapshot(), HoverParams(textDocument: TextDocumentIdentifier(uri: uriOf(path)),
        position: Position(line: line, character: character)))
}

/**
 * The content of a hover, and its range as `line:character-line:character`.
 */
func markupOf(answer: Nullable<Hover>): (MarkupContent, String) {
    match (answer) {
        case Nullable.Value(hover) => match (hover.contents) {
            case MarkupContentOrMarkedStringOrMarkedStrings.AsMarkupContent(content) =>
                (content, hover.range.map {it => "${at(it.start)}-${at(it.end)}"} ?? "")
            case _ => throw AssertException("not markup")
        }
        case _ => throw AssertException("no hover")
    }
}

@Test
class HoverHandlerTest {
    let file = "/** Twice `n`. */\nfunc twice(n: Int64): Int64 { n * 2 }\nfunc f() {\n    twice(1)\n}\n"

    @TestCase
    func aCallShowsWhereItsFunctionIsItsDeclarationAndItsDocInMarkdown() {
        // arrange
        let (state, dir) = loaded([("a.cj", file)])
        state.hoverMarkdown = true

        // act
        let (content, range) = markupOf(hoverOf(state, dir.join("a.cj"), 3, 6))

        // assert
        @Expect(content.kind, MarkupKind.Markdown)
        @Expect(content.value, "```cangjie\ndefault\n```\n\n```cangjie\nfunc twice(n: Int64): Int64\n```\n\n---\n\nTwice `n`.")
        @Expect(range, "3:4-3:9")
    }

    @TestCase
    func aClientOfPlainTextGetsTheSameLines() {
        // arrange
        let (state, dir) = loaded([("a.cj", file)])

        // act
        let (content, _) = markupOf(hoverOf(state, dir.join("a.cj"), 3, 6))

        // assert
        @Expect(content.kind, MarkupKind.PlainText)
        @Expect(content.value, "default\nfunc twice(n: Int64): Int64\n\nTwice `n`.")
    }

    @TestCase
    func nothingThereIsNull() {
        // arrange
        let (state, dir) = loaded([("a.cj", file)])

        // act
        let answer = hoverOf(state, dir.join("a.cj"), 2, 9)

        // assert
        @Expect(answer.isNull())
    }

    @TestCase[row in [
        (ClientCapabilities(textDocument: TextDocumentClientCapabilities(
            hover: HoverClientCapabilities(contentFormat: [MarkupKind.PlainText, MarkupKind.Markdown]))), true),
        (ClientCapabilities(textDocument: TextDocumentClientCapabilities(
            hover: HoverClientCapabilities(contentFormat: [MarkupKind.PlainText]))), false),
        (ClientCapabilities(), false)
    ]]
    func markdownGoesOnlyToAClientThatSaysItTakesIt(row: (ClientCapabilities, Bool)) {
        // arrange
        let (capabilities, markdown) = row
        let state = ServerState()

        // act
        handleInitialize(state, Client(), NoopLogger(),
            InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null,
                capabilities: capabilities))

        // assert
        @Expect(state.hoverMarkdown, markdown)
    }
}
