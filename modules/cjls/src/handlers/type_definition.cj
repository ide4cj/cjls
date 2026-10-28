package cjls.handlers

import std.collection.{collectArray, filterMap}
import cjls.lsp_types.*
import cjls.macros.LspHandler
import cjls.server.{ReadOnlyContext, ServerSnapshot}
import loupe.{ExpandedPlace, NavigationTarget, typeDefinitionAt, typeDefinitionInExpansion}
import stdxx.Nullable

/**
 * The declaration of a symbol's type, using this snapshot's text and method-specific link support.
 */
@LspHandler[readonly]
func handleTypeDefinition(
    snap: ServerSnapshot,
    params: TypeDefinitionParams
): Nullable<DefinitionOrDefinitionLinks> {
    let db = snap.analysis
    let places =
        if (isExpandedDocument(params.textDocument.uri)) {
            let view = expandedViewOf(snap, params.textDocument.uri) ?? return Nullable.Null
            let targets =
                match (view.expanded.placeOf(view.offsetOf(snap, params.position))) {
                    case Some(InSource(offset)) =>
                        typeDefinitionAt(db, view.source.fileId(db), offset)
                    case Some(InExpansion(call, offset)) =>
                        typeDefinitionInExpansion(db, call, offset)
                    case None => return Nullable.Null
                }
            targets |> filterMap { target: NavigationTarget => placeInView(snap, view, target) } |>
                collectArray
        } else {
            let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
            typeDefinitionAt(db, file.fileId(db), offsetOf(snap, file, params.position))
                .map {
                    target =>
                    Place(
                        db.sourceFile(target.fileId).getOrThrow().text(db),
                        snap.path(target.fileId).toUri(),
                        target
                    )
                }
        }
    navigationResult(places, snap.encoding, links: snap.typeDefinitionLinks)
}
