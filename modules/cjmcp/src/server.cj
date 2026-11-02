package cjmcp

import fjson.{JsonValue, fromJsonBytes}
import loupe.vfs.VfsPath
import stdx.log.{Logger, NoopLogger}

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
    private var python: ?PythonSession = None

    McpServer(private let root: VfsPath, private let logger!: Logger = NoopLogger()) {}

    func close(): Unit {
        python?.close()
    }

    func handle(line: Array<Byte>): ?JsonValue {
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
            let params = request.get("params") ?? obj([])
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
            obj([("jsonrpc", JsonString("2.0")), ("id", id), ("result", result)])
        } catch (e: McpException) {
            if (notification) { None } else { failure(id, e.code, e.message) }
        } catch (_: IllegalArgumentException) {
            if (notification) { None } else { failure(id, -32600, "Invalid request") }
        } catch (e: Exception) {
            if (notification) { None } else { failure(id, -32603, e.message) }
        }
    }

    private func dispatch(method: String, params: JsonValue): JsonValue {
        if (method == "ping") {
            return obj([])
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
            return obj([("tools", tools())])
        }
        callTool(params)
    }

    private func initializeSession(params: JsonValue): JsonValue {
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
        return obj(
            [
                ("protocolVersion", JsonString("2025-11-25")),
                ("capabilities", obj([("tools", obj([]))])),
                (
                    "serverInfo",
                    obj([("name", JsonString("cjmcp")), ("version", JsonString("0.1.0"))])
                ),
                ("instructions", JsonString(agentInstructions))
            ]
        )
    }

    private func callTool(params: JsonValue): JsonValue {
        let code =
            try {
                if (params["name"].asString() != "runPython") {
                    throw McpException("Unknown tool", -32602)
                }
                let args = params["arguments"]
                for ((name, _) in args.asObject() where name != "code") {
                    throw McpException("Unexpected argument: ${name}", -32602)
                }
                args["code"].asString()
            } catch (e: IllegalArgumentException) {
                throw McpException(e.message, -32602)
            }
        try {
            if (python.isNone()) {
                python = PythonSession(root, logger: logger)
            }
            let result = python
                .getOrThrow { IllegalStateException("Python session was not initialized") }
                .run(code)
            toolResult(result, error: !result["error"].isNull())
        } catch (e: Exception) {
            toolResult(obj([("error", JsonString(e.message)), ("revision", JsonNull)]), error: true)
        }
    }
}

/**
 * Build a JSON object from its named members.
 */
func obj(members: Array<(String, JsonValue)>): JsonValue {
    JsonObject(members)
}

/**
 * Wrap a Python result as MCP text and structured content.
 */
func toolResult(value: JsonValue, error!: Bool): JsonValue {
    obj(
        [
            (
                "content",
                JsonArray(
                    [obj([("type", JsonString("text")), ("text", JsonString(value.toString()))])]
                )
            ),
            ("structuredContent", value),
            ("isError", JsonBool(error))
        ]
    )
}

/**
 * Build a JSON-RPC error response with the original request ID.
 */
func failure(id: JsonValue, code: Int64, message: String): JsonValue {
    obj(
        [
            ("jsonrpc", JsonString("2.0")),
            ("id", id),
            ("error", obj([("code", JsonInteger(code)), ("message", JsonString(message))]))
        ]
    )
}

/**
 * Describe the runPython tool and its argument schema.
 */
func tools(): JsonValue {
    let code = obj(
        [
            ("type", JsonString("string")),
            (
                "description",
                JsonString(
                    "Python script. workspace is a live native Cangjie object; result must be JSON-serializable. stdout and stderr are captured."
                )
            )
        ]
    )
    let schema = obj(
        [
            ("type", JsonString("object")),
            ("properties", obj([("code", code)])),
            ("required", JsonArray([JsonString("code")])),
            ("additionalProperties", JsonBool(false))
        ]
    )
    let tool = obj(
        [
            ("name", JsonString("runPython")),
            (
                "description",
                JsonString(
                    "Query native Cangjie analysis with Python; follow server instructions. Python has process permissions and no hard timeout."
                )
            ),
            ("inputSchema", schema),
            (
                "annotations",
                obj([("readOnlyHint", JsonBool(false)), ("openWorldHint", JsonBool(true))])
            )
        ]
    )
    JsonArray([tool])
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
