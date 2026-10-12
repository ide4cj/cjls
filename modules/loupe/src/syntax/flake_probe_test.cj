package loupe.syntax

import std.ref.*
import std.unittest.*
import std.unittest.testmacro.*
import cjsyntax.*
import rope.Rope
import loupe.db.*
import loupe.vfs.FileId

/**
 * Temporary, an experiment on macOS CI: aResultHoldingANodeKeepsAnEvictedTreeAlive repeated, each failure told
 * apart by what else is gone: the memo's node (calca dropped it) or only the tree (the node holds it).
 */
func weakRoot(db: AnalysisDatabase, file: SourceFile): WeakRef<CjSyntaxNode> {
    WeakRef(rootOf(db, file), CleanupPolicy.EAGER)
}

@Test
class FlakeProbeTest {
    @TestCase
    func aResultHoldingANodeKeepsAnEvictedTreeAliveRepeated() {
        var treeFreed = 0
        var rootFreed = 0
        var rootAliveTreeFreed = 0
        var rootRunAgain = 0
        for (i in 0..300) {
            let db = AnalysisDatabase()
            let file = db.setFileText(FileId(0), Rope("func f() {}\nfunc g() {}\n"))
            let other = FileId(1)
            db.setFileText(other, Rope(""))
            let tree = weakTree(db, file)
            let root = weakRoot(db, file)
            let rootRuns = db.storage.executionsOf("rootOf")
            for (j in 0..PARSE_LRU) {
                parse(db, db.setFileText(FileId(100 + j), Rope("let x${j} = ${j}")))
            }
            db.setFileText(other, Rope("changed"))

            let freed = isFreed(tree)
            let rootGone = root.value.isNone()
            if (freed) {
                treeFreed++
                if (rootGone) {
                    rootFreed++
                } else {
                    rootAliveTreeFreed++
                }
            }
            if (db.storage.executionsOf("rootOf") != rootRuns) {
                rootRunAgain++
            }
            @Expect(rootOf(db, file).text(), file.text(db).toString())
        }
        println("PROBE treeFreed=${treeFreed} rootFreed=${rootFreed} rootAliveTreeFreed=${rootAliveTreeFreed} rootRunAgain=${rootRunAgain}")
        @Expect(treeFreed, 0)
    }
}
