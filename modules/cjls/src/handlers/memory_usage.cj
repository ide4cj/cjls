package cjls.handlers

import std.fs.Path
import std.runtime.*
import std.time.MonoTime
import cjls.lsp_ext.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * How long `collect` waits for the collection it asked for.
 */
let COLLECT_TIMEOUT = Duration.second * 5

@LspHandler[readonly]
func handleMemoryUsage(params: MemoryUsageParams): MemoryUsage {
    if (params.collect ?? false) {
        collect()
    }
    if (let Some(path) <- params.heapDump) {
        dumpHeapData(Path(path))
    }
    MemoryUsage(
        usedHeap: getUsedHeapSize(),
        allocatedHeap: getAllocatedHeapSize(),
        maxHeap: getMaxHeapSize(),
        gcCount: getGCCount(),
        gcTime: getGCTime(),
        gcFreed: getGCFreedSize(),
        threads: getThreadCount()
    )
}

/**
 * A full collection, waited for: `gc(heavy: true)` returns before the collector has run.
 */
func collect(): Unit {
    let before = getGCCount()
    let started = MonoTime.now()
    gc(heavy: true)
    while (getGCCount() == before && MonoTime.now() - started < COLLECT_TIMEOUT) {
        sleep(Duration.millisecond)
    }
}
