package project_model

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.SourceFile
import loupe.hir.*

/**
 * Each name after a `.` in a body of the workspace that resolves to nothing, by `onFailed`; how many
 * name a declaration of a package or a member of a type, and how many follow a value (inference's).
 */
func resolveEveryField(ws: BenchWorkspace,
    onFailed!: (SourceFile, DefId, ExprId) -> Unit = {_, _, _ => ()}): (Int64, Int64) {
    var resolved = 0
    var ofValues = 0
    for ((_, file, _) in ws.files) {
        for (def in defsOf(ws, file)) {
            let lowered = body(ws.db, def)
            for (i in 0..lowered.exprs.size) {
                if (let FieldExpr(_, _, _) <- lowered.exprs[i]) {
                    match (resolveField(ws.db, def, ExprId(i))) {
                        case PackageMembers(_) | TypeMembers(_) => resolved++
                        case OfValue => ofValues++
                        case NoField => onFailed(file, def, ExprId(i))
                    }
                }
            }
        }
    }
    (resolved, ofValues)
}

/**
 * The names after a `.` in this repository's bodies, resolved, every query memoized past the first
 * run, which the default heap does not hold: `cjHeapSize=2GB cjpm bench '--filter=FieldResolutionBench.*'`.
 */
@Test
class FieldResolutionBench {
    @Bench
    func resolveEveryNameAfterADot(): (Int64, Int64) {
        resolveEveryField(workspace())
    }
}
