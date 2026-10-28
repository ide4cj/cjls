package cjmcp

import fjson.*
import loupe.vfs.VfsPath

class McpException <: Exception {
    McpException(message: String, let code: Int64) {
        super(message)
    }

    protected override func getClassName(): String {
        "McpException"
    }
}

/** A sequential session: no query can overlap a workspace reload. */
class McpServer {
    private var isInitialized = false
    private var isReady = false
    private var python: ?PythonSession = None

    McpServer(private let root: VfsPath) {}

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
                (
                    "instructions",
                    JsonString(
                        "Use runPython to explore a live Cangjie workspace with native analysis objects. workspace.files(), structure(path), diagnostics(path), hover(path, offset), definition(path, offset), reload(); workspace.problems reports loading problems. Assign JSON-serializable output to result or print it. Ranges are UTF-8 bytes, end exclusive. SDK macros are not expanded. Python executes trusted local code without a sandbox or hard timeout."
                    )
                )
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
                python = PythonSession(root)
            }
            let result = python.getOrThrow().run(code)
            toolResult(result, error: !result["error"].isNull())
        } catch (e: Exception) {
            toolResult(obj([("error", JsonString(e.message))]), error: true)
        }
    }
}

func obj(members: Array<(String, JsonValue)>): JsonValue {
    JsonObject(members)
}

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

func failure(id: JsonValue, code: Int64, message: String): JsonValue {
    obj(
        [
            ("jsonrpc", JsonString("2.0")),
            ("id", id),
            ("error", obj([("code", JsonInteger(code)), ("message", JsonString(message))]))
        ]
    )
}

func tools(): JsonValue {
    let code =
        obj(
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
    let schema =
        obj(
            [
                ("type", JsonString("object")),
                ("properties", obj([("code", code)])),
                ("required", JsonArray([JsonString("code")])),
                ("additionalProperties", JsonBool(false))
            ]
        )
    let tool =
        obj(
            [
                ("name", JsonString("runPython")),
                (
                    "description",
                    JsonString(
                        "Run Python over native loupe objects in an embedded CPython interpreter. workspace.structure(path) returns StructureNode objects, diagnostics(path) Diagnostic objects, hover(path, offset) HoverResult or None. Iterate, filter and aggregate in Python and assign result. workspace.files() lists paths; workspace.reload() refreshes disk state. Imports and local I/O are available."
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

func isString(value: JsonValue): Bool {
    match (value) {
        case JsonString(_) => true
        case _ => false
    }
}

func isObject(value: JsonValue): Bool {
    match (value) {
        case JsonObject(_) => true
        case _ => false
    }
}

func isValidId(value: JsonValue): Bool {
    match (value) {
        case JsonInteger(_) => true
        case JsonString(_) => true
        case _ => false
    }
}
