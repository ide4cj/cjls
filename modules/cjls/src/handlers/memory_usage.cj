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
 * Whether the runtime here collects and dumps its heap on request: on Windows a test of `dumpHeapData`,
 * or of it after `gc(heavy: true)`, never returned on CI's runner (#64).
 */
@When[os == "Windows"]
let CONTROLS_HEAP = false

@When[os != "Windows"]
let CONTROLS_HEAP = true

@LspHandler[readonly]
func handleMemoryUsage(params: MemoryUsageParams): MemoryUsage {
    memoryUsage(StdHeapRuntime(), params)
}

/**
 * @throws RpcException - `REQUEST_FAILED`, if a collection or a heap dump is asked of a runtime
 * that does not control its heap, the collection asked for has not run in `COLLECT_TIMEOUT`, or
 * the heap dump cannot be written where asked
 */
func memoryUsage(runtime: HeapRuntime, params: MemoryUsageParams): MemoryUsage {
    if (((params.collect ?? false) || params.heapDump.isSome()) && !runtime.controlsHeap) {
        throw RpcException(ErrorCode.REQUEST_FAILED, "no collection or heap dump on this platform")
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
     * Whether `requestGc` and `dumpHeap` may be called: false where they never return.
     */
    prop controlsHeap: Bool

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
    public prop controlsHeap: Bool {
        get() {
            CONTROLS_HEAP
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
