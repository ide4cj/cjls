package cjls.handlers

import cjls.lsp_types.*
import cjls.macros.LspHandler
import cjls.server.*
import loupe.foldingRanges as loupeFoldingRanges
import stdxx.Nullable

/**
 * What of a document folds, by its tree; `null` for a document the server does not know.
 */
@LspHandler[readonly]
func handleFoldingRange(
    snap: ServerSnapshot,
    params: FoldingRangeParams
): Nullable<Array<FoldingRange>> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let text = file.text(snap.analysis)
    Nullable.Value(
        foldingRanges(
            text,
            loupeFoldingRanges(snap.analysis, file.fileId(snap.analysis)),
            snap.encoding,
            snap.lineFoldingOnly,
            snap.foldingRangeLimit
        )
    )
}
