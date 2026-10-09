package jsonrpc

import fjson.{FjReader, RawJson}

/**
 * Both callbacks run on the read loop, one at a time, in arrival order, and nothing further
 * is read until a callback returns. Slow work belongs on a thread of the handler's own: for a
 * request, carry the `InboundRequest` there and answer from it.
 *
 * @note never wait on an outbound `PendingRequest` from inside a callback: its answer can only
 * arrive through the read loop the callback is holding up.
 */
public interface Handler {
    /**
     * The handler owes the request one answer, now or later. A throw before it answered is
     * answered for it, as `responseErrorOf` maps it.
     */
    func onRequest(request: InboundRequest): Unit

    /**
     * @param params - unread: the method says their type
     */
    func onNotification(method: String, params: ?RawJson): Unit

    /**
     * The notification with its params as `paramsReader`'s reader for the method read them in
     * place, when the read loop could; `None` otherwise, and the handler reads `params` itself.
     */
    func onNotification(method: String, params: ?RawJson, decodedParams: ?Any): Unit {
        onNotification(method, params)
    }

    /**
     * How the params of `method` are read where they lie in the frame (D70): the read loop calls
     * the reader at the `params` key, when `method` came before it, with the reader on the value.
     * It reads exactly that one value; what it returns reaches the handler as the message's
     * `decodedParams`. A throw leaves the params their bytes, for the handler to read and fail the
     * same way with an id to answer to. `None`: the params stay bytes.
     */
    func paramsReader(method: String): Option<(FjReader) -> Any> {
        None
    }
}
