package macro_server

import std.env.getProcessId
import std.fs.*
import std.process.*

/**
 * Where an SDK keeps what the server needs: the server, the `cjc` it finds its runtime by
 * (`dirname(cjc)/../runtime/lib/<host>`), and that runtime, which `dlopen` needs to load a macro's library.
 */
public struct MacroServerPaths {
    public MacroServerPaths(public let server!: Path, public let cjc!: Path, public let runtimeLib!: Path) {}

    /**
     * Those of the SDK at `home` for the host `target` (`linux_x86_64_cjnative`).
     */
    public static func inSdk(home: Path, target: String): MacroServerPaths {
        let exe = if (target.startsWith("windows")) {
            ".exe"
        } else {
            ""
        }
        MacroServerPaths(
            server: home.join("tools").join("bin").join("LSPMacroServer${exe}"),
            cjc: home.join("bin").join("cjc${exe}"),
            runtimeLib: home.join("runtime").join("lib").join(target)
        )
    }
}

/**
 * An `LSPMacroServer` running: its process and the connection to it.
 */
public class MacroServerProcess {
    MacroServerProcess(let process: SubProcess, public let connection: MacroConnection) {}

    /**
     * Asks the server to exit, and waits until it has; ends it if it does not answer.
     */
    public func close(): Unit {
        try {
            connection.close()
        } catch (_: Exception) {
            process.terminate(force: true)
        }
        process.wait()
        ()
    }

    /**
     * Ends the server at once: a macro that loops is never answered.
     */
    public func kill(): Unit {
        process.terminate(force: true)
        process.wait()
        ()
    }
}

/**
 * The script the server starts through on POSIX: its protocol on fds 3 and 4 (the pipes `std.process` gives
 * as stdin and stdout, the only descriptors it passes), what a macro prints to stderr, never onto the protocol,
 * as cjc arranges it; the runtime's directory set in the script itself, where macOS does not strip it.
 */
const POSIX_LAUNCH = ##"lib="$1"; shift; LD_LIBRARY_PATH="$lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" DYLD_LIBRARY_PATH="$lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" exec "$@" 3<&0 4>&1 0</dev/null 1>&2"##

/**
 * Starts the server of `paths`: serial, watching this process, which it outlives by about 4 s at most.
 *
 * @throws ProcessException - if it cannot be started
 */
@When[os != "Windows"]
public func startMacroServer(paths: MacroServerPaths): MacroServerProcess {
    let process = launch(
        "/bin/sh",
        [
            "-c",
            POSIX_LAUNCH,
            "sh",
            paths.runtimeLib.toString(),
            paths.server.toString(),
            "3",
            "4",
            "0",
            paths.cjc.toString(),
            "${getProcessId()}"
        ],
        stdIn: ProcessRedirect.Pipe,
        stdOut: ProcessRedirect.Pipe,
        stdErr: ProcessRedirect.Inherit
    )
    MacroServerProcess(process, MacroConnection(process.stdOutPipe, process.stdInPipe))
}

/**
 * Windows has no way to pass the server two pipe handles through `std.process` (D87, #86).
 *
 * @throws UnsupportedException - always
 */
@When[os == "Windows"]
public func startMacroServer(_: MacroServerPaths): MacroServerProcess {
    throw UnsupportedException("the macro server is not started on Windows")
}
