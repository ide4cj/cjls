package cjls.handlers

import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import stdxx.Nullable
import cjls.lsp_types.*
import cjls.server.*

func completionOf(
    state: ServerState,
    path: Path,
    line: UInt32,
    character: UInt32
): Array<CompletionItem> {
    let answer =
        handleCompletion(
            state.snapshot(),
            CompletionParams(
                textDocument: TextDocumentIdentifier(uri: uriOf(path)),
                position: Position(line: line, character: character)
            )
        )
    match (answer) {
        case Nullable.Value(CompletionItemsOrCompletionList.AsCompletionList(list)) =>
            @Assert(!list.isIncomplete)
            list.items
        case Nullable.Value(_) => throw AssertException("not a list")
        case Nullable.Null => []
    }
}

/**
 * An item as `label kind sortText range`.
 */
func summaryOf(item: CompletionItem): String {
    let range =
        match (item.textEdit) {
            case Some(TextEditOrInsertReplaceEdit.AsTextEdit(edit)) =>
                "${at(edit.range.start)}-${at(edit.range.end)}"
            case _ => "no edit"
        }
    let kind =
        match (item.kind) {
            case Some(CompletionItemKind.Function) => "function"
            case Some(CompletionItemKind.Variable) => "variable"
            case _ => "other"
        }
    "${item.label} ${kind} ${item.sortText ?? "-"} ${range}"
}

func itemNamed(items: Array<CompletionItem>, label: String): CompletionItem {
    for (item in items where item.label == label) {
        return item
    }
    throw AssertException("no item ${label}")
}

@Test
class CompletionHandlerTest {
    let file =
        "struct Point {\n    /** How far right. */\n    public let x: Int64 = 1\n    public func norm(): Int64 { x }\n}\nfunc f() {\n    let p = Point()\n    p.n\n}\n"

    @TestCase
    func aDotListsTheMembersReplacingTheNameTypedInTheirOrder() {
        // arrange
        let (state, dir) = loaded([("a.cj", file)])

        // act
        let items = completionOf(state, dir.join("a.cj"), 7, 7)

        // assert
        @Expect(items.map(summaryOf), ["norm function 0 7:6-7:7", "x variable 1 7:6-7:7"])
    }

    @TestCase
    func resolveAddsTheDeclarationAndTheDocInMarkdown() {
        // arrange
        let (state, dir) = loaded([("a.cj", file)])
        state.completionMarkdown = true
        let item = itemNamed(completionOf(state, dir.join("a.cj"), 7, 7), "x")

        // act
        let resolved = handleCompletionResolve(state.snapshot(), item)

        // assert
        @Expect(resolved.detail, Some("public let x: Int64"))
        match (resolved.documentation) {
            case Some(StringOrMarkupContent.AsMarkupContent(content)) =>
                @Expect(content.kind, MarkupKind.Markdown)
                @Expect(content.value, "How far right.")
            case _ => @Fail("no documentation")
        }
        @Expect(summaryOf(resolved), summaryOf(item))
    }

    @TestCase
    func anItemTheListNoLongerHasStaysAsItWas() {
        // arrange
        let (state, dir) = loaded([("a.cj", file)])
        let item = itemNamed(completionOf(state, dir.join("a.cj"), 7, 7), "x")
        let stale = CompletionItem(label: "y", data: item.data)

        // act
        let resolved = handleCompletionResolve(state.snapshot(), stale)

        // assert
        @Expect(resolved.detail.isNone())
        @Expect(resolved.label, "y")
    }

    @TestCase
    func nothingToCompleteIsNull() {
        // arrange
        let (state, dir) = loaded([("a.cj", file)])

        // act
        let items = completionOf(state, dir.join("a.cj"), 0, 3)

        // assert
        @Expect(items.size, 0)
    }

    @TestCase[row in [
        (ClientCapabilities(textDocument: TextDocumentClientCapabilities(
            completion: CompletionClientCapabilities(completionItem: ClientCompletionItemOptions(
                documentationFormat: [MarkupKind.Markdown, MarkupKind.PlainText])))), true),
        (ClientCapabilities(textDocument: TextDocumentClientCapabilities(
            completion: CompletionClientCapabilities(completionItem: ClientCompletionItemOptions(
                documentationFormat: [MarkupKind.PlainText])))), false),
        (ClientCapabilities(), false)
    ]]
    func markdownGoesOnlyToAClientThatSaysItTakesIt(row: (ClientCapabilities, Bool)) {
        // arrange
        let (capabilities, markdown) = row
        let state = ServerState()

        // act
        handleInitialize(
            state,
            Client(),
            NoopLogger(),
            InitializeParams(
                processId: Nullable.Null,
                rootUri: Nullable.Null,
                capabilities: capabilities
            )
        )

        // assert
        @Expect(state.completionMarkdown, markdown)
    }
}
