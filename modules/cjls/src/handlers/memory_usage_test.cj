package cjls.handlers

import std.fs.{exists, remove, Path}
import std.env.getTempDirectory
import fjson.RawJson
import rope.Encoding
import jsonrpc.*
import cjls.lsp_ext.*

@Test
class MemoryUsageTest {
    @TestCase
    func afterACollectionTheHeapInUseAndTheCollectionsAreReported() {
        // act
        let usage = handleMemoryUsage(MemoryUsageParams(collect: true))

        // assert
        @Expect(usage.usedHeap > 0)
        @Expect(usage.usedHeap <= usage.maxHeap)
        @Expect(usage.gcCount >= 1)
        @Expect(usage.threads >= 1)
    }

    @TestCase
    func aHeapDumpIsWrittenWhereAsked() {
        // arrange
        let path = getTempDirectory().join("cjls-memory-usage-test.data")
        if (exists(path)) {
            remove(path)
        }

        // act
        handleMemoryUsage(MemoryUsageParams(heapDump: path.toString()))

        // assert
        @Expect(exists(path))
        remove(path)
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
        @Expect(json.contains(##""experimental":{"memoryUsage":true}"##))
    }
}
