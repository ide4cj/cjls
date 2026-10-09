package cjls.handlers

import stdxx.Nullable
import loupe.hoverAt
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * What the name at the position stands for: its declaration, or its type, and its doc comment, as
 * Markdown to a client that takes it, plain text otherwise; over the name's range. `null` for no
 * name, one nothing resolves, or a document the server does not know.
 */
@LspHandler[readonly]
func handleHover(snap: ServerSnapshot, params: HoverParams): Nullable<Hover> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let hover = hoverAt(snap.analysis, file.fileId(snap.analysis), offsetOf(snap, file, params.position)) ??
        return Nullable.Null
    let text = file.text(snap.analysis)
    Nullable.Value(Hover(contents: MarkupContentOrMarkedStringOrMarkedStrings.AsMarkupContent(
        hoverContent(hover, snap.hoverMarkdown)),
        range: lspRange(text, hover.range.start, hover.range.end, snap.encoding)))
}
