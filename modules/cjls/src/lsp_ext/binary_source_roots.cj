package cjls.lsp_ext

import cjls.lsp_types.*
import fjson.*
import stdxx.deriving.*

/**
 * The complete replacement of the binary source roots protected by the client.
 */
@DeriveExt[ToJson, FromJson]
protected struct BinarySourceRootsParams {
    public BinarySourceRootsParams(public let roots!: Array<DocumentUri>) {}
}

/**
 * Reports actual source directories without changing their file identities or permissions.
 */
protected struct BinarySourceRootsNotificationSpec <:
    LspOutboundNotification<BinarySourceRootsParams> {
    public static prop METHOD: String {
        get() {
            "cjls/binarySourceRoots"
        }
    }

    public static prop DIRECTION: MessageDirection {
        get() {
            MessageDirection.ServerToClient
        }
    }

    public prop method: String {
        get() {
            METHOD
        }
    }

    public func encodeParams(params: BinarySourceRootsParams): RawJson {
        RawJson.of(params)
    }
}
