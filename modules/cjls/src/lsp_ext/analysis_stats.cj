package cjls.lsp_ext

import fjson.*
import stdxx.deriving.*
import jsonrpc.*
import cjls.lsp_types.{LspInboundRequest, MessageDirection}

/**
 * `cjls/analysisStats`: the work the analysis has done, counted, for a driver to read before and
 * after a request (`docs/lsp-extensions.md`). Takes no params.
 */
public struct AnalysisStatsRequestSpec <: LspInboundRequest<Unit, AnalysisStats> {
    public static prop METHOD: String {
        get() {
            "cjls/analysisStats"
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

    public func decodeParams(params: ?RawJson): Unit {
        ()
    }

    public func decodeParams(r: FjReader): Unit {
        r.skipValue()
    }

    public func encodeResult(result: AnalysisStats): RawJson {
        RawJson.of(result)
    }
}

/**
 * Counts since the server started.
 */
@DeriveExt[ToJson, FromJson]
public struct AnalysisStats {
    public AnalysisStats(
        /**
         * How many times a query was computed rather than taken from what the analysis
         * remembered: its work, the same in every run of the same requests on the same files.
         */
        public let queriesExecuted!: Int64
    ) {}
}
