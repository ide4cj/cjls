package cjls.handlers

import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*
import stdxx.Nullable
import cjls.lsp_types.*
import cjls.server.*

func completionsOf(state: ServerState, path: Path, line: UInt32, character: UInt32): Array<CompletionItem> {
    let answer = handleCompletion(state.snapshot(), CompletionParams(
        textDocument: TextDocumentIdentifier(uri: uriOf(path)), position: Position(line: line, character: character)))
    match (answer) {
        case Nullable.Value(CompletionItemsOrCompletionList.AsCompletionList(list)) => list.items
        case Nullable.Value(CompletionItemsOrCompletionList.AsCompletionItems(items)) => items
        case Nullable.Null => []
    }
}

func editOf(item: CompletionItem): String {
    match (item.textEdit) {
        case Some(TextEditOrInsertReplaceEdit.AsTextEdit(edit)) =>
            "${at(edit.range.start)}-${at(edit.range.end)} ${edit.newText}"
        case _ => "no edit"
    }
}

@Test
class CompletionHandlerTest {
    let file = "/** A point. */\nclass Point {\n    let x = 1\n    /** Its norm. */\n    func norm(): Int64 { x }\n}\n" +
        "func f() {\n    let p = Point()\n    p.\n}\nfunc g() {\n    let p = Point()\n    p.no\n}\n"

    @TestCase
    func aDotListsTheMembersSortedByRelevanceWithAnEmptyEditAtTheCursor() {
        // arrange
        let (state, dir) = loaded([("a.cj", file)])

        // act
        let items = completionsOf(state, dir.join("a.cj"), 8, 6)

        // assert
        @Expect(items.map {item => item.label}, ["norm", "x"])
        @Expect(items.map {item => item.kind ?? CompletionItemKind.Text}, [CompletionItemKind.Function, CompletionItemKind.Variable])
        @Expect(items.map {item => item.sortText ?? ""}, ["919", "919"])
        @Expect(items.map {item => editOf(item)}, ["8:6-8:6 norm", "8:6-8:6 x"])
        @Expect(items.map {item => item.detail.isNone()}, [true, true])
    }

    @TestCase
    func aPrefixTypedIsReplacedByTheEdit() {
        // arrange
        let (state, dir) = loaded([("a.cj", file)])

        // act
        let items = completionsOf(state, dir.join("a.cj"), 12, 8)

        // assert
        @Expect(items.map {item => editOf(item)}, ["12:6-12:8 norm", "12:6-12:8 x"])
    }

    @TestCase
    func resolveAddsTheDetailAndTheDocumentation() {
        // arrange
        let (state, dir) = loaded([("a.cj", file)])
        state.completionMarkdown = true
        let items = completionsOf(state, dir.join("a.cj"), 8, 6)

        // act
        let resolved = handleCompletionResolve(state.snapshot(), items[0])

        // assert
        @Expect(resolved.label, "norm")
        @Expect(resolved.detail ?? "", "func norm(): Int64")
        match (resolved.documentation) {
            case Some(StringOrMarkupContent.AsMarkupContent(content)) =>
                @Expect(content.kind, MarkupKind.Markdown)
                @Expect(content.value, "```cangjie\ndefault.Point\n```\n\nIts norm.")
            case _ => @Fail("no documentation")
        }
        @Expect(resolved.textEdit.isSome())
    }

    @TestCase
    func resolveOfAnItemWithoutTheServersDataReturnsItAsItCame() {
        // arrange
        let (state, _) = loaded([("a.cj", file)])
        let item = CompletionItem(label: "norm")

        // act
        let resolved = handleCompletionResolve(state.snapshot(), item)

        // assert
        @Expect(resolved.detail.isNone())
    }

    @TestCase
    func nothingToCompleteIsNull() {
        // arrange
        let (state, dir) = loaded([("a.cj", file)])

        // act
        let answer = handleCompletion(state.snapshot(), CompletionParams(
            textDocument: TextDocumentIdentifier(uri: uriOf(dir.join("a.cj"))), position: Position(line: 0, character: 4)))

        // assert
        @Expect(answer.isNull())
    }
}
