package cjmcp

import std.collection.ArrayList
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
    private var workspace: ?Workspace = None

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
                        "Cangjie analysis of disk files. Call workspace first; inspect its problems. Ranges and offsets are zero-based UTF-8 bytes, end exclusive. Reload after disk edits. SDK macro expansion is not enabled."
                    )
                )
            ]
        )
    }

    private func callTool(params: JsonValue): JsonValue {
        let name =
            try {
                params["name"].asString()
            } catch (_: IllegalArgumentException) {
                throw McpException("Tool name must be a string", -32602)
            }
        if (
            ![
                "workspace",
                "reload_workspace",
                "diagnostics",
                "file_structure",
                "hover",
                "definition"
            ]
                .contains(name)
        ) {
            throw McpException("Unknown tool: ${name}", -32602)
        }
        let args = params.get("arguments") ?? obj([])
        validateArguments(name, args)
        try {
            if (name == "reload_workspace" || workspace.isNone()) {
                // Publish only a completed load, so a failed reload leaves the previous revision usable.
                workspace = Workspace(root)
            }
            let current = workspace.getOrThrow()
            let result =
                if (name == "workspace" || name == "reload_workspace") {
                    current.status()
                } else {
                    current.query(name, args)
                }
            toolResult(result, error: false)
        } catch (e: Exception) {
            toolResult(obj([("error", JsonString(e.message))]), error: true)
        }
    }
}

func validateArguments(name: String, args: JsonValue): Unit {
    try {
        let members = args.asObject()
        let file = name != "workspace" && name != "reload_workspace"
        let position = name == "hover" || name == "definition"
        for ((key, _) in members) {
            if (!(file && key == "path") && !(position && key == "offset")) {
                throw IllegalArgumentException("unexpected argument: ${key}")
            }
        }
        if (file) {
            args["path"].asString()
        }
        if (position && args["offset"].asInteger() < 0) {
            throw IllegalArgumentException("offset must be nonnegative")
        }
    } catch (e: IllegalArgumentException) {
        throw McpException(e.message, -32602)
    }
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
    JsonArray(
        [
            tool(
                "workspace",
                "Load the Cangjie workspace; list files and loading problems.",
                file: false,
                position: false
            ),
            tool(
                "reload_workspace",
                "Reload project metadata and all source files after disk changes.",
                file: false,
                position: false
            ),
            tool(
                "diagnostics",
                "Get syntax and semantic diagnostics for a loaded file.",
                file: true,
                position: false
            ),
            tool(
                "file_structure",
                "Get the nested declaration outline of a loaded file.",
                file: true,
                position: false
            ),
            tool(
                "hover",
                "Get declaration, inferred type and documentation at a UTF-8 byte offset.",
                file: true,
                position: true
            ),
            tool(
                "definition",
                "Find declaration paths and ranges at a UTF-8 byte offset.",
                file: true,
                position: true
            )
        ]
    )
}

func tool(name: String, description: String, file!: Bool, position!: Bool): JsonValue {
    let props = ArrayList<(String, JsonValue)>()
    let required = ArrayList<JsonValue>()
    if (file) {
        let path =
            obj(
                [
                    ("type", JsonString("string")),
                    (
                        "description",
                        JsonString("Absolute path or path relative to the workspace root.")
                    )
                ]
            )
        props.add(("path", path))
        required.add(JsonString("path"))
    }
    if (position) {
        let offset =
            obj(
                [
                    ("type", JsonString("integer")),
                    ("minimum", JsonInteger(0)),
                    ("description", JsonString("Zero-based UTF-8 byte offset."))
                ]
            )
        props.add(("offset", offset))
        required.add(JsonString("offset"))
    }
    let schema =
        obj(
            [
                ("type", JsonString("object")),
                ("properties", obj(props.toArray())),
                ("required", JsonArray(required.toArray())),
                ("additionalProperties", JsonBool(false))
            ]
        )
    let annotations = obj([("readOnlyHint", JsonBool(true)), ("openWorldHint", JsonBool(false))])
    obj(
        [
            ("name", JsonString(name)),
            ("description", JsonString(description)),
            ("inputSchema", schema),
            ("annotations", annotations)
        ]
    )
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
