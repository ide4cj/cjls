package cjmcp

import fjson.*
import stdxx.Nullable
import stdxx.deriving.*

@DeriveExt[ToJson]
@Serde[skipNone]
struct McpEmpty {
    // Derivation requires an explicit primary constructor even for an empty object.
    McpEmpty() {}
}

@DeriveExt[ToJson]
@Serde[tag: "jsonrpc", rename: "2.0", skipNone]
struct McpResponse {
    McpResponse(let id: JsonValue, let result: ToJson) {}
}

@DeriveExt[ToJson]
@Serde[tag: "jsonrpc", rename: "2.0", skipNone]
struct McpErrorResponse {
    McpErrorResponse(let id: JsonValue, let error: McpError) {}
}

@DeriveExt[ToJson]
@Serde[skipNone]
struct McpError {
    McpError(let code: Int64, let message: String) {}
}

@DeriveExt[ToJson]
@Serde[skipNone]
struct McpInitializeResult {
    McpInitializeResult(
        let protocolVersion: String,
        let capabilities: McpCapabilities,
        let serverInfo: McpServerInfo,
        let instructions: String
    ) {}
}

@DeriveExt[ToJson]
@Serde[skipNone]
struct McpCapabilities {
    McpCapabilities(let tools: McpEmpty) {}
}

@DeriveExt[ToJson]
@Serde[skipNone]
struct McpToolResult {
    McpToolResult(
        let content: Array<McpTextContent>,
        let structuredContent: ToJson,
        let isError!: Bool
    ) {}
}

@DeriveExt[ToJson]
@Serde[tag: "type", rename: "text", skipNone]
struct McpTextContent {
    McpTextContent(let text: String) {}
}

/**
 * These fields remain explicit nulls when failure precedes workspace acquisition.
 */
@DeriveExt[ToJson]
@Serde[skipNone]
struct McpExecutionFailure {
    McpExecutionFailure(
        let error: String,
        let revision: Nullable<Int64>,
        let root: String,
        let sessionId: Nullable<String>
    ) {}
}

@DeriveExt[ToJson]
@Serde[skipNone]
struct McpToolsResult {
    McpToolsResult(let tools: Array<McpTool>) {}
}

@DeriveExt[ToJson]
@Serde[skipNone]
struct McpTool {
    McpTool(
        let name: String,
        let description: String,
        let inputSchema: McpInputSchema,
        let annotations: McpToolAnnotations
    ) {}
}

@DeriveExt[ToJson]
@Serde[tag: "type", rename: "object", skipNone]
struct McpInputSchema {
    McpInputSchema(
        let properties: McpToolProperties,
        let required: Array<String>,
        let additionalProperties!: Bool
    ) {}
}

@DeriveExt[ToJson]
@Serde[skipNone]
struct McpToolProperties {
    McpToolProperties(
        let code: McpStringSchema,
        let root: McpStringSchema,
        let maxOutputBytes: McpBudgetSchema
    ) {}
}

@DeriveExt[ToJson]
@Serde[tag: "type", rename: "string", skipNone]
struct McpStringSchema {
    McpStringSchema(let description: String) {}
}

@DeriveExt[ToJson]
@Serde[tag: "type", rename: "integer", skipNone]
struct McpBudgetSchema {
    McpBudgetSchema(let minimum: Int64, let `default`: Int64, let description: String) {}
}

@DeriveExt[ToJson]
@Serde[skipNone]
struct McpToolAnnotations {
    McpToolAnnotations(let readOnlyHint!: Bool, let openWorldHint!: Bool) {}
}

@DeriveExt[ToJson]
@Serde[skipNone]
struct McpServerInfo {
    McpServerInfo(
        let name: String,
        let version: String,
        @Serde[rename: "_meta"]
        let meta: McpServerMeta
    ) {}
}

@DeriveExt[ToJson]
@Serde[skipNone]
struct McpServerMeta {
    McpServerMeta(
        let apiVersion: Int64,
        let commit: Nullable<String>,
        let dirty: Nullable<Bool>,
        let features: Array<String>
    ) {}
}
