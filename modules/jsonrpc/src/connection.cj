package jsonrpc

import std.collection.ArrayList
import std.collection.concurrent.*
import std.sync.*
import stdx.log.*
import fjson.*

public class Connection <: Resource {
    private let locker = Mutex()
    private let nextId = AtomicInt32(0)
    private let pending = ConcurrentHashMap<RequestId, LinkedBlockingQueue<ResultOrError>>()
    private let inflight = ConcurrentHashMap<RequestId, CancellationToken>()

    public Connection(private let transport: JsonRpcTransport, private let handler: Handler, private let logger: Logger) {}

    /**
     * @throws RpcException - if params are not serialized to array|object|null
     * @throws TransportException - if the frame cannot be written
     */
    public func notify<P>(method: String, params: P): Unit where P <: ToJson {
        send(NotificationBody(method, params: serializeParams(params)).enveloped())
    }

    /**
     * @throws RpcException - if params are not serialized to array|object|null
     * @throws TransportException - if the frame cannot be written
     */
    public func request<P, R>(method: String, params: P): PendingRequest<R> where P <: ToJson,
        R <: FromJson<R> {
        let id = Integer(nextId.fetchAdd(1))
        let slot = LinkedBlockingQueue<ResultOrError>(1)
        pending.add(id, slot)
        try {
            send(RequestBody(id, method, params: serializeParams(params)).enveloped())
        } catch (e: Exception) {
            // nothing will ever answer an id that never reached the wire
            forget(id)
            throw e
        }

        PendingRequest<R>(id, slot, {=> forget(id)})
    }

    public func cancel(id: RequestId): Unit {
        if (let Some(tok) <- inflight.get(id)) {
            tok.cancel()
        }
    }

    public func isClosed(): Bool {
        transport.isClosed()
    }

    public func close(): Unit {
        try {
            transport.close()
        } finally {
            cancelInflight()
            abandonPending()
        }
    }

    /**
     * Reads until the peer hangs up or the connection is closed. Undecodable frames are answered
     * and skipped. However it ends, the connection is closed as `close` does: no caller is left
     * waiting on an answer that cannot arrive, and no handler working on one nobody will read.
     *
     * @throws TransportException - if the framing is lost in either direction
     */
    public func serve(): Unit {
        let paramsReader = {method: String => handler.paramsReader(method)}
        try {
            while (true) {
                let (body, decodedParams) = try {
                    transport.read(paramsReader) ?? break
                } catch (e: RpcException) {
                    // the frame never got far enough to have an id
                    send(ResponseBody(Null, ResultOrError.Error(e.responseError)).enveloped())
                    continue
                } catch (e: Exception) {
                    // a `close` racing a blocked read pulls the stream out from under
                    // it; that is the shutdown itself, not a fault to report
                    if (isClosed()) {
                        break
                    }
                    throw e
                }

                match (body) {
                    case Request(req) => dispatchRequest(req, decodedParams)
                    case Notification(note) => dispatchNotification(note, decodedParams)
                    case Response(resp) => complete(resp)
                }
            }
        } finally {
            close()
        }
    }

    /**
     * Hands the request over on the read loop itself, so requests and notifications reach the
     * handler in the order they arrived.
     *
     * @throws TransportException - if the frame cannot be written
     */
    private func dispatchRequest(req: RequestBody, decodedParams: ?Any): Unit {
        let cancellation = CancellationToken()
        if (inflight.addIfAbsent(req.id, cancellation).isSome()) {
            // the id is taken, so a response carrying it would be ambiguous
            let refusal = ResponseError(ErrorCode.INVALID_REQUEST, "request id ${req.id} is already in flight")
            send(ResponseBody(Value(req.id), ResultOrError.Error(refusal)).enveloped())
            return
        }
        if (isClosed()) {
            // a `close` from another thread may have cancelled the others before this one was in
            cancellation.cancel()
        }

        let request = InboundRequest(req.id, req.method, req.params, cancellation, {
            resultOrError => answer(req, resultOrError)
        }, decodedParams: decodedParams)
        try {
            handler.onRequest(request)
        } catch (e: Exception) {
            // a no-op when the handler answered before it threw
            request.respond(ResultOrError.Error(responseErrorOf(e)))
        } catch (e: Error) {
            // a bug, and a stack overflow the next request may well not repeat: read on
            logger.error("serve request \"${req.method}\" failed", [("cause", ErrorLogValue(e))])
            request.respond(ResultOrError.Error(responseErrorOf(e)))
        }
    }

