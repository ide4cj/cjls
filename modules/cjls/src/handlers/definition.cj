package cjls.handlers

import cjls.lsp_types.*
import cjls.macros.LspHandler
import cjls.server.*
import loupe.definitionAt
import rope.Encoding
import stdxx.Nullable

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
    navigationResult(places, snap.encoding, links: snap.locationLinks)
}

/**
 * Navigation results in the encoding and result shape negotiated for the requested method.
 */
func navigationResult(
    places: Array<Place>,
    encoding: Encoding,
    links!: Bool
): Nullable<DefinitionOrDefinitionLinks> {
    if (places.isEmpty()) {
        return Nullable.Null
    }
    if (links) {
        return Nullable
            .Value(
                DefinitionOrDefinitionLinks
                    .AsDefinitionLinks(
                        places
                            .map {
                                place =>
                                locationLink(place.text, place.uri, place.target, encoding)
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
                                    location(place.text, place.uri, place.target, encoding)
                                }
                        )
                )
        )
}
