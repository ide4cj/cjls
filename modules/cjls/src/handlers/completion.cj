package cjls.handlers

import std.collection.ArrayList
import stdxx.Nullable
import fjson.JsonValue
import loupe.{completionsAt, completionDetail, CompletionKind, HoverItem}
import loupe.CompletionItem as Candidate
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * The completions at the position (#203, D111): after a `.` the members of what is before it, at a
 * name what is in scope, each with a `sortText` from its relevance and a `textEdit` replacing the
 * name typed before the cursor; the list is complete, the client matches what was typed. The
 * detail and the documentation come with `completionItem/resolve`, through `data`. `null` for a
 * position nothing completes at, or a document the server does not know; nothing in an expanded
 * file, which is read only.
 */
@LspHandler[readonly]
func handleCompletion(snap: ServerSnapshot, params: CompletionParams): Nullable<CompletionItemsOrCompletionList> {
    if (isExpandedDocument(params.textDocument.uri)) {
        return Nullable.Null
    }
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let offset = offsetOf(snap, file, params.position)
    let found = completionsAt(snap.analysis, file.fileId(snap.analysis), offset) ?? return Nullable.Null
    let text = file.text(snap.analysis)
    let range = lspRange(text, found.range.start, found.range.end, snap.encoding)
    let items = Array(found.items.size) {
        i =>
        let item = found.items[i]
        CompletionItem(label: item.label, kind: kindOf(item.kind), sortText: sortTextOf(item.relevance),
            filterText: item.label, textEdit: TextEditOrInsertReplaceEdit.AsTextEdit(TextEdit(range: range, newText: item.label)),
            data: JsonValue.JsonObject([("uri", JsonValue.JsonString(params.textDocument.uri)),
                ("line", JsonValue.JsonInteger(Int64(params.position.line))),
                ("character", JsonValue.JsonInteger(Int64(params.position.character))),
                ("index", JsonValue.JsonInteger(i))]))
    }
    Nullable.Value(CompletionItemsOrCompletionList.AsCompletionList(CompletionList(isIncomplete: false, items: items)))
}

/**
 * The item with its detail, its declaration as hover shows it, and its documentation, its package
 * and its doc comment: the completions are listed again at the position `data` names, on the
 * snapshot of now, and the item found by its index, or by its label if the list moved. The item as
 * it came, if `data` is not the server's or the position completes nothing any more.
 */
@LspHandler[readonly]
func handleCompletionResolve(snap: ServerSnapshot, params: CompletionItem): CompletionItem {
    let data = params.data ?? return params
    let uri = match (data.get("uri")) {
        case Some(JsonString(one)) => one
        case _ => return params
    }
    let line = integerOf(data, "line") ?? return params
    let character = integerOf(data, "character") ?? return params
    let index = integerOf(data, "index") ?? return params
    let file = fileOf(snap, uri) ?? return params
    let fileId = file.fileId(snap.analysis)
    let offset = offsetOf(snap, file, Position(line: UInt32(line), character: UInt32(character)))
    let found = completionsAt(snap.analysis, fileId, offset) ?? return params
    let candidate = match (found.items.get(index)) {
        case Some(one) where one.label == params.label => one
        case _ => (found.items.iterator().filter {one: Candidate => one.label == params.label}.next()) ?? return params
    }
    let detail = completionDetail(snap.analysis, fileId, offset, candidate) ?? return params
    CompletionItem(label: params.label, labelDetails: params.labelDetails, kind: params.kind, tags: params.tags,
        detail: detail.code, documentation: documentationOf(detail, snap.completionMarkdown),
        deprecated: params.deprecated, preselect: params.preselect, sortText: params.sortText,
        filterText: params.filterText, insertText: params.insertText, insertTextFormat: params.insertTextFormat,
        insertTextMode: params.insertTextMode, textEdit: params.textEdit, textEditText: params.textEditText,
        additionalTextEdits: params.additionalTextEdits, commitCharacters: params.commitCharacters,
        command: params.command, data: params.data)
}

func integerOf(data: JsonValue, key: String): ?Int64 {
    match (data.get(key)) {
        case Some(JsonInteger(one)) => one
        case _ => None
    }
}

/**
 * Where the item is declared and its doc comment, as hover shows them: Markdown to a client that
 * takes it, plain text otherwise; `None` for an item of neither.
 */
func documentationOf(detail: HoverItem, markdown: Bool): ?StringOrMarkupContent {
    let parts = ArrayList<String>()
    if (let Some(path) <- detail.path) {
        parts.add(codeBlock(path, markdown))
    }
    if (let Some(doc) <- detail.doc) {
        parts.add(doc)
    }
    if (parts.isEmpty()) {
        return None
    }
    let value = String.join(parts.toArray(), delimiter: if (markdown) {
        "\n\n"
    } else {
        "\n"
    })
    StringOrMarkupContent.AsMarkupContent(MarkupContent(kind: if (markdown) {
        MarkupKind.Markdown
    } else {
        MarkupKind.PlainText
    }, value: value))
}

/**
 * Sorts as the relevance does, the most relevant first: a client sorts `sortText` as a string.
 */
func sortTextOf(relevance: Int64): String {
    "${999 - max(0, min(relevance, 999))}".padStart(3, padding: "0")
}

func kindOf(kind: CompletionKind): CompletionItemKind {
    match (kind) {
        case LocalItem | ParamItem | VarItem => CompletionItemKind.Variable
        case FuncItem => CompletionItemKind.Function
        case PropItem => CompletionItemKind.Property
        case CtorItem => CompletionItemKind.Constructor
        case ClassItem | TypeAliasItem => CompletionItemKind.Class
        case InterfaceItem => CompletionItemKind.Interface
        case StructItem => CompletionItemKind.Struct
        case EnumItem => CompletionItemKind.Enum
        case PkgItem => CompletionItemKind.Module
        case TypeParamItem => CompletionItemKind.TypeParameter
        case KeywordItem => CompletionItemKind.Keyword
    }
}
