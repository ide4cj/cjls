package cjls.handlers

import std.collection.{filter, first}
import fjson.JsonValue
import stdxx.Nullable
import loupe.{CallHierarchyEntry, incomingCalls, outgoingCalls, prepareCallHierarchy}
import loupe.hir.ItemFile
import cjls.lsp_types.*
import cjls.macros.LspHandler
import cjls.server.*

/**
 * Resolves the callable named at the client's position.
 */
@LspHandler[readonly]
func handlePrepareCallHierarchy(
    snap: ServerSnapshot,
    params: CallHierarchyPrepareParams
): Nullable<Array<CallHierarchyItem>> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let entries = prepareCallHierarchy(
        snap.analysis,
        file.fileId(snap.analysis),
        offsetOf(snap, file, params.position)
    )
    if (entries.isEmpty()) {
        return Nullable.Null
    }
    Nullable.Value(entries.map { entry => callHierarchyItem(snap, entry) })
}

/**
 * Re-resolves returned locations in the current snapshot instead of storing database handles.
 */
private func hierarchyRoot(snap: ServerSnapshot, item: CallHierarchyItem): ?CallHierarchyEntry {
    let file = fileOf(snap, item.uri) ?? return None
    prepareCallHierarchy(
        snap.analysis,
        file.fileId(snap.analysis),
        offsetOf(snap, file, item.selectionRange.start)
    )
        .iterator() |>
        filter {
            entry: CallHierarchyEntry =>
            entry.name == item.name && callHierarchyData(snap, entry) == item.data
        } |>
        first
}

/**
 * An opaque binary locator distinguishes overloads sharing a reference location. Re-resolve the
 * location first and compare this data; interned handles are never trusted across snapshots.
 */
func callHierarchyData(snap: ServerSnapshot, entry: CallHierarchyEntry): ?LSPAny {
    let def = entry.definition ?? return None
    match (def.file(snap.analysis)) {
        case Binary(pkg, file) =>
            Some(
                JsonValue.JsonArray(
                    [
                        JsonValue.JsonString(pkg.binary(snap.analysis)),
                        JsonValue.JsonString(pkg.path(snap.analysis).toString()),
                        JsonValue.JsonInteger(file),
                        JsonValue.JsonString(def.item(snap.analysis).toString())
                    ]
                )
            )
        case _ => None
    }
}

/**
 * Translates grouped callers and ranges in each caller's document.
 */
@LspHandler[readonly]
func handleIncomingCalls(
    snap: ServerSnapshot,
    params: CallHierarchyIncomingCallsParams
): Nullable<Array<CallHierarchyIncomingCall>> {
    let root = hierarchyRoot(snap, params.item) ?? return Nullable.Null
    Nullable.Value(
        incomingCalls(snap.analysis, root)
            .map {
                calls =>
                CallHierarchyIncomingCall(
                    from: callHierarchyItem(snap, calls.item),
                    fromRanges: callRanges(snap, calls, calls.item)
                )
            }
    )
}

/**
 * Translates grouped callees; all ranges belong to the requested caller.
 */
@LspHandler[readonly]
func handleOutgoingCalls(
    snap: ServerSnapshot,
    params: CallHierarchyOutgoingCallsParams
): Nullable<Array<CallHierarchyOutgoingCall>> {
    let root = hierarchyRoot(snap, params.item) ?? return Nullable.Null
    Nullable.Value(
        outgoingCalls(snap.analysis, root)
            .map {
                calls =>
                CallHierarchyOutgoingCall(
                    to: callHierarchyItem(snap, calls.item),
                    fromRanges: callRanges(snap, calls, root)
                )
            }
    )
}
