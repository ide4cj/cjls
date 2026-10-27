package cjls.handlers

import stdxx.Nullable
import loupe.{definitionAt, NavigationTarget}
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * Where the name at the position is declared, each candidate of an ambiguity or an overload: as
 * `LocationLink`s to a client that takes them, `Location`s otherwise; `null` for a name nothing
 * resolves, or a document the server does not know. In an expanded file, through its view
 * (`definitionPlacesInView`).
 */
@LspHandler[readonly]
func handleDefinition(
    snap: ServerSnapshot,
    params: DefinitionParams
): Nullable<DefinitionOrDefinitionLinks> {
    let places =
        if (isExpandedDocument(params.textDocument.uri)) {
            let view = expandedViewOf(snap, params.textDocument.uri) ?? return Nullable.Null
            definitionPlacesInView(snap, view, params.position)
        } else {
            let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
            definitionAt(
                snap.analysis,
                file.fileId(snap.analysis),
                offsetOf(snap, file, params.position)
            )
                .map {
                    target =>
                    Place(
                        snap.analysis.sourceFile(target.fileId).getOrThrow().text(snap.analysis),
                        snap.path(target.fileId).toUri(),
                        target
                    )
                }
        }
    if (places.isEmpty()) {
        return Nullable.Null
    }
    if (snap.locationLinks) {
        return Nullable
            .Value(
                DefinitionOrDefinitionLinks
                    .AsDefinitionLinks(
                        places
                            .map {
                                place =>
                                locationLink(place.text, place.uri, place.target, snap.encoding)
                            }
                    )
            )
    }
    Nullable
        .Value(
            DefinitionOrDefinitionLinks
                .AsDefinition(
                    Definition
                        .AsLocations(
                            places
                                .map {
                                    place =>
                                    location(place.text, place.uri, place.target, snap.encoding)
                                }
                        )
                )
        )
}
