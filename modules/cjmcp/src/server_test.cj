package cjmcp

import std.env.getTempDirectory
import std.unittest.*
import std.unittest.testmacro.*
import fjson.*
import loupe.vfs.VfsPath

/**
 * Send a protocol request with a fixed test ID and require a response.
 */
func request(server: McpServer, method: String, params!: JsonValue = obj([])): JsonValue {
    let response =
        server
            .handle(
                obj(
                    [
                        ("jsonrpc", JsonString("2.0")),
                        ("id", JsonString("test")),
                        ("method", JsonString(method)),
                        ("params", params)
                    ]
                )
                    .toString()
                    .toArray()
            )
            .getOrThrow { IllegalStateException("test request did not produce a response") }
    fromJsonBytes<JsonValue>(toJsonBytes(response))
}

/**
 * Initialize a test session with a future version to exercise version negotiation.
 */
func initialize(server: McpServer): JsonValue {
    request(
        server,
        "initialize",
        params: obj(
            [
                ("protocolVersion", JsonString("2099-01-01")),
                ("capabilities", obj([])),
                ("clientInfo", obj([("name", JsonString("test")), ("version", JsonString("1"))]))
            ]
        )
    )
}

/**
 * Create a test session that completed initialization.
 */
func readyServer(): McpServer {
    let server = McpServer(VfsPath.file(getTempDirectory()))
    initialize(server)
    server.handle(##"{"jsonrpc":"2.0","method":"notifications/initialized"}"##.toArray())
    server
}

@Test
class McpServerTest {
    @TestCase
    func lifecycleAndVersionNegotiation() {
        // arrange
        let server = McpServer(VfsPath.file(getTempDirectory()))

        // act
        let before = request(server, "tools/list")
        let initialization = initialize(server)
        let waiting = request(server, "tools/list")
        let notification = server.handle(
            ##"{"jsonrpc":"2.0","method":"notifications/initialized"}"##.toArray()
        )
        let listed = request(server, "tools/list")
        let repeated = request(server, "initialize")

        // assert
        @Expect(before["error"]["code"].asInteger(), -32600)
        @Expect(initialization["result"]["protocolVersion"].asString(), "2025-11-25")
        @Expect(initialization["id"].asString(), "test")
        @Expect(initialization["result"]["serverInfo"], fromJsonBytes<JsonValue>(toJsonBytes(serverInfo())))
        @Expect(initialization["result"]["serverInfo"]["_meta"]["apiVersion"].asInteger(), 1)
        @Expect(initialization["result"]["serverInfo"]["_meta"]["features"], JsonArray([
            JsonString("structuredDiagnostics"), JsonString("worktreeSessions"),
            JsonString("checkedSourceChanges"), JsonString("sourceExcerpts"),
            JsonString("outputBudget"), JsonString("semanticViews"), JsonString("apiDocs"),
            JsonString("taskEvidence")
        ]))
        @Expect(waiting["error"]["code"].asInteger(), -32600)
        @Expect(notification.isNone())
        @Expect(listed["result"]["tools"].asArray().size, 1)
        @Expect(repeated["error"]["code"].asInteger(), -32600)
    }

    @TestCase
    func malformedRequestsRecoverWithoutChangingSession() {
        // arrange
        let server = readyServer()
        let bad =
            [
                "[",
                "{}",
                "[]",
                "null",
                ##"{"jsonrpc":"2.0","id":null,"method":"ping"}"##,
                ##"{"jsonrpc":"2.0","id":true,"method":"ping"}"##,
                ##"{"jsonrpc":"2.0","id":3,"method":7}"##
            ]

        // act
        let responses =
            bad
                .map {
                    line =>
                    let response =
                        server
                            .handle(line.toArray())
                            .getOrThrow {
                                IllegalStateException("test request did not produce a response")
                            }
                    fromJsonBytes<JsonValue>(toJsonBytes(response))
                }
        let ping = request(server, "ping")

        // assert
        @Expect(responses[0]["error"]["code"].asInteger(), -32700)
        @Expect(responses[1..].iterator().all { response => response["error"]["code"].asInteger() == -32600 })
        @Expect(ping["result"], obj([]))
    }

    @TestCase
    func notificationsNeverRunToolsOrProduceResponses() {
        // arrange
        let server = readyServer()

        // act
        let notification = server.handle(
            ##"{"jsonrpc":"2.0","method":"tools/call","params":{"name":"runPython","arguments":{"code":"print(1)"}}}"##
                .toArray()
        )
        let unknown = server.handle(##"{"jsonrpc":"2.0","method":"unknown"}"##.toArray())

        // assert
        @Expect(notification.isNone())
        @Expect(unknown.isNone())
    }

    @TestCase
    func toolArgumentsAndUnknownMethodsHaveProtocolErrors() {
        // arrange
        let server = readyServer()
        let calls =
            [
                obj([("name", JsonString("unknown"))]),
                obj([("name", JsonString("runPython"))]),
                obj(
                    [
                        ("name", JsonString("runPython")),
                        ("arguments", obj([("code", JsonInteger(1))]))
                    ]
                ),
                obj(
                    [
                        ("name", JsonString("runPython")),
                        ("arguments", obj([("code", JsonString("")), ("extra", JsonBool(true))]))
                    ]
                ),
                obj([("name", JsonString("runPython")), ("arguments", JsonNull)])
            ]

        // act
        let invalidBudgets =
            [JsonInteger(-1), JsonBool(true), JsonString("24000"), JsonNull, JsonFloat(1.5)]
        let budgetResponses =
            invalidBudgets
                .map {
                    budget =>
                    request(
                        server,
                        "tools/call",
                        params: obj(
                            [
                                ("name", JsonString("runPython")),
                                (
                                    "arguments",
                                    obj([("code", JsonString("")), ("maxOutputBytes", budget)])
                                )
                            ]
                        )
                    )
                }
        let invalidRoots =
            [JsonNull, JsonInteger(7), JsonBool(true), JsonString(""), JsonString("relative")]
        let rootResponses =
            invalidRoots
                .map {
                    directory =>
                    request(
                        server,
                        "tools/call",
                        params: obj(
                            [
                                ("name", JsonString("runPython")),
                                ("arguments", obj([("code", JsonString("")), ("root", directory)]))
                            ]
                        )
                    )
                }
        let responses = calls.map { params => request(server, "tools/call", params: params) }
        let unknown = request(server, "unknown")

        // assert
        @Expect(responses.iterator().all { response => response["error"]["code"].asInteger() == -32602 })
        @Expect(unknown["error"]["code"].asInteger(), -32601)
        @Expect(rootResponses.iterator().all { response => response["error"]["code"].asInteger() == -32602 })
        @Expect(budgetResponses.iterator().all { response => response["error"]["code"].asInteger() == -32602 })
    }

    @TestCase
    func pythonExecutionIsAdvertisedAsHavingExternalEffects() {
        // arrange
        let server = readyServer()

        // act
        let tool = request(server, "tools/list")["result"]["tools"][0]

        // assert
        @Expect(tool["name"].asString(), "runPython")
        @Expect(!tool["annotations"]["readOnlyHint"].asBool())
        @Expect(tool["annotations"]["openWorldHint"].asBool())
    }
    @TestCase
    func responseEnvelopesPreserveIdsAndPayloadPresence() {
        // arrange
        let server = readyServer()
        let requests =
            [
                ##"{"jsonrpc":"2.0","id":7,"method":"ping"}"##,
                ##"{"jsonrpc":"2.0","id":"строка","method":"ping"}"##,
                ##"{"jsonrpc":"2.0","id":9,"method":"unknown"}"##,
                "["
            ]
        let expected =
            [
                ##"{"jsonrpc":"2.0","id":7,"result":{}}"##,
                ##"{"jsonrpc":"2.0","id":"строка","result":{}}"##,
                ##"{"jsonrpc":"2.0","id":9,"error":{"code":-32601,"message":"Method not found: unknown"}}"##,
                ##"{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}"##
            ]

        // act
        let actual =
            requests
                .map {
                    line =>
                    let response =
                        server
                            .handle(line.toArray())
                            .getOrThrow {
                                IllegalStateException("test request did not produce a response")
                            }
                    String.fromUtf8(toJsonBytes(response))
                }

        // assert
        @Expect(actual, expected)
    }

    @TestCase
    func toolContentPreservesArbitraryStructuredResults() {
        // arrange
        let payload = fromJsonBytes<JsonValue>(
            ##"{"result":[null,true,42,{"text":"строка\n\"quoted\""}],"error":null}"##.toArray()
        )

        // act
        let result = fromJsonBytes<JsonValue>(toJsonBytes(toolResult(payload, error: false)))
        let text = result["content"][0]

        // assert
        @Expect(text["type"], JsonString("text"))
        @Expect(fromJsonBytes<JsonValue>(text["text"].asString().toArray()), payload)
        @Expect(result["structuredContent"], payload)
        @Expect(result["isError"], JsonBool(false))
    }

    @TestCase
    func workspaceAcquisitionFailureKeepsExplicitNullFields() {
        // arrange
        let server = readyServer()
        let missing = getTempDirectory().join("cjmcp-missing-workspace-json-derives").toString()

        // act
        let response =
            request(
                server,
                "tools/call",
                params: obj(
                    [
                        ("name", JsonString("runPython")),
                        (
                            "arguments",
                            obj([("code", JsonString("")), ("root", JsonString(missing))])
                        )
                    ]
                )
            )["result"]
        let failure = response["structuredContent"]

        // assert
        @Expect(response["isError"], JsonBool(true))
        @Expect(failure.get("revision"), Some(JsonNull))
        @Expect(failure.get("sessionId"), Some(JsonNull))
        @Expect(failure["root"], JsonString(missing))
        @Expect(!failure["error"].asString().isEmpty())
        @Expect(fromJsonBytes<JsonValue>(response["content"][0]["text"].asString().toArray()), failure)
    }

    @TestCase
    func toolSchemaPreservesArgumentConstraints() {
        // arrange
        let server = readyServer()

        // act
        let schema = request(server, "tools/list")["result"]["tools"][0]["inputSchema"]
        let properties = schema["properties"]
        let budget = properties["maxOutputBytes"]

        // assert
        @Expect(schema["type"], JsonString("object"))
        @Expect(schema["required"], JsonArray([JsonString("code")]))
        @Expect(schema["additionalProperties"], JsonBool(false))
        @Expect(properties["code"]["type"], JsonString("string"))
        @Expect(properties["root"]["type"], JsonString("string"))
        @Expect(budget["type"], JsonString("integer"))
        @Expect(budget["minimum"], JsonInteger(0))
        @Expect(budget["default"], JsonInteger(24000))
    }
}

/**
 * Build arbitrary request fixtures independently of the response types.
 */
func obj(members: Array<(String, JsonValue)>): JsonValue {
    JsonObject(members)
}
