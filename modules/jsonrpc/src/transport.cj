package jsonrpc

import std.io.*
import std.sync.{AtomicBool, Mutex}
import stdx.log.*
import fjson.*

public interface JsonRpcReader <: Resource {
    /**
     * @return `None` once the peer hangs up
     */
    func read(): ?Body
}

public interface JsonRpcWriter <: Resource {
    func write(body: Body): Unit
}

public interface JsonRpcTransport <: JsonRpcReader & JsonRpcWriter {}

public class FramedJsonRpcTransport <: JsonRpcTransport {
    public static const BODY_BYTES_MAX: Int64 = 32 * 1024 * 1024
    private static const WRITER_KEPT_MAX: Int64 = 1024 * 1024
    private static const SKIP_CHUNK: Int64 = 64 * 1024

    private let input: BufferedInputStream<InputStream>
    private let output: BufferedOutputStream<OutputStream>
    private let closed = AtomicBool(false)
    // one each, kept from message to message: only the read loop reads, and writes take `writing`
    private let reader = FjReader(Array<Byte>())
    private var writer = FjWriter()
    private let writing = Mutex()

    /**
     * @param bodyBytesMax - the largest content read; one over it is skipped and refused
     */
    public FramedJsonRpcTransport(private let source: InputStream, private let sink: OutputStream,
        private let logger: Logger, private let bodyBytesMax!: Int64 = BODY_BYTES_MAX) {
        this.input = BufferedInputStream(source)
        this.output = BufferedOutputStream(sink)
    }

    public func isClosed(): Bool {
        closed.load()
    }

    public func close(): Unit {
        if (closed.swap(true)) {
            return
        }

        try {
            output.flush()
        } catch (e: Exception) {
            // a close that throws would mask whatever is being torn down alongside it
            logger.warn("flushing the JSON-RPC transport on close failed", [("cause", e)])
        }

        if (let Some(closeableSink) <- (sink as Resource)) {
            closeableSink.close()
        }
        if (let Some(closeableSource) <- (source as Resource)) {
            closeableSource.close()
        }
    }

    /**
     * A closed transport reads as EOF: shutting down is not a framing fault, and a read loop
     * that already ends on `None` needs no second exit. A header cut off by the stream's end
     * is EOF too, as nothing can tell it from one.
     *
     * @throws RpcException - if the frame carries no decodable message, or is over the limit
     * @throws TransportException - if the framing is malformed or truncated
     */
    public func read(): ?Body {
        if (isClosed()) {
            return None
        }
        let header = Header.read(input) ?? return None
        // `InputStream.read` rejects an empty buffer, so it must not reach `readExactly`
        if (header.contentLength == 0) {
            throw RpcException(ErrorCode.PARSE_ERROR, "JSON-RPC frame declares an empty content")
        }
        let count = Int64(header.contentLength)
        if (count > bodyBytesMax) {
            // the length is known, so the stream stays in sync past the content left unread
            skipExactly(count)
            throw RpcException(ErrorCode.INVALID_REQUEST,
                "JSON-RPC body size limit exceeded: expected at most ${bodyBytesMax}, got ${count} bytes")
        }
        let payload = readExactly(count)
        reader.reset(payload)
        try {
            let body = Body.fromJson(reader)
            reader.end()
            body
        } catch (e: FjException) {
            // read in one pass, a message does not say which it failed at: the JSON or the message
            if (!isJson(payload)) {
                throw RpcException(ErrorCode.PARSE_ERROR, "JSON-RPC content is not valid JSON\nCause: ${e.message}")
            }
            throw RpcException(ErrorCode.INVALID_REQUEST, "JSON-RPC content is not a valid message\nCause: ${e.message}")
        }
    }

    /**
     * @throws TransportException - if the transport is closed
     */
    public func write(msg: Body): Unit {
        if (isClosed()) {
            throw TransportException("JSON-RPC transport is closed")
        }
        synchronized(writing) {
            writer.clear()
            msg.toJson(writer)
            let payload = writer.bytes()
            output.write("Content-Length: ${payload.size}\r\n\r\n".toArray())
            output.write(payload)
            output.flush()
            // one outsized answer must not keep its buffer for the lifetime of the connection
            if (payload.size > WRITER_KEPT_MAX) {
                writer = FjWriter()
            }
        }
    }

    private static func isJson(payload: Array<Byte>): Bool {
        try {
            let r = FjReader(payload)
            r.skipValue()
            r.end()
            true
        } catch (_: FjException) {
            false
        }
    }

    /**
     * @throws TransportException - if the stream ends first
     */
    private func readExactly(count: Int64): Array<Byte> {
        let res = Array<Byte>(count, repeat: 0)
        // a `BufferedInputStream` keeps reading until the buffer is full or the stream ends
        let readBytes = input.read(res)

        if (readBytes < count) {
            throw TransportException("JSON-RPC content truncated: expected ${count} bytes, got ${readBytes}")
        }

        res
    }

    /**
     * Reads `count` bytes a chunk at a time, keeping none: the content is over the limit precisely
     * so as not to hold it.
     *
     * @throws TransportException - if the stream ends first
     */
    private func skipExactly(count: Int64): Unit {
        let chunk = Array<Byte>(min(count, SKIP_CHUNK), repeat: 0)
        var skipped = 0
        while (skipped < count) {
            let readBytes = input.read(chunk[..min(count - skipped, chunk.size)])
            if (readBytes == 0) {
                throw TransportException("JSON-RPC content truncated: expected ${count} bytes, got ${skipped}")
            }
            skipped += readBytes
        }
    }
}