    /**
     * Never throws: the thread answering may be a handler's own `spawn`, with nobody above it
     * to catch.
     */
    private func answer(req: RequestBody, resultOrError: ResultOrError): Unit {
        inflight.remove(req.id)
        try {
            send(ResponseBody(Value(req.id), resultOrError).enveloped())
        } catch (e: Exception) {
            if (isClosed()) {
                logger.debug("dropped the answer to \"${req.method}\" - the connection is closed")
                return
            }
            logger.error("answer to \"${req.method}\" failed", [("cause", e)])
        } catch (e: Error) {
            logger.error("answer to \"${req.method}\" failed", [("cause", ErrorLogValue(e))])
        }
    }

    private func dispatchNotification(note: NotificationBody, decodedParams: ?Any): Unit {
        try {
            handler.onNotification(note.method, note.params, decodedParams)
        } catch (e: Exception) {
            // nobody waits on a notification's outcome, so there is no one else to tell
            logger.error("serve notification \"${note.method}\" failed", [("cause", e)])
        } catch (e: Error) {
            logger.error("serve notification \"${note.method}\" failed", [("cause", ErrorLogValue(e))])
        }
    }

    private func complete(resp: ResponseBody): Unit {
        let id = match (resp.id) {
            case Value(id) => id
            case Null =>
                // the peer could not tell which of our frames it was rejecting
                logger.error("peer rejected an unidentifiable message", [("cause", describe(resp.resultOrError))])
                return
        }

        match (pending.remove(id)) {
            case Some(slot) => slot.add(resp.resultOrError)
            case None => logger.warn("dropped a response for an unknown request id ${id}")
        }
    }

    /**
     * Stops correlating an outbound id, so whatever answers it later is dropped.
     */
    private func forget(id: RequestId): Unit {
        pending.remove(id)
    }

    /**
     * Cancels and forgets every inbound request, answered or not: a handler that never answers
     * would otherwise keep its id for the lifetime of the process.
     */
    private func cancelInflight(): Unit {
        let ids = ArrayList<RequestId>()
        for ((id, _) in inflight) {
            ids.add(id)
        }

        for (id in ids) {
            inflight.remove(id)?.cancel()
        }
    }

    private func abandonPending(): Unit {
        let ids = ArrayList<RequestId>()
        for ((id, _) in pending) {
            ids.add(id)
        }

        for (id in ids) {
            if (let Some(slot) <- pending.remove(id)) {
                slot.add(
                    ResultOrError.Error(
                        ResponseError(ErrorCode.INTERNAL_ERROR, "the connection ended before the peer answered")))
            }
        }
    }

    /**
     * @throws TransportException - if the frame cannot be written
     */
    private func send(body: Body): Unit {
        synchronized(locker) {
            transport.write(body)
        }
    }

    /**
     * @throws RpcException - if params are not serialized to array|object|null
     */
    private func serializeParams<P>(params: P): ?RawJson where P <: ToJson {
        let written = RawJson.of(params)
        match (written.bytes[0]) {
            // `{` or `[`
            case 0x7B | 0x5B => written
            // `null`
            case 0x6E => None
            case _ => throw RpcException(ErrorCode.INVALID_PARAMS, "invalid params type", data: written)
        }
    }

    private func describe(resultOrError: ResultOrError): String {
        match (resultOrError) {
            case Error(err) => "${err.code}: ${err.message}"
            case Result(_) => "no error given"
        }
    }
}
