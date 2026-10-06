package project_model

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.SourceFile
import loupe.hir.*

/**
 * Each name used in a body of the workspace that resolves to nothing, or to an ambiguity, by
 * `onFailed`; how many do resolve. A name after a `.` is inference's, not counted.
 */
func resolveEveryBodyName(ws: BenchWorkspace, onFailed!: (SourceFile, DefId, String, BodyResolution) -> Unit = {_, _, _, _ => ()}): Int64 {
    var resolved = 0
    for ((_, file, _) in ws.files) {
        for (def in defsOf(ws, file)) {
            let lowered = body(ws.db, def)
            let scopes = exprScopes(ws.db, def)
            for (i in 0..lowered.exprs.size) {
                if (let PathExpr(name, _) <- lowered.exprs[i]) {
                    let resolution = resolveBodyName(ws.db, def, scopes.scopeOf(ExprId(i)), name)
                    match (resolution) {
                        case Values(_) => resolved++
                        case InFile(Found(_)) | InFile(FoundPackage(_)) | InFile(Ctors(_, _)) => resolved++
                        case _ => onFailed(file, def, name, resolution)
                    }
                }
            }
        }
    }
    resolved
}

/**
 * The names used in this repository's bodies, resolved, every query memoized past the first run, which the default
 * heap does not hold: `cjHeapSize=2GB cjpm bench '--filter=BodyResolutionBench.*'`.
 */
@Test
class BodyResolutionBench {
    @Bench
    func resolveEveryNameInABody(): Int64 {
        resolveEveryBodyName(workspace())
    }
}
