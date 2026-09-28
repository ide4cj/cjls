package calca

import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

const FETCH_BENCH_FILES = 256

const FETCH_BENCH_READERS = 4

@CalcaTracked
func benchWords(db: TestDb, file: SourceFile): Int64 {
    file.text(db).split(" ").size
}

let FETCH_BENCH_DB = {=>
    let db = TestDatabase()
    let files = Array<SourceFile>(FETCH_BENCH_FILES) {i => SourceFile(db, "${i}.cj", "text of ${i}")}
    for (file in files) {
        benchWords(db, file)
    }
    (db, files)
}()

/**
 * Every file's memo once, on `db`: all of them hit.
 */
func fetchEveryFile(db: TestDatabase, files: Array<SourceFile>): Int64 {
    var sum = 0
    for (file in files) {
        sum += benchWords(db, file)
    }
    sum
}

/**
 * Fetches that hit, on one snapshot and on several at once, as handlers off the read loop make
 * them: what the memo table's lock costs a reader, and what readers cost one another.
 * `cjpm bench '--filter=ParallelFetchBench.*'`.
 */
@Test
class ParallelFetchBench {
    @Bench
    func oneSnapshot(): Int64 {
        let (db, files) = FETCH_BENCH_DB
        fetchEveryFile(db.snapshot(), files)
    }

    @Bench
    func severalSnapshotsAtOnce(): Int64 {
        let (db, files) = FETCH_BENCH_DB
        let readers = Array(FETCH_BENCH_READERS) {
            _ =>
            let snapshot = db.snapshot()
            spawn {
                fetchEveryFile(snapshot, files)
            }
        }
        readers.iterator().fold(0) {sum, reader => sum + reader.get()}
    }

    /**
     * What `severalSnapshotsAtOnce` would cost with no contention: the same threads, one after
     * another.
     */
    @Bench
    func severalSnapshotsInTurn(): Int64 {
        let (db, files) = FETCH_BENCH_DB
        var sum = 0
        for (_ in 0..FETCH_BENCH_READERS) {
            let snapshot = db.snapshot()
            sum += spawn {
                fetchEveryFile(snapshot, files)
            }.get()
        }
        sum
    }
}
