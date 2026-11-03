package cjls

import std.env.{getStdErr, getStdOut}
import std.io.OutputStream
import std.runtime.getMaxHeapSize
import stdx.log.Logger
import jsonrpc.{ErrorLogValue, FramedJsonRpcTransport}
import platform.{StdinStream, useBinaryStdio}
import cjls.handlers.router
import cjls.macro_host.MacroHost
import cjls.server.{ServerState, serve}

main(args: Array<String>): Int64 {
    runCommand(args)
}

/**
 * Runs the registered CLI, logging uncaught exceptions and errors before returning 1.
 */
func runCommand(
    args: Array<String>,
    out!: OutputStream = getStdOut(),
    err!: OutputStream = getStdErr(),
    logger!: Logger = stderrLogger()
): Int64 {
    try {
        CJLS_APP.run(
            args,
            context: CommandContext(logger, output: CommandOutput(out, err)),
            stdout: out,
            stderr: err
        )
    } catch (e: Exception) {
        logger.fatal("stopped", [("cause", e)])
        1
    } catch (e: Error) {
        logger.fatal("stopped", [("cause", ErrorLogValue(e))])
        1
    }
}

/**
 * Serves LSP over stdio until the client says `exit`, on a larger heap.
 *
 * @return the exit code
 */
func runServer(logger: Logger): Int64 {
    if (let Some(exitCode) <- relaunchWithLargerHeap(logger)) {
        return exitCode
    }
    useBinaryStdio()
    logger.info("started", [("heap", getMaxHeapSize())])
    // stdout is the wire: nothing else may write to it
    let state = ServerState()
    state.startsMacros =
        {
            loop, logger =>
            let host = MacroHost(loop, logger)
            host.start()
            host
        }
    let exitCode = serve(
        FramedJsonRpcTransport(StdinStream(), getStdOut(), logger),
        router().withState(state),
        logger
    )
    logger.info("stopped", [("exitCode", exitCode)])
    exitCode
}
