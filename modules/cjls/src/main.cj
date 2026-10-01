package cjls

import std.env.getStdOut
import std.runtime.getMaxHeapSize
import jsonrpc.FramedJsonRpcTransport
import cjls.server.serve
import cjls.handlers.router

main(): Int64 {
    let logger = stderrLogger()
    if (let Some(exitCode) <- relaunchWithLargerHeap(logger)) {
        return exitCode
    }
    try {
        useBinaryStdio()
        logger.info("started", [("heap", getMaxHeapSize())])
        // stdout is the wire: nothing else may write to it
        let exitCode = serve(FramedJsonRpcTransport(StdinStream(), getStdOut(), logger), router(), logger)
        logger.info("stopped", [("exitCode", exitCode)])
        exitCode
    } catch (e: Exception) {
        logger.fatal("stopped", [("cause", e)])
        1
    }
}
