package jsonrpc

import stdx.log.{LogValue, LogWriter}

/**
 * An `Error` as a log attribute, written as stdx.log writes an `Exception`: its class and
 * message, then a frame per line. stdx.log takes no `Error`, and a stack overflow or running out
 * of memory is a bug to be found from the log alone.
 */
public class ErrorLogValue <: LogValue {
    public ErrorLogValue(private let error: Error) {}

    public func writeTo(w: LogWriter): Unit {
        w.startArray()
        w.writeString(error.toString())
        for (frame in error.getStackTrace()) {
            w.writeString("${frame.declaringClass}.${frame.methodName}(${frame.fileName}:${frame.lineNumber})")
        }
        w.endArray()
    }
}
