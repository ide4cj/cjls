package cjls.handlers

import loupe.fileStructure
import stdxx.Nullable
import cjls.lsp_types.*
import cjls.macros.LspHandler
import cjls.server.*

/**
 * The outline of a document, nested; `null` for a document the server does not know.
 */
@LspHandler[readonly]
func handleDocumentSymbol(
    snap: ServerSnapshot,
    params: DocumentSymbolParams
): Nullable<SymbolInformationsOrDocumentSymbols> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let text = file.text(snap.analysis)
    let structure = fileStructure(snap.analysis, file.fileId(snap.analysis))
    Nullable.Value(
        SymbolInformationsOrDocumentSymbols.AsDocumentSymbols(
            structure.map { node => documentSymbol(text, node, snap.encoding) }
        )
    )
}
