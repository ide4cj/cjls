package macro_host

import std.env.getVariable
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import macro_server.*

/**
 * Compares K28's per-switch restart cost with process reuse, excluding compilation.
 * Set CJLS_K28_BENCH_DIR to a persistent directory inside this worktree. Run once
 * before taking the measurement lock to populate the compiler cache.
 */
@Test
@Configure[warmup: Duration.second, minDuration: Duration.second, minBatches: 10]
class MacroLibrarySwitchBench {
    var calls: Array<MacroCallData> = []
    var server: ?MacroServers = None
    var paths: ?MacroServerPaths = None

    @BeforeAll
    func prepare(): Unit {
        let paths = testSdkPaths()
        this.paths = paths
        let numbers = testNumbers()
        let root = Path(getVariable("CJLS_K28_BENCH_DIR").getOrThrow())
        let manifest = root.join("libraries.txt")
        if (!exists(manifest)) {
            let libraries = conflictingLibraries(root, SdkToolchain(paths), false)
            let lines = libraries.map { pair => "${pair[0]}\n${pair[1]}" }
            File.writeTo(manifest, String.join(lines, delimiter: "\n").toArray())
        }
        let lines = String.fromUtf8(File.readFrom(manifest)).split("\n")
        calls =
            [
                conflictingLibraryCall(lines[0], lines[1], numbers),
                conflictingLibraryCall(lines[2], lines[3], numbers)
            ]
        server = MacroServers(paths, Duration.minute, NoopLogger())
    }

    @AfterAll
    func finish(): Unit {
        server?.close()
    }

    @Bench
    func sameLibraryCall(): Int64 {
        expanded(server.getOrThrow(), calls[0])
    }

    /**
     * Twenty requests including startup and shutdown: block 1 alternates on
     * every call; block 5 switches every five calls; block 20 uses one library.
     * A fresh server per iteration prevents the SDK's growing library-handle
     * list from making later cases depend on earlier cases' warmup lengths.
     * This measures successful SDK responses, not isolation of conflicting
     * helper code: K28 remains a known limitation of process reuse.
     */
    @Bench[block in [1, 5, 20]]
    func twentyCalls(block: Int64): Int64 {
        let batchServer = MacroServers(paths.getOrThrow(), Duration.minute, NoopLogger())
        try {
            var count = 0
            for (i in 0..20) {
                count += expanded(batchServer, calls[(i / block) % 2])
            }
            count
        } finally {
            batchServer.close()
        }
    }

    private func expanded(expander: MacroServers, call: MacroCallData): Int64 {
        match (expander.expand(call)) {
            case Answered(result) =>
                if (result.status == MACRO_FAILED) {
                    throw IllegalStateException("macro expansion failed")
                }
                result.tks.size
            case Unanswered(reason) => throw IllegalStateException(reason)
        }
    }
}
