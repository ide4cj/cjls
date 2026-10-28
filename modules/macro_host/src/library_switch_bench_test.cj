package macro_host

import std.env.getVariable
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import macro_server.*

/**
 * Measures K28's process cost with prebuilt SDK libraries, excluding compilation.
 * Set CJLS_K28_BENCH_DIR to a persistent directory inside this worktree. Run once
 * before taking the measurement lock to populate the compiler cache.
 */
@Test
@Configure[warmup: Duration.second, minDuration: Duration.second, minBatches: 10]
class MacroLibrarySwitchBench {
    var calls: Array<MacroCallData> = []
    var server: ?MacroServers = None

    @BeforeAll
    func prepare(): Unit {
        let paths = testSdkPaths()
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
        expanded(calls[0])
    }

    /**
     * Twenty requests: block 1 alternates on every call; block 5 switches four
     * times per round; block 20 stays in one library across rounds.
     * Conflicting helper outputs are checked by SameNameMacroLibraryTest, not
     * here: the deliberately unsafe baseline must remain measurable too.
     */
    @Bench[block in [1, 5, 20]]
    func twentyCalls(block: Int64): Int64 {
        var count = 0
        for (i in 0..20) {
            count += expanded(calls[(i / block) % 2])
        }
        count
    }

    private func expanded(call: MacroCallData): Int64 {
        match (server.getOrThrow().expand(call)) {
            case Answered(result) =>
                if (result.status == MACRO_FAILED) {
                    throw IllegalStateException("macro expansion failed")
                }
                result.tks.size
            case Unanswered(reason) => throw IllegalStateException(reason)
        }
    }
}
