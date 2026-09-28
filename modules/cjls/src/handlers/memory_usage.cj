package cjls.handlers

import std.fs.{FSException, Path}
import std.runtime.*
import std.time.MonoTime
import jsonrpc.{ErrorCode, RpcException}
import cjls.lsp_types.*
import cjls.lsp_ext.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * How long `collect` waits for the collection it asked for.
 */
let COLLECT_TIMEOUT = Duration.second * 5

/**
 * @throws RpcException - `REQUEST_FAILED`, if the heap dump cannot be written where asked
 */
@LspHandler[readonly]
func handleMemoryUsage(params: MemoryUsageParams): MemoryUsage {
    if (params.collect ?? false) {
        collect()
    }
    if (let Some(path) <- params.heapDump) {
        try {
            dumpHeapData(Path(path))
        } catch (e: FSException) {
            throw RpcException(ErrorCode.REQUEST_FAILED, e.message)
        }
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
