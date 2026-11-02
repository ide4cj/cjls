package cjls

import std.env.getStdOut
import std.runtime.getMaxHeapSize
import stdx.log.Logger
import jsonrpc.{ErrorLogValue, FramedJsonRpcTransport}
import platform.{StdinStream, useBinaryStdio}
import cjls.server.{serve, ServerState}
import cjls.macro_host.MacroHost
import cjls.handlers.router

main(args: Array<String>): Int64 {
    let logger = stderrLogger()
    try {
        APP.run(args, context: CommandContext(logger))
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
