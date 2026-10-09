package cjls.handlers

import stdxx.Nullable
import loupe.highlightRelated
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * Every name of the document meaning what the one at the position does, each a read, a write or
 * neither; `null` for a name nothing resolves, or a document the server does not know.
 */
@LspHandler[readonly]
func handleDocumentHighlight(snap: ServerSnapshot, params: DocumentHighlightParams): Nullable<Array<DocumentHighlight>> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let found = highlightRelated(snap.analysis, file.fileId(snap.analysis), offsetOf(snap, file, params.position))
    if (found.isEmpty()) {
        return Nullable.Null
    }
    let text = file.text(snap.analysis)
    Nullable.Value(found.map {highlight => documentHighlight(text, highlight, snap.encoding)})
}
