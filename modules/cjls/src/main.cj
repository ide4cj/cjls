package cjls

import std.argopt.ArgumentParseException
import std.env.{getStdErr, getStdOut}
import std.runtime.getMaxHeapSize
import stdx.log.Logger
import jsonrpc.{ErrorLogValue, FramedJsonRpcTransport}
import cjls.server.serve
import cjls.handlers.router

main(args: Array<String>): Int64 {
    let logger = stderrLogger()
    let command = try {
        parseCommand(args)
    } catch (e: ArgumentParseException) {
        getStdErr().write("cjls: ${e.message}\n${USAGE}")
        return 2
    }
    try {
        match (command) {
            case Serve => runServer(logger)
            case PrintProject(dir) => printProject(dir, logger)
            case Help =>
                getStdOut().write(USAGE)
                0
        }
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
    let exitCode = serve(FramedJsonRpcTransport(StdinStream(), getStdOut(), logger), router(), logger)
    logger.info("stopped", [("exitCode", exitCode)])
    exitCode
}
