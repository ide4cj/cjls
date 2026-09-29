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
 * Whether the runtime here dumps its heap: on Windows `dumpHeapData` never returns, with the
 * nightlies of 2026-09-18 and 09-29 alike, while `gc(heavy: true)` does (#64).
 */
@When[os == "Windows"]
let DUMPS_HEAP = false

@When[os != "Windows"]
let DUMPS_HEAP = true

@LspHandler[readonly]
func handleMemoryUsage(params: MemoryUsageParams): MemoryUsage {
    memoryUsage(StdHeapRuntime(), params)
}

/**
 * @throws RpcException - `REQUEST_FAILED`, if a heap dump is asked of a runtime that cannot dump
 * its heap (before anything else is done), the collection asked for has not run in
 * `COLLECT_TIMEOUT`, or the heap dump cannot be written where asked
 */
func memoryUsage(runtime: HeapRuntime, params: MemoryUsageParams): MemoryUsage {
    if (params.heapDump.isSome() && !runtime.dumpsHeap) {
        throw RpcException(ErrorCode.REQUEST_FAILED, "no heap dump on this platform")
    }
    if ((params.collect ?? false) && !collect(runtime)) {
        throw RpcException(ErrorCode.REQUEST_FAILED, "no collection ran in ${COLLECT_TIMEOUT}")
    }
    if (let Some(path) <- params.heapDump) {
        try {
            runtime.dumpHeap(Path(path))
        } catch (e: FSException) {
            throw RpcException(ErrorCode.REQUEST_FAILED, e.message)
        }
    }
    runtime.usage()
}

/**
 * A full collection, waited for: `gc(heavy: true)` returns before the collector has run. False if
 * none ran in `COLLECT_TIMEOUT`.
 */
func collect(runtime: HeapRuntime): Bool {
    let before = runtime.gcCount
    let started = runtime.now()
    runtime.requestGc()
    while (runtime.gcCount == before && runtime.now() - started < COLLECT_TIMEOUT) {
        runtime.pause()
    }
    runtime.gcCount != before
}

/**
 * What `cjls/memoryUsage` asks of the runtime, the collector's timing and the clock with it: its
 * tests decide when a collection runs rather than wait for one.
 */
interface HeapRuntime {
    /**
     * Whether `dumpHeap` may be called: false where it never returns.
     */
    prop dumpsHeap: Bool

    /**
     * Asks for a full collection; it may run after this returns, or not at all.
     */
    func requestGc(): Unit

    /**
     * Collections run since the start.
     */
    prop gcCount: Int64

    func now(): MonoTime

    /**
     * A moment's wait while a collection is awaited.
     */
    func pause(): Unit

    /**
     * @throws FSException - if the dump cannot be written at `path`
     */
    func dumpHeap(path: Path): Unit

    func usage(): MemoryUsage
}

class StdHeapRuntime <: HeapRuntime {
    public prop dumpsHeap: Bool {
        get() {
            DUMPS_HEAP
        }
    }

    public func requestGc(): Unit {
        gc(heavy: true)
    }

    public prop gcCount: Int64 {
        get() {
            getGCCount()
        }
    }

    public func now(): MonoTime {
        MonoTime.now()
    }

    public func pause(): Unit {
        sleep(Duration.millisecond)
    }

    public func dumpHeap(path: Path): Unit {
        dumpHeapData(path)
    }

    public func usage(): MemoryUsage {
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
}
