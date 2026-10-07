package project_model

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.SourceFile
import loupe.hir.*

/**
 * Each expression of a body of the workspace whose type is an error, by `onUnknown`; how many
 * expressions there are.
 */
func inferEveryBody(ws: BenchWorkspace, onUnknown!: (SourceFile, DefId, ExprId) -> Unit = {_, _, _ => ()}): Int64 {
    var count = 0
    for ((_, file, _) in ws.files) {
        for (def in defsOf(ws, file)) {
            let result = inferBody(ws.db, def)
            for (i in 0..result.exprs.size) {
                if (result.exprs[i].kind(ws.db) == ErrorTy) {
                    onUnknown(file, def, ExprId(i))
                }
            }
            count += result.exprs.size
        }
    }
    count
}

/**
 * The types of this repository's bodies, read once they are computed: what a run after the first
 * measures is the memos read, not the inference. `cjHeapSize=2GB cjpm bench '--filter=InferenceBench.*'`.
 */
@Test
class InferenceBench {
    @Bench
    func readTheTypesOfEveryBodyOfTheWorkspaceComputed(): Int64 {
        inferEveryBody(workspace())
    }
}
