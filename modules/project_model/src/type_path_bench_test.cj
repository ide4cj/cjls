package project_model

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.SourceFile
import loupe.hir.*

/**
 * The declarations of `file` and their members.
 */
func defsOf(ws: BenchWorkspace, file: SourceFile): Array<DefId> {
    let defs = ArrayList<DefId>()
    func add(items: Array<Item>): Unit {
        for (item in items) {
            defs.add(DefId(ws.db, ItemFile.Source(file), item.id))
            add(item.members)
        }
    }
    add(itemTree(ws.db, file).items)
    defs.toArray()
}

/**
 * Each path in a type of a signature of the workspace that does not resolve, by `onFailed`; how many
 * segments do.
 */
func resolveEveryTypePath(ws: BenchWorkspace, onFailed!: (SourceFile, String, PathResolution) -> Unit = {_, _, _ => ()}): Int64 {
    var resolved = 0
    for ((_, file, _) in ws.files) {
        for (def in defsOf(ws, file)) {
            let sig = signature(ws.db, def)
            let scope = typeScopeOf(ws.db, def) ?? continue
            for (ty in sig.types) {
                if (let PathRef(segments) <- ty) {
                    let names = segments.map {segment => segment.name}
                    for (resolution in resolveTypePath(ws.db, scope, names)) {
                        match (resolution) {
                            case Resolved(_) => resolved++
                            case _ => onFailed(file, String.join(names, delimiter: "."), resolution)
                        }
                    }
                }
            }
        }
    }
    resolved
}

/**
 * The paths in the types of this repository's signatures, resolved: `cjpm bench '--filter=TypePathBench.*'`.
 */
@Test
class TypePathBench {
    @Bench
    func resolveEveryPathInASignature(): Int64 {
        resolveEveryTypePath(workspace())
    }
}
