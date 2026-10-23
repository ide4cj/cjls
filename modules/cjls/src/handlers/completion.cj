package cjls.handlers

import fjson.JsonValue
import stdxx.Nullable
import loupe.{CompletionKind, completionDetail, completionsAt}
import loupe.CompletionItem as AnalysisCompletion
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * The completions at the position (`loupe.completionsAt`), the most relevant first: each replaces
 * the name typed before the cursor, its order in `sortText`, and what `completionItem/resolve`
 * needs to find it again in `data`. Never incomplete: the items do not depend on what was typed,
 * which the client matches them against. `null` where there is nothing to complete, in a document
 * the server does not know, or in an expanded file, which is read-only.
 */
@LspHandler[readonly]
func handleCompletion(
    snap: ServerSnapshot,
    params: CompletionParams
): Nullable<CompletionItemsOrCompletionList> {
    let uri = params.textDocument.uri
    if (isExpandedDocument(uri)) {
        return Nullable.Null
    }
    let file = fileOf(snap, uri) ?? return Nullable.Null
    let result =
        completionsAt(
            snap.analysis,
            file.fileId(snap.analysis),
            offsetOf(snap, file, params.position)
        ) ??
            return Nullable.Null
    let range =
        lspRange(file.text(snap.analysis), result.range.start, result.range.end, snap.encoding)
    let width = "${result.items.size}".size
    let items =
        Array<CompletionItem>(result.items.size) {
            index =>
            let item = result.items[index]
            CompletionItem(
                label: item.label,
                kind: completionItemKind(item.kind),
                sortText: "${index}".padStart(width, padding: "0"),
                textEdit: TextEditOrInsertReplaceEdit
                    .AsTextEdit(TextEdit(range: range, newText: item.label)),
                data: completionData(uri, params.position, index)
            )
        }
    Nullable
        .Value(
            CompletionItemsOrCompletionList
                .AsCompletionList(CompletionList(isIncomplete: false, items: items))
        )
}

/**
 * The item with its detail, its declaration as one line, and its doc comment, as Markdown to a
 * client that takes it, plain text otherwise (`loupe.completionDetail`). The item is found again by
 * the completions at the position its `data` names, by its index and its label: the item as it was
 * when the list or the file it came from is gone.
 */
@LspHandler[readonly]
func handleCompletionResolve(snap: ServerSnapshot, item: CompletionItem): CompletionItem {
    let (uri, position, index) = completionDataOf(item.data) ?? return item
    let file = fileOf(snap, uri) ?? return item
    let fileId = file.fileId(snap.analysis)
    let offset = offsetOf(snap, file, position)
    let result = completionsAt(snap.analysis, fileId, offset) ?? return item
    if (index < 0 || index >= result.items.size || result.items[index].label != item.label) {
        return item
    }
    let detail = completionDetail(snap.analysis, fileId, offset, result.items[index]) ?? return item
    let documentation =
        detail
            .doc
            .map {
                doc =>
                StringOrMarkupContent
                    .AsMarkupContent(
                        MarkupContent(
                            kind: if (snap.completionMarkdown) {
                                MarkupKind.Markdown
                            } else {
                                MarkupKind.PlainText
                            },
                            value: doc
                        )
                    )
            }
    CompletionItem(
        label: item.label,
        labelDetails: item.labelDetails,
        kind: item.kind,
        tags: item.tags,
        detail: detail.code,
        documentation: documentation,
        deprecated: item.deprecated,
        preselect: item.preselect,
        sortText: item.sortText,
        filterText: item.filterText,
        insertText: item.insertText,
        insertTextFormat: item.insertTextFormat,
        insertTextMode: item.insertTextMode,
        textEdit: item.textEdit,
        textEditText: item.textEditText,
        additionalTextEdits: item.additionalTextEdits,
        commitCharacters: item.commitCharacters,
        command: item.command,
        data: item.data
    )
}

/**
 * What a client shows a completion as; a type alias as a struct, as R1 does.
 */
func completionItemKind(kind: CompletionKind): CompletionItemKind {
    match (kind) {
        case CompletionKind.LocalItem | CompletionKind.ParamItem | CompletionKind.VarItem =>
            CompletionItemKind.Variable
        case CompletionKind.FuncItem => CompletionItemKind.Function
        case CompletionKind.PropItem => CompletionItemKind.Property
        case CompletionKind.CtorItem => CompletionItemKind.Constructor
        case CompletionKind.ClassItem => CompletionItemKind.Class
        case CompletionKind.InterfaceItem => CompletionItemKind.Interface
        case CompletionKind.StructItem | CompletionKind.TypeAliasItem => CompletionItemKind.Struct
        case CompletionKind.EnumItem => CompletionItemKind.Enum
        case CompletionKind.PkgItem => CompletionItemKind.Module
        case CompletionKind.TypeParamItem => CompletionItemKind.TypeParameter
        case CompletionKind.KeywordItem => CompletionItemKind.Keyword
    }
}

/**
 * Where a completion item came from, for `completionItem/resolve`, whose request carries the item alone.
 */
func completionData(uri: DocumentUri, position: Position, index: Int64): LSPAny {
    JsonValue
        .JsonObject(
            [
                ("uri", JsonValue.JsonString(uri)),
                ("line", JsonValue.JsonInteger(Int64(position.line))),
                ("character", JsonValue.JsonInteger(Int64(position.character))),
                ("index", JsonValue.JsonInteger(index))
            ]
        )
}

func completionDataOf(data: ?LSPAny): ?(DocumentUri, Position, Int64) {
    let fields = data ?? return None
    let (uri, line, character, index) =
        match (
            (fields.get("uri"), fields.get("line"), fields.get("character"), fields.get("index"))
        ) {
            case (
                    Some(JsonValue.JsonString(uri)),
                    Some(JsonValue.JsonInteger(line)),
                    Some(JsonValue.JsonInteger(character)),
                    Some(JsonValue.JsonInteger(index))
                ) => (uri, line, character, index)
            case _ => return None
        }
    if (line < 0 || character < 0 || line > Int64(UInt32.Max) || character > Int64(UInt32.Max)) {
        return None
    }
    (uri, Position(line: UInt32(line), character: UInt32(character)), index)
}
