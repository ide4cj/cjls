package cjls.handlers

import cjformat.FormatOptions
import cjformat.config.{FormatConfigException, optionsFor}
import cjls.lsp_types.*
import cjls.macros.LspHandler
import cjls.server.{ReadOnlyContext, ServerSnapshot}
import jsonrpc.{ErrorCode, RpcException}
import loupe.{TextRange, formatting, rangeFormatting}
import loupe.vfs.VfsPath
import stdxx.Nullable

/**
 * The edits that format a document; `null` for one with syntax errors or not known. The style is
 * the project's `cjformat.toml`, whatever indent the client's `options` ask for: a project formats alike in
 * every editor, and as `cjls fmt` does.
 */
@LspHandler[readonly]
func handleFormatting(
    snap: ServerSnapshot,
    params: DocumentFormattingParams
): Nullable<Array<TextEdit>> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let text = file.text(snap.analysis)
    let edits =
        formatting(
            snap.analysis,
            file.fileId(snap.analysis),
            options: formattingOptions(params.textDocument.uri)
        ) ??
            return Nullable.Null
    Nullable.Value(edits.map { edit => textEdit(text, edit, snap.encoding) })
}

/**
 * The edits that format the complete syntax node enclosing `params.range`;
 * `null` likewise.
 */
@LspHandler[readonly]
func handleRangeFormatting(
    snap: ServerSnapshot,
    params: DocumentRangeFormattingParams
): Nullable<Array<TextEdit>> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let text = file.text(snap.analysis)
    let range =
        TextRange(offsetOf(snap, file, params.range.start), offsetOf(snap, file, params.range.end))
    let edits =
        rangeFormatting(
            snap.analysis,
            file.fileId(snap.analysis),
            range,
            options: formattingOptions(params.textDocument.uri)
        ) ??
            return Nullable.Null
    Nullable.Value(edits.map { edit => textEdit(text, edit, snap.encoding) })
}

/**
 * Reads project policy for disk documents; virtual documents use the library defaults.
 *
 * @throws RpcException - if a project config cannot be read or validated
 */
private func formattingOptions(uri: String): FormatOptions {
    let path = VfsPath.fromUri(uri).filePath ?? return FormatOptions()
    try {
        optionsFor(path)
    } catch (e: FormatConfigException) {
        throw RpcException(ErrorCode.REQUEST_FAILED, e.message)
    }
}
