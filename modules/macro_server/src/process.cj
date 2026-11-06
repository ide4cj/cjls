package macro_server

import std.env.getTempDirectory
import std.fs.*
import std.io.SeekPosition
import platform.{ChildPipes, PipedChild, startPiped}

/**
 * Where an SDK keeps what the server needs: the server, the `cjc` it finds its runtime by
 * (`dirname(cjc)/../runtime/lib/<host>`), that runtime, which `dlopen` needs to load a macro's library, and the
 * `Tokens.inc` cjc's token kinds are numbered by (`TokenNumbers`).
 */
public struct MacroServerPaths {
    public MacroServerPaths(
        public let server!: Path,
        public let cjc!: Path,
        public let runtimeLib!: Path,
        public let tokensInc!: Path
    ) {}

    /**
     * Those of the SDK at `home` for the host `target` (`linux_x86_64_cjnative`).
     */
    public static func inSdk(home: Path, target: String): MacroServerPaths {
        let exe = if (target.startsWith("windows")) { ".exe" } else { "" }
        MacroServerPaths(
            server: home.join("tools").join("bin").join("LSPMacroServer${exe}"),
            cjc: home.join("bin").join("cjc${exe}"),
            runtimeLib: home.join("runtime").join("lib").join(target),
            tokensInc: home.join("include").join("cangjie").join("Lex").join("Tokens.inc")
        )
    }

    /**
     * The library of the macros of std's package `pkg` (`std.unittest.testmacro`) the SDK ships beside its runtime:
     * `libcangjie-std-unittest.testmacro.so`, `.dylib` or `.dll`; `None` if there is none.
     */
    public func stdMacroLibrary(pkg: String): ?Path {
        let name = "libcangjie-std-${pkg.removePrefix("std.")}"
        for (suffix in [".so", ".dylib", ".dll"]) {
            let library = runtimeLib.join(name + suffix)
            if (exists(library)) {
                return library
            }
        }
        None
    }
}

/**
 * An `LSPMacroServer` running: its process and the connection to it.
 */
public class MacroServerProcess {
    MacroServerProcess(
        let child: PipedChild,
        public let connection: MacroConnection,
        private let directory: Path,
        private let output: File
    ) {}

    /**
     * Start a call with an empty output file. Calls are serial, so the child is idle here.
     */
    public func clearOutput(): Unit {
        output.setLength(0)
        output.seek(SeekPosition.Begin(0))
    }

    /**
     * The last 64 KiB written by this call; never block on a pipe or retain unbounded output.
     */
    public func callOutput(): String {
        let reader = File(directory.join("output"), OpenMode.Read)
        try {
            let size = reader.length
            let start = max(0, size - 65536)
            reader.seek(SeekPosition.Begin(start))
            let buffer = Array<Byte>(min(size, 65536), repeat: 0)
            if (buffer.isEmpty()) {
                return ""
            }
            let count = reader.read(buffer)
            var from = 0
            // A bounded tail may start within a UTF-8 character.
            while (from < count && (buffer[from] & 0xC0) == 0x80) {
                from++
            }
            let text = String.fromUtf8(buffer[from..count])
            if (start > 0) { "[macro output truncated]\n${text}" } else { text }
        } catch (_: Exception) {
            "[macro output could not be decoded]"
        } finally {
            reader.close()
        }
    }

    private func cleanup(): Unit {
        output.close()
        remove(directory, recursive: true)
    }

    /**
     * Asks the server to exit, and waits until it has; ends it if it cannot be asked.
     */
    public func close(): Unit {
        try {
            connection.close()
        } catch (_: Exception) {
            child.kill()
        }
        try {
            child.wait()
        } finally {
            cleanup()
        }
    }

    /**
     * Ends the server at once: a macro that loops is never answered.
     */
    public func kill(): Unit {
        child.kill()
        try {
            child.wait()
        } finally {
            cleanup()
        }
    }
}

/**
 * The server's arguments after its own path (`src/main-macrosrv.cpp`): the pipe end it reads, the one it writes,
 * `0` for serial, `cjc`, whose directory it finds the runtime by, and the process it exits with, where the
 * platform does not end it itself.
 */
func macroServerArgs(paths: MacroServerPaths, pipes: ChildPipes): Array<String> {
    let args = [pipes.read, pipes.write, "0", paths.cjc.toString()]
    match (pipes.parent) {
        case Some(pid) => args.concat(["${pid}"])
        case None => args
    }
}

/**
 * Where the server's shared libraries are looked for first, as the SDK's `envsetup` orders them: the runtime a
 * macro's library needs, then the directory of the server's own `libcangjie-lsp`, which its `RUNPATH` names
 * (`$ORIGIN/../lib`) but an inherited library path comes before. One that names another SDK's `tools/lib` (the
 * pinned nightly's, under the tests) has 1.0.5's server load that SDK's `libcangjie-lsp` and crash at its start
 * (#310).
 */
func macroServerLibraryDirs(paths: MacroServerPaths): Array<Path> {
    let toolsLib = paths.server.parent.parent.join("lib")
    [paths.runtimeLib, toolsLib]
}

/**
 * Starts the server of `paths`, serial, through `startPiped`: on POSIX watching this process, which it outlives
 * by about 4 s at most; on Windows in a job that ends it with this process.
 *
 * @throws ProcessException - if it cannot be started on POSIX
 * @throws ProcessStartException - if it cannot be started on Windows
 */
public func startMacroServer(
    paths: MacroServerPaths,
    nativeDirectories!: Array<Path> = []
): MacroServerProcess {
    let directory = Directory.createTemp(getTempDirectory())
    let output = File(directory.join("output"), OpenMode.Write)
    try {
        let child = startPiped(
            paths.server,
            macroServerLibraryDirs(paths).concat(nativeDirectories),
            { pipes => macroServerArgs(paths, pipes) },
            output: output
        )
        MacroServerProcess(
            child,
            MacroConnection(child.fromChild, child.toChild),
            directory,
            output
        )
    } catch (e: Exception) {
        output.close()
        remove(directory, recursive: true)
        throw e
    }
}
