package cjls.handlers

import stdxx.Nullable
import loupe.{definitionAt, NavigationTarget}
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * Where the name at the position is declared, each candidate of an ambiguity or an overload: as
 * `LocationLink`s to a client that takes them, `Location`s otherwise; `null` for a name nothing
 * resolves, or a document the server does not know.
 */
@LspHandler[readonly]
func handleDefinition(snap: ServerSnapshot, params: DefinitionParams): Nullable<DefinitionOrDefinitionLinks> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let targets = definitionAt(snap.analysis, file.fileId(snap.analysis), offsetOf(snap, file, params.position))
    if (targets.isEmpty()) {
        return Nullable.Null
    }
    let place = {
        target: NavigationTarget =>
        (snap.analysis.sourceFile(target.fileId).getOrThrow().text(snap.analysis), snap.path(target.fileId).toUri())
    }
    if (snap.locationLinks) {
        return Nullable.Value(DefinitionOrDefinitionLinks.AsDefinitionLinks(targets.map {
            target =>
            let (text, uri) = place(target)
            locationLink(text, uri, target, snap.encoding)
        }))
    }
    Nullable.Value(DefinitionOrDefinitionLinks.AsDefinition(Definition.AsLocations(targets.map {
        target =>
        let (text, uri) = place(target)
        location(text, uri, target, snap.encoding)
    })))
}
