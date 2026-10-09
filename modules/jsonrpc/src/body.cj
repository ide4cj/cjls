package jsonrpc

import fjson.*
import stdxx.{IntegerOrString, Nullable, UnexpectedVariantException}
import stdxx.deriving.*

public type RequestId = IntegerOrString

private let JSONRPC = FjName("jsonrpc")
private let ID = FjName("id")
private let RESULT = FjName("result")
private let ERROR = FjName("error")

/** No method's params read in place: they all stay bytes. */
let NO_PARAMS_READER: (String) -> Option<(FjReader) -> Any> = {_ => None}

/**
 * One message. JSON-RPC has no discriminator field, so the shape is the discriminator: `id`,
 * `method`, `result` and `error` present or not decide the variant. It is read in one pass, whatever
 * the order of the keys; the params, a result and an error's data stay unread - `RawJson`, slices of
 * the frame - until whoever knows the method reads them as its types.
 */
public enum Body <: ToJson & FromJson<Body> {
    | Request(RequestBody)
    | Notification(NotificationBody)
    | Response(ResponseBody)

    /**
     * @throws RpcException - if the protocol invariants are not met
     * @throws FjException - if the JSON is not a message's
     */
    public static func fromJson(r: FjReader): Body {
        read(r, NO_PARAMS_READER)[0]
    }

    /**
     * The message, with its params read in place (D73) when `method` came before them and
     * `paramsReader` gives a reader for that method: what the reader returned is the second value.
     * The params stay in the body as their bytes either way. A reader that throws leaves them
     * unread, as if there had been none: whoever reads them next fails the same way, with an id to
     * answer to.
     *
     * @throws RpcException - if the protocol invariants are not met
     * @throws FjException - if the JSON is not a message's
     */
    public static func read(r: FjReader, paramsReader: (String) -> Option<(FjReader) -> Any>): (Body, ?Any) {
        var version: ?String = None
        var id: ?Nullable<RequestId> = None
        var method: ?String = None
        var params: ?RawJson = None
        var decoded: ?Any = None
        var result: ?RawJson = None
        var error: ?ResponseError = None

        r.beginObject()
        while (r.nextKey()) {
            if (r.keyIs("jsonrpc")) {
                version = match (r.peekKind()) {
                    case FjKind.FjString => r.readString()
                    case _ =>
                        r.skipValue()
                        ""
                }
            } else if (r.keyIs("id")) {
                id = Nullable<RequestId>.fromJson(r)
            } else if (r.keyIs("method")) {
                method = r.readString()
            } else if (r.keyIs("params")) {
                let reader = match (method) {
                    case Some(name) => paramsReader(name)
                    case None => Option<(FjReader) -> Any>.None
                }
                match (reader) {
                    case Some(readInPlace) =>
                        let mark = r.mark()
                        try {
                            decoded = readInPlace(r)
                            params = RawJson(r.sliceSince(mark))
                        } catch (_: Exception) {
                            decoded = None
                            r.rewind(mark)
                            params = paramsOf(r)
                        }
                    case None => params = paramsOf(r)
                }
            } else if (r.keyIs("result")) {
                result = RawJson.fromJson(r)
            } else if (r.keyIs("error")) {
                error = ResponseError.fromJson(r)
            } else {
                r.skipValue()
            }
        }

        if (version != Some("2.0")) {
            throw RpcException(ErrorCode.INVALID_REQUEST, "invalid \"jsonrpc\" field value")
        }
        let someId = id ?? return (Notification(
            NotificationBody(method ?? throw missingField("Notification", "method"), params: params)), decoded)
        let body = match ((result, error)) {
            case (Some(_), Some(_)) => throw RpcException(ErrorCode.INVALID_REQUEST,
                "a response carries both \"result\" and \"error\"")
            case (Some(value), None) => Response(ResponseBody(someId, Result(value)))
            case (None, Some(err)) => Response(ResponseBody(someId, ResultOrError.Error(err)))
            case _ =>
                let requestId = match (someId) {
                    case Value(value) => value
                    case Null => throw RpcException(ErrorCode.INVALID_REQUEST, "a request's \"id\" is null")
                }
                Request(RequestBody(requestId, method ?? throw missingField("Request", "method"), params: params))
        }
        (body, decoded)
    }

