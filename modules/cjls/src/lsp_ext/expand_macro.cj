package cjls.lsp_ext

import fjson.*
import stdxx.Nullable
import stdxx.deriving.*
import jsonrpc.*
import cjls.lsp_types.{LspInboundRequest, MessageDirection, TextDocumentPositionParams}

/**
 * `cjls/expandMacro`: what the macro call at a position expands to, as rust-analyzer's
 * `rust-analyzer/expandMacro` answers it (`docs/lsp-extensions.md`).
 */
public struct ExpandMacroRequestSpec <:
    LspInboundRequest<TextDocumentPositionParams, Nullable<MacroExpansion>> {
    public static prop METHOD: String {
        get() {
            "cjls/expandMacro"
        }
    }

    public static prop DIRECTION: MessageDirection {
        get() {
            MessageDirection.ClientToServer
        }
    }

    public prop method: String {
        get() {
            METHOD
        }
    }

    /**
     * @throws RpcException - `INVALID_PARAMS`, if the params do not read as `TextDocumentPositionParams`
     */
    public func decodeParams(params: ?RawJson): TextDocumentPositionParams {
        try {
            (params ?? RawJson.NULL).read<TextDocumentPositionParams>()
        } catch (e: Exception) {
            throw RpcException(ErrorCode.INVALID_PARAMS, e.message)
        }
    }

    /**
     * @throws RpcException - `INVALID_PARAMS`, if the params do not read as `TextDocumentPositionParams`
     */
    public func decodeParams(r: FjReader): TextDocumentPositionParams {
        try {
            TextDocumentPositionParams.fromJson(r)
        } catch (e: Exception) {
            throw RpcException(ErrorCode.INVALID_PARAMS, e.message)
        }
    }

    public func encodeResult(result: Nullable<MacroExpansion>): RawJson {
        RawJson.of(result)
    }
}

/**
 * What a macro call expands to.
 */
@DeriveExt[ToJson, FromJson]
public struct MacroExpansion {
    public MacroExpansion(
        /**
         * The macro's name as the call writes it: `@Derive`, `@m.M`.
         */
        public let name!: String,
        /**
         * The text of the expansion, formatted; one of cjls's own starts with a comment saying so.
         */
        public let expansion!: String,
        /**
         * Who wrote it: `workspace`, the macro server running a macro of the workspace; `cjls`, the server itself for
         * a macro of std, signatures only.
         */
        public let kind!: String
    ) {}
}

/**
 * The command of the code action "Expand macro": its one argument the `TextDocumentPositionParams` of the call, it
 * writes the file with the macro calls expanded under `.cache/cjls/expanded/` and asks the client to show it
 * (`window/showDocument`).
 */
public const EXPAND_MACRO_COMMAND = "cjls.expandMacro"
