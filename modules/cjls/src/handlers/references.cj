package cjls.handlers

import std.collection.{collectArray, filter, map}
import stdxx.Nullable
import loupe.{ExpandedPlace, findReferences, Reference}
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * Every name of the workspace meaning what the one at the position does, the declarations among them if the
 * client asks for them; `null` for a name nothing resolves, or a document the server does not know. In a document
 * showing a file's expansions (D103), of a name the file has, found in the files.
 */
@LspHandler[readonly]
func handleReferences(snap: ServerSnapshot, params: ReferenceParams): Nullable<Array<Location>> {
    let (fileId, offset) = if (isExpandedDocument(params.textDocument.uri)) {
        let view = expandedViewOf(snap, params.textDocument.uri) ?? return Nullable.Null
        match (view.expanded.placeOf(view.offsetOf(snap, params.position))) {
            case Some(InSource(offset)) => (view.source.fileId(snap.analysis), offset)
            case _ => return Nullable.Null
        }
    } else {
        let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
        (file.fileId(snap.analysis), offsetOf(snap, file, params.position))
    }
    let found = findReferences(snap.analysis, fileId, offset)
    if (found.isEmpty()) {
        return Nullable.Null
    }
    Nullable.Value(found |> filter {one: Reference => params.context.includeDeclaration || !one.isDeclaration} |> map {
        one: Reference => location(snap.analysis.sourceFile(one.fileId).getOrThrow().text(snap.analysis),
            snap.path(one.fileId).toUri(), one, snap.encoding)
    } |> collectArray)
}
