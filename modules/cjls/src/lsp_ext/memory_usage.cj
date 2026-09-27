package cjls.lsp_ext

import fjson.*
import stdxx.deriving.*
import jsonrpc.*
import cjls.lsp_types.{LspInboundRequest, MessageDirection}

/**
 * `cjls/memoryUsage`, rust-analyzer's `rust-analyzer/memoryUsage`: what the Cangjie runtime says of
 * its heap and its collections, as numbers rather than a report, so a driver can read them
 * (`docs/lsp-extensions.md`).
 */
public struct MemoryUsageRequestSpec <: LspInboundRequest<MemoryUsageParams, MemoryUsage> {
    public static prop METHOD: String {
        get() {
            "cjls/memoryUsage"
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
     * Absent params read as `{}`.
     *
     * @throws RpcException - `INVALID_PARAMS`, if the params do not read as `MemoryUsageParams`
     */
    public func decodeParams(params: ?RawJson): MemoryUsageParams {
        let raw = params ?? return MemoryUsageParams()
        try {
            raw.read<MemoryUsageParams>()
        } catch (e: Exception) {
            throw RpcException(ErrorCode.INVALID_PARAMS, e.message)
        }
    }

    public func encodeResult(result: MemoryUsage): RawJson {
        RawJson.of(result)
    }
}

@DeriveExt[ToJson, FromJson]
@Serde[skipNone]
public struct MemoryUsageParams {
    public MemoryUsageParams(
        /**
         * A full collection first, waited for, so that `allocatedHeap` is what is held rather than
         * what is held and garbage not collected yet.
         */
        public let collect!: ?Bool = None,
        /**
         * A heap dump written there first (after the collection, if any), for `cjprof heap -i`.
         */
        public let heapDump!: ?String = None
    ) {}
}

/**
 * `std.runtime`'s numbers: sizes in bytes, the collector's time in microseconds, counts since the
 * start.
 */
@DeriveExt[ToJson, FromJson]
public struct MemoryUsage {
    public MemoryUsage(
        /**
         * The heap's regions in use, the objects in them and their free space; what the heap
         * takes of the process's memory.
         */
        public let usedHeap!: Int64,
        /**
         * The objects on the heap, the live and the garbage not collected yet.
         */
        public let allocatedHeap!: Int64,
        public let maxHeap!: Int64,
        public let gcCount!: Int64,
        public let gcTime!: Int64,
        public let gcFreed!: Int64,
        public let threads!: Int64
    ) {}
}
