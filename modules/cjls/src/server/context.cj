package cjls.server

import stdx.log.Logger
import fjson.{FromJson, RawJson, ToJson}
import jsonrpc.*
import cjls.lsp_types.{LspOutboundNotification, LspOutboundRequest}

/**
 * What a handler that runs on the read loop gets: its params, and the `ServerState` itself, since
 * nothing else runs meanwhile.
 */
public class Context<P> {
    Context(
        public let params: P,
        public let state: ServerState,
        public let client: Client,
        public let cancellation: CancellationToken,
        public let logger: Logger
    ) {}
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
    Parts(let state: ServerState, let client: Client, let cancellation: CancellationToken, let logger: Logger) {}

    func context<P>(params: P): Context<P> {
        Context(params, state, client, cancellation, logger)
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
    public func notify<P>(spec: LspOutboundNotification<P>, params: P): Unit where P <: ToJson {
        connected().notify(spec.method, params)
    }

    /**
     * @note never await the answer from a handler given a `Context`: it can only arrive through the
     * read loop that handler is holding
     *
     * @throws IllegalStateException - if the client is not connected yet
     * @throws RpcException - if params are not serialized to array|object|null
     * @throws TransportException - if the frame cannot be written
     */
    public func request<P, R>(method: String, params: P): PendingRequest<R> where P <: ToJson,
        R <: FromJson<R> {
        connected().request<P, R>(method, params)
    }

    /**
     * Sends the request `spec` names, one whose answer is only a success, and waits for that on a
     * thread of its own, so any handler may call it: a failure is a `WARN` of `logger`, and a
     * `DEBUG` once the connection is closed, as nothing sent then reaches the client.
     */
    public func request<P>(spec: LspOutboundRequest<P, Unit>, params: P, logger: Logger): Unit where P <: ToJson {
        let method = spec.method
        let pending = try {
            connected().request<P, RawJson>(method, params)
        } catch (e: Exception) {
            requestFailed(method, e, logger)
            return
        }
        spawn {
            try {
                pending.await()
            } catch (e: Exception) {
                requestFailed(method, e, logger)
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
