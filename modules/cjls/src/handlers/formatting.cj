package cjls.handlers

import stdxx.Nullable
import loupe.{formatting, rangeFormatting, TextRange}
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * The edits that format a document; `null` for one with syntax errors or not known. The style is
 * the formatter's own, whatever indent the client's `options` ask for: a project formats alike in
 * every editor, and as `cjls fmt` does.
 */
@LspHandler[readonly]
func handleFormatting(snap: ServerSnapshot, params: DocumentFormattingParams): Nullable<Array<TextEdit>> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let text = file.text(snap.analysis)
    let edits = formatting(snap.analysis, file.fileId(snap.analysis)) ?? return Nullable.Null
    Nullable.Value(edits.map {edit => textEdit(text, edit, snap.encoding)})
}

/**
 * The edits that format the lines `params.range` covers, as `handleFormatting` would format them;
 * `null` likewise.
 */
@LspHandler[readonly]
func handleRangeFormatting(snap: ServerSnapshot, params: DocumentRangeFormattingParams): Nullable<Array<TextEdit>> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let text = file.text(snap.analysis)
    let range = TextRange(offsetOf(snap, file, params.range.start), offsetOf(snap, file, params.range.end))
    let edits = rangeFormatting(snap.analysis, file.fileId(snap.analysis), range) ?? return Nullable.Null
    Nullable.Value(edits.map {edit => textEdit(text, edit, snap.encoding)})
}
