package cjls.server

import std.collection.{ArrayList, HashMap}
import fjson.{FjReader, RawJson}
import loupe.vfs.VfsPath
import cjls.lsp_types.*

/**
 * Every handler of the server, and the state they share:
 *
 * ```cangjie
 * Router()
 *     .withState(ServerState())
 *     .route(InitializeRequestSpec(), handleInitialize)
 *     .route(HoverRequestSpec(), handleHover)
 *     .route(CancelNotificationSpec()) {ctx: Context<CancelParams> => ctx.client.cancel(ctx.params.id)}
 * ```
 *
 * The spec gives the method and the types; a handler takes a context of the params and returns the
 * result, and the compiler holds it to both. `@LspHandler` makes a function of what it needs from
 * the context, params last, into one.
 *
 * The context says how the handler runs. With a `Context` it runs on the read loop itself, in
 * arrival order, with the `ServerState` to itself: it is how the inputs change, and nothing else is
 * read while it runs, so it must not take long. With a `ReadOnlyContext` it runs on a thread of its
 * own against a `ServerSnapshot` taken when its message arrived, so it sees every change before
 * it and none after, and any number run at once.
 */
public class Router {
    var state = ServerState()
    let requests = HashMap<String, RequestRoute>()
    let notifications = HashMap<String, NotificationRoute>()
    var diagnostics: ?(ServerSnapshot, VfsPath) -> Array<Diagnostic> = None

    /**
     * The methods it has a handler for, requests and notifications: what
     * `capabilities()` is checked against (`CapabilitiesTest`), not a way to
     * dispatch.
     */
    public prop methods: Array<String> {
        get() {
            let methods = ArrayList<String>(requests.keys())
            methods.add(all: notifications.keys())
            methods.toArray()
        }
    }

    /**
     * The state the handlers share; a fresh one unless given.
     */
    public func withState(state: ServerState): Router {
        this.state = state
        this
    }

    /**
     * A document's diagnostics, in the client's terms, for the server to push to a client that
     * cannot pull them: after every change of the files, for every open document, from a snapshot
     * (D14). When and on which thread is the server's (S7).
     */
    public func publishDiagnostics(diagnostics: (ServerSnapshot, VfsPath) -> Array<Diagnostic>): Router {
        this.diagnostics = diagnostics
        this
    }

    /**
     * How each method's params are read where they lie in the frame, for the read loop (D73):
     * what `Server.paramsReader` answers from.
     */
    let paramsReaders = HashMap<String, (FjReader) -> Any>()

    /**
     * @throws IllegalArgumentException - if the method already has a handler
     */
    public func route<P, R>(spec: LspInboundRequest<P, R>, handler: (Context<P>) -> R): Router {
        add(requests, spec.method, RequestRoute.Exclusive({
            parts, params, decoded => spec.encodeResult(handler(parts.context(decodedAs<P>(decoded) ?? spec.decodeParams(params))))
        }), inPlace(spec))
    }

    /**
     * @throws IllegalArgumentException - if the method already has a handler
     */
    public func route<P>(spec: LspInboundNotification<P>, handler: (Context<P>) -> Unit): Router {
        add(notifications, spec.method, NotificationRoute.Exclusive({
            parts, params, decoded => handler(parts.context(decodedAs<P>(decoded) ?? spec.decodeParams(params)))
        }), inPlace(spec))
    }

    /**
     * @throws IllegalArgumentException - if the method already has a handler, or is one of the
     * lifecycle's: whatever arrives after it must see the state it leaves
     */
    public func route<P, R>(spec: LspInboundRequest<P, R>, handler: (ReadOnlyContext<P>) -> R): Router {
        refuseLifecycle(spec.method)
        add(requests, spec.method, RequestRoute.ReadOnly({
            parts, params, decoded => spec.encodeResult(handler(parts.context(decodedAs<P>(decoded) ?? spec.decodeParams(params))))
        }), inPlace(spec))
    }

    /**
     * @throws IllegalArgumentException - if the method already has a handler, or is one of the
     * lifecycle's: whatever arrives after it must see the state it leaves
     */
    public func route<P>(spec: LspInboundNotification<P>, handler: (ReadOnlyContext<P>) -> Unit): Router {
        refuseLifecycle(spec.method)
        add(notifications, spec.method, NotificationRoute.ReadOnly({
            parts, params, decoded => handler(parts.context(decodedAs<P>(decoded) ?? spec.decodeParams(params)))
        }), inPlace(spec))
    }

    private func add<T>(routes: HashMap<String, T>, method: String, route: T, inPlace: (FjReader) -> Any): Router {
        if (routes.contains(method)) {
            throw IllegalArgumentException("two handlers for \"${method}\"")
        }
        routes.add(method, route)
        paramsReaders.add(method, inPlace)
        this
    }

    private func inPlace<P, R>(spec: LspInboundRequest<P, R>): (FjReader) -> Any {
        {
            r =>
            let params: Any = spec.decodeParams(r)
            params
        }
    }

    private func inPlace<P>(spec: LspInboundNotification<P>): (FjReader) -> Any {
        {
            r =>
            let params: Any = spec.decodeParams(r)
            params
        }
    }
}

/**
 * The params the read loop decoded in place, as the route's type; `None` when it could not, or
 * they are not of it.
 */
func decodedAs<P>(decoded: ?Any): ?P {
    match (decoded) {
        case Some(value) => value as P
        case None => None
    }
}

/**
 * A route runs on its parts and the message's params: their bytes, and what the read loop
 * decoded of them in place, if it did (D73).
 */
enum RequestRoute {
    | Exclusive((Parts, ?RawJson, ?Any) -> RawJson)
    | ReadOnly((ReadOnlyParts, ?RawJson, ?Any) -> RawJson)
}

enum NotificationRoute {
    | Exclusive((Parts, ?RawJson, ?Any) -> Unit)
    | ReadOnly((ReadOnlyParts, ?RawJson, ?Any) -> Unit)
}

private func refuseLifecycle(method: String): Unit {
    if ([InitializeRequestSpec.METHOD, ShutdownRequestSpec.METHOD, ExitNotificationSpec.METHOD].contains(method)) {
        throw IllegalArgumentException("\"${method}\" cannot be handled with a `ReadOnlyContext`")
    }
}
