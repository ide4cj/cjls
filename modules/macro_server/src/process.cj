package macro_server

import std.fs.*
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
    MacroServerProcess(let child: PipedChild, public let connection: MacroConnection) {}

    /**
     * Asks the server to exit, and waits until it has; ends it if it cannot be asked.
     */
    public func close(): Unit {
        try {
            connection.close()
        } catch (_: Exception) {
            child.kill()
        }
        child.wait()
    }

    /**
     * Ends the server at once: a macro that loops is never answered.
     */
    public func kill(): Unit {
        child.kill()
        child.wait()
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
public func startMacroServer(paths: MacroServerPaths): MacroServerProcess {
    let child =
        startPiped(
            paths.server,
            macroServerLibraryDirs(paths),
            { pipes => macroServerArgs(paths, pipes) }
        )
    MacroServerProcess(child, MacroConnection(child.fromChild, child.toChild))
}
