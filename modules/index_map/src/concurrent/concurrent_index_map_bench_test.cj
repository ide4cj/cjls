package index_map.concurrent

import std.unittest.*
import std.unittest.testmacro.*

const INSERT_BENCH_KEYS = 1024

const INSERT_BENCH_WRITERS = 4

// as long as a path in a project, so hashing one costs what it does in an interner
let INSERT_BENCH_KEYS_SEEN = Array<String>(INSERT_BENCH_KEYS) {
    i => "/home/user/projects/app/src/package_${i % 32}/module_${i}/file_${i}.cj"
}

let INSERT_BENCH_FILLED = {=>
    let map = ConcurrentIndexMap<String, Int64>()
    for (key in INSERT_BENCH_KEYS_SEEN) {
        map.addIfAbsentWithIndex(key, 0)
    }
    map
}()

/**
 * Inserting into a `ConcurrentIndexMap`: a key seen (no lock), keys never seen (the lock), and
 * several threads inserting the same keys at once; #117 measured the insert that hashes a new key
 * once more, not twice, with it. `cjpm bench '--filter=ConcurrentIndexMapInsertBench.*'`.
 */
@Test
class ConcurrentIndexMapInsertBench {
    @Bench
    func insertAKeySeen(): Int64 {
        INSERT_BENCH_FILLED.addIfAbsentWithIndex(INSERT_BENCH_KEYS_SEEN[INSERT_BENCH_KEYS / 2], 0)[0]
    }

    /**
     * A new map given `INSERT_BENCH_KEYS` keys, one thread.
     */
    @Bench
    func insertKeysNeverSeen(): Int64 {
        let map = ConcurrentIndexMap<String, Int64>()
        for (key in INSERT_BENCH_KEYS_SEEN) {
            map.addIfAbsentWithIndex(key, 0)
        }
        map.size
    }

    @Bench
    func getOrAddAKeySeen(): Int64 {
        INSERT_BENCH_FILLED.getOrAdd(INSERT_BENCH_KEYS_SEEN[INSERT_BENCH_KEYS / 2]) {=> 0}[0]
    }

    /**
     * As `insertKeysNeverSeen`, by `getOrAdd`.
     */
    @Bench
    func getOrAddKeysNeverSeen(): Int64 {
        let map = ConcurrentIndexMap<String, Int64>()
        for (key in INSERT_BENCH_KEYS_SEEN) {
            map.getOrAdd(key) {=> 0}
        }
        map.size
    }

    /**
     * A new map given the same `INSERT_BENCH_KEYS` keys by `INSERT_BENCH_WRITERS` threads at once,
     * each from its own place.
     */
    @Bench
    func insertFromSeveralThreads(): Int64 {
        let map = ConcurrentIndexMap<String, Int64>()
        let writers = Array(INSERT_BENCH_WRITERS) {
            writer => spawn {
                for (i in 0..INSERT_BENCH_KEYS) {
                    let key = (i + writer * INSERT_BENCH_KEYS / INSERT_BENCH_WRITERS) % INSERT_BENCH_KEYS
                    map.addIfAbsentWithIndex(INSERT_BENCH_KEYS_SEEN[key], 0)
                }
            }
        }
        for (writer in writers) {
            writer.get()
        }
        map.size
    }
}
