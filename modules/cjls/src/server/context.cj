package cjls.server

import stdx.log.Logger
import fjson.RawJson
import jsonrpc.*
import cjls.lsp_types.{LspOutboundNotification, LspOutboundRequest}

/**
 * What a handler that runs on the read loop gets: its params, and the `ServerState` itself, since
 * nothing else runs meanwhile.
 */
public class Context<P> {
    Context(
        public let params: P,
        public let loop: Loop,
        public let client: Client,
        public let cancellation: CancellationToken,
        public let logger: Logger
    ) {}

    public prop state: ServerState {
        get() {
            loop.state
        }
    }
}

/**
 * What a handler that runs on a thread of its own gets: as `Context`, with a snapshot in place of
 * the state, so such a handler cannot change the inputs.
 */
public class ReadOnlyContext<P> {
    ReadOnlyContext(
        public let params: P,
        public let snapshot: ServerSnapshot,
        public let client: Client,
        public let cancellation: CancellationToken,
        public let logger: Logger
    ) {}
}

/**
 * A type a `@LspHandler` function can take before its params.
 */
public interface FromContext<T> {
    static func from<P>(ctx: Context<P>): T
}

/**
 * A type a `@LspHandler[readonly]` function can take before its params.
 */
public interface FromReadOnlyContext<T> {
    static func from<P>(ctx: ReadOnlyContext<P>): T
}

/**
 * A context but for its params, which the route decodes, knowing their type.
 */
class Parts {
    Parts(let loop: Loop, let client: Client, let cancellation: CancellationToken, let logger: Logger) {}

    func context<P>(params: P): Context<P> {
        Context(params, loop, client, cancellation, logger)
    }
}

class ReadOnlyParts {
    ReadOnlyParts(let snapshot: ServerSnapshot, let client: Client, let cancellation: CancellationToken,
        let logger: Logger) {}

    func context<P>(params: P): ReadOnlyContext<P> {
        ReadOnlyContext(params, snapshot, client, cancellation, logger)
    }
}

/**
 * Never cancelled for a notification.
 */
extend CancellationToken <: FromContext<CancellationToken> & FromReadOnlyContext<CancellationToken> {
    public static func from<P>(ctx: Context<P>): CancellationToken {
        ctx.cancellation
    }

    public static func from<P>(ctx: ReadOnlyContext<P>): CancellationToken {
        ctx.cancellation
    }
}

/**
 * Carries the method, and the id of a request, on every line it writes.
 */
extend Logger <: FromContext<Logger> & FromReadOnlyContext<Logger> {
    public static func from<P>(ctx: Context<P>): Logger {
        ctx.logger
    }

    public static func from<P>(ctx: ReadOnlyContext<P>): Logger {
        ctx.logger
    }
}

/**
 * The client, as the server talks to it. Bound to its connection once that exists: the connection
 * needs the server, and the server hands this out.
 */
public class Client <: FromContext<Client> & FromReadOnlyContext<Client> {
    private var connection: ?Connection = None

    public static func from<P>(ctx: Context<P>): Client {
        ctx.client
    }

    public static func from<P>(ctx: ReadOnlyContext<P>): Client {
        ctx.client
    }

    /**
     * @throws IllegalStateException - if the client is already connected
     */
    protected func connect(connection: Connection): Unit {
        if (this.connection.isSome()) {
            throw IllegalStateException("the client is already connected")
        }
        this.connection = connection
    }

    /**
     * Sends the notification `spec` names, as `route` takes the ones the client sends: the method
     * and the type of the params come with it.
     *
     * @throws IllegalStateException - if the client is not connected yet
     * @throws RpcException - if params are not serialized to array|object|null
     * @throws TransportException - if the frame cannot be written
     */
    public func notify<P>(spec: LspOutboundNotification<P>, params: P): Unit {
        connected().notify(spec.method, spec.encodeParams(params))
    }

    /**
     * Sends the request `spec` names; its answer is read as the result `spec` names.
     *
     * @note never await the answer from a handler given a `Context`: it can only arrive through the
     * read loop that handler is holding
     *
     * @throws IllegalStateException - if the client is not connected yet
     * @throws RpcException - if params are not serialized to array|object|null
     * @throws TransportException - if the frame cannot be written
     */
    public func request<P, R>(spec: LspOutboundRequest<P, R>, params: P): PendingAnswer<R> {
        let pending = connected().request<RawJson, RawJson>(spec.method, spec.encodeParams(params))
        PendingAnswer<R>(pending, {result => spec.decodeResult(result)})
    }

    /**
     * Sends the request `spec` names, one whose answer is only a success, and waits for that on a
     * thread of its own, so any handler may call it: a failure is a `WARN` of `logger`, and a
     * `DEBUG` once the connection is closed, as nothing sent then reaches the client.
     */
    public func request<P>(spec: LspOutboundRequest<P, Unit>, params: P, logger: Logger): Unit {
        let method = spec.method
        let answer = try {
            request(spec, params)
        } catch (e: Exception) {
            requestFailed(method, e, logger)
            return
        }
        spawn {
            try {
                answer.await()
            } catch (e: Exception) {
                requestFailed(method, e, logger)
            } catch (e: Error) {
                logger.error("request failed", [("request", method), ("cause", ErrorLogValue(e))])
            }
        }
    }

    private func requestFailed(method: String, e: Exception, logger: Logger): Unit {
        if (isClosed()) {
            logger.debug("request dropped", [("request", method), ("reason", "the connection is closed")])
        } else {
            logger.warn("request failed", [("request", method), ("error", e.message)])
        }
    }

    /**
     * Tells the handler of an inbound request to give up.
     */
    public func cancel(id: RequestId): Unit {
        connection?.cancel(id)
    }

    public func close(): Unit {
        connection?.close()
    }

    /**
     * Whether the connection is closed: nothing sent now reaches the client. `false` before it connects.
     */
    public func isClosed(): Bool {
        connection?.isClosed() ?? false
    }

    private func connected(): Connection {
        connection.getOrThrow {=> IllegalStateException("the client is not connected yet")}
    }
}

/**
 * The answer to a request sent to the client, read as the result its spec names. Single-use: the
 * first `await()` takes the answer, and the connection forgets the id once it is delivered, so a
 * second `await()` would wait for an answer that never comes (as `PendingRequest.await`, which it
 * forwards to).
 */
public struct PendingAnswer<R> {
    PendingAnswer(private let pending: PendingRequest<RawJson>, private let decode: (RawJson) -> R) {}

    public prop id: RequestId {
        get() {
            pending.id
        }
    }

    /**
     * Blocks the caller's own thread; never a handler's given a `Context` (see `Client.request`).
     *
     * @throws RpcException - if the client answered with an error, or the connection closed first
     * @throws FjException - if the result does not read as an `R`
     */
    public func await(): R {
        decode(pending.await())
    }
}
