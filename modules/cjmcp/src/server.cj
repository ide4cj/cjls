package cjmcp

import std.fs.Path
import stdx.log.{Logger, NoopLogger}
import fjson.*
import loupe.vfs.VfsPath
import stdxx.Nullable

class McpException <: Exception {
    McpException(message: String, let code: Int64) {
        super(message)
    }

    protected override func getClassName(): String {
        "McpException"
    }
}

/**
 * A sequential session: no query can overlap a workspace reload.
 */
class McpServer {
    private var isInitialized = false
    private var isReady = false
    private let sessions = WorkspaceSessions()

    McpServer(private let root: VfsPath, private let logger!: Logger = NoopLogger()) {}

    func close(): Unit {
        sessions.close()
    }

    func handle(line: Array<Byte>): ?ToJson {
        let request =
            try {
                fromJsonBytes<JsonValue>(line)
            } catch (_: Exception) {
                return failure(JsonNull, -32700, "Parse error")
            }
        var id: JsonValue = JsonNull
        var notification = false
        try {
            request.asObject()
            if (request.get("jsonrpc") != Some(JsonString("2.0"))) {
                throw McpException("Invalid JSON-RPC version", -32600)
            }
            let method = request.get("method") ?? throw McpException("Missing method", -32600)
            if (!isString(method)) {
                throw McpException("Method must be a string", -32600)
            }
            if (let Some(value) <- request.get("id")) {
                if (!isValidId(value)) {
                    throw McpException("Request id must be an integer or a string", -32600)
                }
                id = value
            } else {
                notification = true
            }
            let params = request.get("params") ?? JsonObject([])
            if (!isObject(params)) {
                throw McpException("Params must be an object", -32602)
            }
            if (notification) {
                if (method.asString() == "notifications/initialized" && isInitialized) {
                    isReady = true
                }
                return None
            }
            let result = dispatch(method.asString(), params)
            McpResponse(id, result)
        } catch (e: McpException) {
            if (notification) { None } else { failure(id, e.code, e.message) }
        } catch (_: IllegalArgumentException) {
            if (notification) { None } else { failure(id, -32600, "Invalid request") }
        } catch (e: Exception) {
            if (notification) { None } else { failure(id, -32603, e.message) }
        }
    }

    private func dispatch(method: String, params: JsonValue): ToJson {
        if (method == "ping") {
            return McpEmpty()
        }
        if (method == "initialize") {
            return initializeSession(params)
        }
        if (method != "tools/list" && method != "tools/call") {
            throw McpException("Method not found: ${method}", -32601)
        }
        if (!isReady) {
            throw McpException("Initialize the session first", -32600)
        }
        if (method == "tools/list") {
            return McpToolsResult(tools())
        }
        callTool(params)
    }

    private func initializeSession(params: JsonValue): McpInitializeResult {
        if (isInitialized) {
            throw McpException("Already initialized", -32600)
        }
        try {
            params["protocolVersion"].asString()
            params["capabilities"].asObject()
            params["clientInfo"]["name"].asString()
            params["clientInfo"]["version"].asString()
        } catch (_: IllegalArgumentException) {
            throw McpException("Invalid initialize parameters", -32602)
        }
        isInitialized = true
        return McpInitializeResult(
            "2025-11-25",
            McpCapabilities(McpEmpty()),
            serverInfo(),
            agentInstructions
        )
    }

    private func callTool(params: JsonValue): McpToolResult {
        var maxOutputBytes: Int64 = 24000
        var selectedRoot = root.toString()
        let code =
            try {
                if (params["name"].asString() != "runPython") {
                    throw McpException("Unknown tool", -32602)
                }
                let args = params["arguments"]
                for (
                    (name, _) in args.asObject() where name != "code" && name != "maxOutputBytes" &&
                        name != "root"
                ) {
                    throw McpException("Unexpected argument: ${name}", -32602)
                }
                if (let Some(directory) <- args.get("root")) {
                    selectedRoot = directory.asString()
                    if (!Path(selectedRoot).isAbsolute()) {
                        throw McpException("root must be an absolute directory path", -32602)
                    }
                }
                if (let Some(budget) <- args.get("maxOutputBytes")) {
                    maxOutputBytes = budget.asInteger()
                    if (maxOutputBytes < 0) {
                        throw McpException("maxOutputBytes must be nonnegative", -32602)
                    }
                }
                args["code"].asString()
            } catch (e: IllegalArgumentException) {
                throw McpException(e.message, -32602)
            }
        var sessionId = Nullable<String>.Null
        try {
            let entry = sessions.acquire(selectedRoot, logger)
            selectedRoot = entry.root
            sessionId = Nullable<String>.Value(entry.id)
            let result = entry.python.run(code, maxOutputBytes)
            toolResult(result, error: !result["error"].isNull())
        } catch (e: Exception) {
            toolResult(
                McpExecutionFailure(e.message, Nullable<Int64>.Null, selectedRoot, sessionId),
                error: true
            )
        }
    }
}

/**
 * Wrap a Python result as MCP text and structured content.
 */
func toolResult(value: ToJson, error!: Bool): McpToolResult {
    McpToolResult([McpTextContent(String.fromUtf8(toJsonBytes(value)))], value, isError: error)
}

/**
 * Build a JSON-RPC error response with the original request ID.
 */
func failure(id: JsonValue, code: Int64, message: String): McpErrorResponse {
    McpErrorResponse(id, McpError(code, message))
}

/**
 * Describe the runPython tool and its argument schema.
 */
func tools(): Array<McpTool> {
    let properties = McpToolProperties(
        McpStringSchema(
            "Python script. workspace is a live native Cangjie object. result supports JSON data plus WorkspaceDiagnostic, MacroStatus, MacroState, TextRange and Severity values, encoded automatically. stdout and stderr are captured."
        ),
        McpStringSchema(
            "Absolute project/worktree directory. Omit to use --dir; never follows the previous call. Each canonical root has an independent cached session."
        ),
        McpBudgetSchema(
            0,
            24000,
            "Budget for the UTF-8 JSON response (result, stdout, stderr, error, root, sessionId and revision). Default 24000; 0 explicitly allows unlimited output. Excess returns OutputBudgetExceeded after execution, with the full response available as last_output in the next script."
        )
    )
    [
        McpTool(
            "runPython",
            "Query native Cangjie analysis with Python; follow server instructions. Python has process permissions and no hard timeout.",
            McpInputSchema(properties, ["code"], additionalProperties: false),
            McpToolAnnotations(readOnlyHint: false, openWorldHint: true)
        )
    ]
}

/**
 * Whether the JSON value is a string.
 */
func isString(value: JsonValue): Bool {
    match (value) {
        case JsonString(_) => true
        case _ => false
    }
}

/**
 * Whether the JSON value is an object.
 */
func isObject(value: JsonValue): Bool {
    match (value) {
        case JsonObject(_) => true
        case _ => false
    }
}

/**
 * Whether the value is a supported JSON-RPC request ID.
 */
func isValidId(value: JsonValue): Bool {
    match (value) {
        case JsonInteger(_) => true
        case JsonString(_) => true
        case _ => false
    }
}
