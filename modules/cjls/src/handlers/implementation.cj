package cjls.handlers

import stdxx.Nullable
import loupe.{ExpandedPlace, implementationsAt}
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * What implements the name at the position: the members overriding or implementing a member, the types below a
 * class or an interface and the `extend`s declaring it, as `Location`s, which every client takes; `null` for none,
 * or a document the server does not know. In a document showing a file's expansions (D103), of a name the file has.
 */
@LspHandler[readonly]
func handleImplementation(
    snap: ServerSnapshot,
    params: ImplementationParams
): Nullable<DefinitionOrDefinitionLinks> {
    let (fileId, offset) =
        if (isExpandedDocument(params.textDocument.uri)) {
            let view = expandedViewOf(snap, params.textDocument.uri) ?? return Nullable.Null
            match (view.expanded.placeOf(view.offsetOf(snap, params.position))) {
                case Some(InSource(offset)) => (view.source.fileId(snap.analysis), offset)
                case _ => return Nullable.Null
            }
        } else {
            let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
            (file.fileId(snap.analysis), offsetOf(snap, file, params.position))
        }
    let found = implementationsAt(snap.analysis, fileId, offset)
    if (found.isEmpty()) {
        return Nullable.Null
    }
    Nullable
        .Value(
            DefinitionOrDefinitionLinks
                .AsDefinition(
                    Definition
                        .AsLocations(
                            found
                                .map {
                                    target =>
                                    location(
                                        snap
                                            .analysis
                                            .sourceFile(target.fileId)
                                            .getOrThrow()
                                            .text(snap.analysis),
                                        snap.path(target.fileId).toUri(),
                                        target,
                                        snap.encoding
                                    )
                                }
                        )
                )
        )
}
