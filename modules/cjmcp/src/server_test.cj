package cjmcp

import std.collection.*
import std.env.getTempDirectory
import std.unittest.*
import std.unittest.testmacro.*
import fjson.*
import loupe.vfs.VfsPath

func request(server: McpServer, method: String, params!: JsonValue = obj([])): JsonValue {
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
        .getOrThrow()
}

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
        let notification =
            server.handle(##"{"jsonrpc":"2.0","method":"notifications/initialized"}"##.toArray())
        let listed = request(server, "tools/list")
        let repeated = request(server, "initialize")

        // assert
        @Expect(before["error"]["code"].asInteger(), -32600)
        @Expect(initialization["result"]["protocolVersion"].asString(), "2025-11-25")
        @Expect(initialization["id"].asString(), "test")
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
        let responses = bad.map { line => server.handle(line.toArray()).getOrThrow() }
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
        let notification =
            server
                .handle(
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
        let responses = calls.map { params => request(server, "tools/call", params: params) }
        let unknown = request(server, "unknown")

        // assert
        @Expect(responses.iterator().all { response => response["error"]["code"].asInteger() == -32602 })
        @Expect(unknown["error"]["code"].asInteger(), -32601)
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
}
