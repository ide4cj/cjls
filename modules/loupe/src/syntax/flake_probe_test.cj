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

func probeDb(): (AnalysisDatabase, SourceFile, FileId) {
    let db = AnalysisDatabase()
    let file = db.setFileText(FileId(0), Rope("func f() {}\nfunc g() {}\n"))
    let other = FileId(1)
    db.setFileText(other, Rope(""))
    (db, file, other)
}

func evictAndWrite(db: AnalysisDatabase, other: FileId): Unit {
    for (j in 0..PARSE_LRU) {
        parse(db, db.setFileText(FileId(100 + j), Rope("let x${j} = ${j}")))
    }
    db.setFileText(other, Rope("changed"))
}

@Test
class FlakeProbeTest {
    @TestCase
    func aResultHoldingANodeKeepsAnEvictedTreeAliveRepeated() {
        var treeFreed = 0
        var rootFreed = 0
        var rootAliveTreeFreed = 0
        var runBefore = 0
        var runAfterFreed = 0
        for (_ in 0..300) {
            let (db, file, other) = probeDb()
            let tree = weakTree(db, file)
            let root = weakRoot(db, file)
            let runs = db.storage.executionsOf("rootOf")
            @Expect(runs, 1)
            evictAndWrite(db, other)

            let freed = isFreed(tree)
            let rootGone = root.value.isNone()
            if (db.storage.executionsOf("rootOf") != runs) {
                runBefore++
            }
            @Expect(rootOf(db, file).text(), file.text(db).toString())
            if (freed) {
                treeFreed++
                if (rootGone) {
                    rootFreed++
                } else {
                    rootAliveTreeFreed++
                }
                // calca dropped the value: fetched again, it is computed again; the GC freed what the memo
                // holds: it is answered from the memo
                if (db.storage.executionsOf("rootOf") != runs) {
                    runAfterFreed++
                }
            }
        }
        println("PROBE1 treeFreed=${treeFreed} rootFreed=${rootFreed} rootAliveTreeFreed=${rootAliveTreeFreed} runBefore=${runBefore} runAfterFreed=${runAfterFreed}")
        @Expect(treeFreed, 0)
    }

    /**
     * The test holds the node itself: a tree freed here is the GC's doing alone.
     */
    @TestCase
    func aNodeHeldByTheTestKeepsItsTreeAliveRepeated() {
        var treeFreed = 0
        var corrupt = 0
        let descendantsWhole = wholeDescendants()
        for (_ in 0..300) {
            let (db, file, other) = probeDb()
            let tree = weakTree(db, file)
            let node = rootOf(db, file)
            evictAndWrite(db, other)

            if (isFreed(tree)) {
                treeFreed++
                churn()
                if (node.text() != file.text(db).toString() || countDescendants(node) != descendantsWhole) {
                    corrupt++
                }
            }
            @Expect(node.text(), file.text(db).toString())
        }
        println("PROBE2 treeFreed=${treeFreed} corrupt=${corrupt}")
        @Expect(treeFreed, 0)
    }

    /**
     * Neither calca nor the test holds the tree after its eviction but through `parse`'s memo, kept by no `lru`
     * eviction: a control, the tree should stay.
     */
    @TestCase
    func aTreeNotEvictedStaysRepeated() {
        var treeFreed = 0
        for (_ in 0..300) {
            let (db, file, other) = probeDb()
            let tree = weakTree(db, file)
            db.setFileText(other, Rope("changed"))

            if (isFreed(tree)) {
                treeFreed++
            }
            @Expect(rootOf(db, file).text(), file.text(db).toString())
        }
        println("PROBE3 treeFreed=${treeFreed}")
        @Expect(treeFreed, 0)
    }

    /**
     * std alone, no calca, no loupe: an object a local holds and uses after, a weak reference to it.
     */
    @TestCase
    func aHeldObjectsWeakReferenceStaysRepeated() {
        var cleared = 0
        var corrupt = 0
        for (i in 0..300) {
            let payload = Payload(4096, i)
            let weak = WeakRef(payload, CleanupPolicy.EAGER)
            churn()
            if (isFreed(weak)) {
                cleared++
                churn()
                if (!payload.intact(i)) {
                    corrupt++
                }
            }
            @Expect(payload.intact(i))
        }
        println("PROBE4 cleared=${cleared} corrupt=${corrupt}")
        @Expect(cleared, 0)
    }
}

class Payload {
    let data: Array<Int64>

    init(size: Int64, seed: Int64) {
        data = Array<Int64>(size) {j => seed * 7919 + j}
    }

    func intact(seed: Int64): Bool {
        var ok = true
        for (j in 0..data.size) {
            if (data[j] != seed * 7919 + j) {
                ok = false
            }
        }
        ok
    }
}

/**
 * Allocates enough garbage for the GC to reuse what it freed.
 */
func churn(): Unit {
    var sum = 0
    for (k in 0..2000) {
        let garbage = Array<Int64>(1024) {j => j + k}
        sum += garbage[k % 1024]
    }
    if (sum == -1) {
        println(sum)
    }
}

func countDescendants(node: CjSyntaxNode): Int64 {
    var n = 0
    for (_ in node.descendants()) {
        n++
    }
    n
}

func wholeDescendants(): Int64 {
    let (db, file, _) = probeDb()
    countDescendants(rootOf(db, file))
}
