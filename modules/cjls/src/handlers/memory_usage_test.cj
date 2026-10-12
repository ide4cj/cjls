package cjls.handlers

import std.collection.ArrayList
import std.fs.{FSException, Path}
import std.time.MonoTime
import fjson.RawJson
import rope.Encoding
import jsonrpc.*
import cjls.lsp_types.*
import cjls.lsp_ext.*

@Test
class MemoryUsageTest {
    @TestCase
    func aCollectionAskedForIsWaitedForBeforeTheNumbersAreRead() {
        // arrange
        let runtime = FakeHeapRuntime(collectsAfterPauses: 3)

        // act
        let usage = memoryUsage(runtime, MemoryUsageParams(collect: true))

        // assert
        @Expect(usage.gcCount, 1)
        @Expect(runtime.calls.toArray(), ["gc", "pause", "pause", "pause", "usage"])
    }

    @TestCase
    func aCollectionRunBeforeTheRequestReturnsIsNotWaitedFor() {
        // arrange
        let runtime = FakeHeapRuntime(collectsAfterPauses: 0)

        // act
        memoryUsage(runtime, MemoryUsageParams(collect: true))

        // assert
        @Expect(runtime.calls.toArray(), ["gc", "usage"])
    }

    @TestCase
    func aCollectionThatNeverRunsFailsTheRequestOnceTheTimeoutHasPassed() {
        // arrange
        let runtime = FakeHeapRuntime()

        // act
        let e = @AssertThrows[RpcException](memoryUsage(runtime, MemoryUsageParams(collect: true)))

        // assert
        @Expect(e.responseError.code, ErrorCode.REQUEST_FAILED)
        @Expect(runtime.elapsed, COLLECT_TIMEOUT)
    }

    @TestCase
    func withoutCollectNoCollectionIsAskedFor() {
        // arrange
        let runtime = FakeHeapRuntime(collectsAfterPauses: 0)

        // act
        memoryUsage(runtime, MemoryUsageParams())

        // assert
        @Expect(runtime.calls.toArray(), ["usage"])
    }

    @TestCase
    func theHeapIsDumpedAfterTheCollection() {
        // arrange
        let runtime = FakeHeapRuntime(collectsAfterPauses: 0)

        // act
        memoryUsage(runtime, MemoryUsageParams(collect: true, heapDump: "heap.data"))

        // assert
        @Expect(runtime.calls.toArray(), ["gc", "dumpHeap heap.data", "usage"])
    }

    @TestCase
    func aHeapDumpThatCannotBeWrittenFailsTheRequest() {
        // arrange
        let runtime = FakeHeapRuntime(dumpFails: true)

        // act
        let e = @AssertThrows[RpcException](memoryUsage(runtime, MemoryUsageParams(heapDump: "heap.data")))

        // assert
        @Expect(e.responseError.code, ErrorCode.REQUEST_FAILED)
    }

    @TestCase
    func aHeapDumpAskedOfARuntimeThatCannotDumpFailsTheRequestBeforeAnythingIsDone() {
        // arrange
        let runtime = FakeHeapRuntime(collectsAfterPauses: 0, heapDumped: false)

        // act
        let e = @AssertThrows[RpcException](memoryUsage(runtime, MemoryUsageParams(collect: true, heapDump: "heap.data")))

        // assert
        @Expect(e.responseError.code, ErrorCode.REQUEST_FAILED)
        @Expect(runtime.calls.isEmpty())
    }

    @TestCase
    func aRuntimeThatCannotDumpItsHeapStillCollects() {
        // arrange
        let runtime = FakeHeapRuntime(collectsAfterPauses: 0, heapDumped: false)

        // act
        memoryUsage(runtime, MemoryUsageParams(collect: true))

        // assert
        @Expect(runtime.calls.toArray(), ["gc", "usage"])
    }

    @TestCase
    func theRuntimesOwnNumbersAreReported() {
        // act
        let usage = handleMemoryUsage(MemoryUsageParams())

        // assert
        @Expect(usage.usedHeap > 0)
        @Expect(usage.maxHeap > 0) // the used heap may pass it: the runtime grows past its limit
        @Expect(usage.threads >= 1)
    }

    @TestCase
    func absentParamsAskForNothingFirst() {
        // act
        let params = MemoryUsageRequestSpec().decodeParams(Option<RawJson>.None)

        // assert
        @Expect(params.collect.isNone())
        @Expect(params.heapDump.isNone())
    }

    @TestCase
    func paramsThatDoNotReadAreInvalid() {
        // act
        let e = @AssertThrows[RpcException](MemoryUsageRequestSpec().decodeParams(RawJson(##"{"collect": 1}"##.toArray())))

        // assert
        @Expect(e.responseError.code, ErrorCode.INVALID_PARAMS)
    }

    @TestCase
    func theServerAdvertisesItAsAnExperimentalCapability() {
        // act
        let json = RawJson.of(capabilities(Encoding.Utf16)).toString()

        // assert
        @Expect(json.contains(##""experimental":{"memoryUsage":true,"##))
    }
}

/**
 * A runtime whose collection asked for runs after `collectsAfterPauses` pauses (at once for 0,
 * never for `None`), and whose clock moves a millisecond a pause and not otherwise.
 */
class FakeHeapRuntime <: HeapRuntime {
    let calls = ArrayList<String>()
    var elapsed = Duration.Zero
    private let started = MonoTime.now()
    private var count = 0
    private var pausesToCollection: ?Int64 = None

    FakeHeapRuntime(
        private let collectsAfterPauses!: ?Int64 = None,
        private let dumpFails!: Bool = false,
        private let heapDumped!: Bool = true
    ) {}

    public prop dumpsHeap: Bool {
        get() {
            heapDumped
        }
    }

    public func requestGc(): Unit {
        calls.add("gc")
        pausesToCollection = collectsAfterPauses
        collectIfDue()
    }

    public prop gcCount: Int64 {
        get() {
            count
        }
    }

    public func now(): MonoTime {
        started + elapsed
    }

    public func pause(): Unit {
        calls.add("pause")
        elapsed += Duration.millisecond
        if (let Some(n) <- pausesToCollection) {
            pausesToCollection = n - 1
        }
        collectIfDue()
    }

    public func dumpHeap(path: Path): Unit {
        calls.add("dumpHeap ${path}")
        if (dumpFails) {
            throw FSException("cannot write ${path}")
        }
    }

    public func usage(): MemoryUsage {
        calls.add("usage")
        MemoryUsage(usedHeap: 1, allocatedHeap: 1, maxHeap: 1, gcCount: count, gcTime: 0, gcFreed: 0,
            threads: 1)
    }

    private func collectIfDue(): Unit {
        if (pausesToCollection == Some(0)) {
            count++
            pausesToCollection = None
        }
    }
}
