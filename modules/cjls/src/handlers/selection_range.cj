package cjls.handlers

import stdxx.Nullable
import loupe.extendSelection
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * For each position asked, in their order, the ranges a selection there widens through, from the
 * tree alone; `null` for a document the server does not know. A position past the end of a line or
 * of the document stands for that end, as LSP has it.
 */
@LspHandler[readonly]
func handleSelectionRange(snap: ServerSnapshot, params: SelectionRangeParams): Nullable<Array<SelectionRange>> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let text = file.text(snap.analysis)
    let fileId = file.fileId(snap.analysis)
    Nullable.Value(params.positions.map {
        position => selectionRange(text, extendSelection(snap.analysis, fileId, offsetOf(snap, file, position)),
            snap.encoding)
    })
}