    public func toJson(w: FjWriter): Unit {
        match (this) {
            case Request(request) => request.toJson(w)
            case Notification(notification) => notification.toJson(w)
            case Response(response) => response.toJson(w)
        }
    }

    /**
     * @throws UnexpectedVariantException - if it is not a `Request`
     */
    public func getRequestBodyOrThrow(): RequestBody {
        if (let Request(reqBody) <- this) {
            return reqBody
        }

        throw UnexpectedVariantException("Request", variantName())
    }

    /**
     * @throws UnexpectedVariantException - if it is not a `Notification`
     */
    public func getNotificationBodyOrThrow(): NotificationBody {
        if (let Notification(noteBody) <- this) {
            return noteBody
        }

        throw UnexpectedVariantException("Notification", variantName())
    }

    /**
     * @throws UnexpectedVariantException - if it is not a `Response`
     */
    public func getResponseBodyOrThrow(): ResponseBody {
        if (let Response(respBody) <- this) {
            return respBody
        }

        throw UnexpectedVariantException("Response", variantName())
    }

    private func variantName(): String {
        match (this) {
            case Request(_) => "Request"
            case Notification(_) => "Notification"
            case Response(_) => "Response"
        }
    }
}

/**
 * JSON-RPC allows only a structured value as the params; `null` reads as none at all.
 */
private func paramsOf(r: FjReader): ?RawJson {
    match (r.peekKind()) {
        case FjKind.FjObject | FjKind.FjArray => RawJson.fromJson(r)
        case FjKind.FjNull =>
            r.readNull()
            None
        case _ => throw RpcException(ErrorCode.INVALID_REQUEST, "\"params\" has to be an array or an object")
    }
}

@DeriveExt[ToJson]
@Serde[tag: "jsonrpc", rename: "2.0", skipNone]
public struct RequestBody {
    public RequestBody(
        public let id: RequestId,
        public let method: String,
        public let params!: ?RawJson = None
    ) {}

    public func enveloped(): Body {
        Request(this)
    }
}

@DeriveExt[ToJson]
@Serde[tag: "jsonrpc", rename: "2.0", skipNone]
public struct NotificationBody {
    public NotificationBody(public let method: String, public let params!: ?RawJson = None) {}

    public func enveloped(): Body {
        Notification(this)
    }
}

public struct ResponseBody <: ToJson {
    /**
     * @param id - `Null` when the request it answers could not be read far enough to have one
     */
    public ResponseBody(public let id: Nullable<RequestId>, public let resultOrError: ResultOrError) {}

    public func enveloped(): Body {
        Response(this)
    }

    public func toJson(w: FjWriter): Unit {
        w.beginObject()
        w.name(JSONRPC)
        w.string("2.0")
        w.name(ID)
        id.toJson(w)
        match (resultOrError) {
            case Result(value) =>
                w.name(RESULT)
                value.toJson(w)
            case Error(err) =>
                w.name(ERROR)
                err.toJson(w)
        }
        w.endObject()
    }
}

public enum ResultOrError {
    | Result(RawJson)
    | Error(ResponseError)

    public func isResult(): Bool {
        if (let Result(_) <- this) {
            return true
        }

        false
    }

    /**
     * @throws UnexpectedVariantException - if it holds an `Error`
     */
    public func getResultOrThrow(): RawJson {
        match (this) {
            case Result(data) => data
            case Error(_) => throw UnexpectedVariantException("Result", "Error")
        }
    }

    /**
     * @throws UnexpectedVariantException - if it holds a `Result`
     */
    public func getErrorOrThrow(): ResponseError {
        match (this) {
            case Error(err) => err
            case Result(_) => throw UnexpectedVariantException("Error", "Result")
        }
    }
}
