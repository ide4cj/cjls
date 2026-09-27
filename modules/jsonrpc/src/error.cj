package jsonrpc

import std.deriving.*
import fjson.*
import stdxx.deriving.*

@DeriveExt[ToJson, FromJson]
@Serde[skipNone]
public struct ResponseError {
    /**
     * @param data - as it came, unread: only whoever knows the method knows its type
     */
    public ResponseError(public let code: ErrorCode, public let message: String, public let data!: ?RawJson = None) {}
}

/**
 * Open rather than an enum, so a code this side does not know survives a round trip.
 */
@DeriveExt[ToJson, FromJson]
@Serde[transparent]
@Derive[Equatable]
public struct ErrorCode <: ToString {
    public const ErrorCode(public let value: Int32) {}

    public static const PARSE_ERROR: ErrorCode = ErrorCode(-32700)
    public static const INVALID_REQUEST: ErrorCode = ErrorCode(-32600)
    public static const METHOD_NOT_FOUND: ErrorCode = ErrorCode(-32601)
    public static const INVALID_PARAMS: ErrorCode = ErrorCode(-32602)
    public static const INTERNAL_ERROR: ErrorCode = ErrorCode(-32603)

    public func toString(): String {
        value.toString()
    }
}
