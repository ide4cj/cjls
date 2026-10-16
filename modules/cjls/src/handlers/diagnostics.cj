package cjls.handlers

import fjson.toJsonBytes
import loupe.diagnostics
import loupe.vfs.VfsPath
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * What is wrong in a document, or `unchanged` when the client's `previousResultId` is the report's
 * still (#51). A document the server does not know has nothing wrong. The files changing under it is
 * the server's to answer (S5): the handler runs again on the files as they are then (D122).
 */
@LspHandler[readonly]
func handleDocumentDiagnostic(snap: ServerSnapshot, params: DocumentDiagnosticParams): DocumentDiagnosticReport {
    let items = documentDiagnostics(snap, VfsPath.fromUri(params.textDocument.uri))
    let resultId = resultIdOf(snap, items)
    if (params.previousResultId == Some(resultId)) {
        return DocumentDiagnosticReport.AsRelatedUnchangedDocumentDiagnosticReport(
            RelatedUnchangedDocumentDiagnosticReport(resultId: resultId))
    }
    DocumentDiagnosticReport.AsRelatedFullDocumentDiagnosticReport(
        RelatedFullDocumentDiagnosticReport(resultId: resultId, items: items))
}

/**
 * The `resultId` of a report of `items`: a hash of them as the client gets them, positions in its
 * columns included, so nothing is kept between requests (as ty does). A client that dropped a
 * document's diagnostics may still send its id (Neovim reopening a buffer), so the openings so far
 * are part of it: an id from before a `didOpen` never matches after it.
 */
func resultIdOf(snap: ServerSnapshot, items: Array<Diagnostic>): String {
    "${snap.openings}:${String.fromUtf8(toJsonBytes(items)).hashCode()}"
}

/**
 * The diagnostics of the document at `path`, as the snapshot has it: what a pull answers, and what
 * the server pushes to a client that cannot pull; none for an expanded file (`sourceOfExpanded`).
 */
func documentDiagnostics(snap: ServerSnapshot, path: VfsPath): Array<Diagnostic> {
    // an expanded file is no file of the workspace: what its names would mean there is no error of the user's
    if (isExpandedFile(path)) {
        return []
    }
    let file = snap.sourceFile(path) ?? return []
    let text = file.text(snap.analysis)
    diagnostics(snap.analysis, file.fileId(snap.analysis)).map {it => diagnostic(text, it, snap.encoding)}
}
