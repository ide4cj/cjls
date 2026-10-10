package cjls.server

import std.collection.concurrent.LinkedBlockingQueue
import std.env.getTempDirectory
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import stdxx.{IntegerOrString, Nullable}
import fjson.*
import jsonrpc.*
import rope.Rope
import loupe.vfs.VfsPath
import cjls.lsp_types.*
import cjls.macros.LspHandler

/**
 * A request as the connection would hand it over, with its answer caught on a queue so a test can
 * wait for one given off-thread.
 */
class Asked {
    let answers = LinkedBlockingQueue<ResultOrError>()
    let request: InboundRequest

    Asked(method: String, params!: ?RawJson = Option<RawJson>.None, decodedParams!: ?Any = Option<Any>.None) {
        let answers = this.answers
        request = InboundRequest(Integer(1), method, params, CancellationToken(), {answer => answers.add(answer)},
            decodedParams: decodedParams)
    }

    func answer(): ResultOrError {
        answers.remove()
    }
}

func paramsOf(json: String): RawJson {
    RawJson(json.toArray())
}

/**
 * What was written, read into a tree for a test to look into.
 */
func treeOf(written: RawJson): JsonValue {
    written.read<JsonValue>()
}

func hoverParams(): RawJson {
    paramsOf(##"{"textDocument": {"uri": "file:///a.cj"}, "position": {"line": 3, "character": 1}}"##)
}

func initializeParams(): RawJson {
    paramsOf(##"{"processId": null, "rootUri": null, "capabilities": {}}"##)
}

/**
 * The lifecycle's own handlers, doing nothing but answering.
 */
func lifecycleRouter(): Router {
    Router()
        .route(InitializeRequestSpec()) {_: Context<InitializeParams> => InitializeResult(capabilities: ServerCapabilities())}
        .route(ShutdownRequestSpec()) {_: Context<Unit> => ()}
}

func serverOf(router: Router, client!: Client = Client()): Server {
    Server(router, client, NoopLogger())
}

func initialized(router: Router, client!: Client = Client()): Server {
    let server = serverOf(router, client: client)
    let asked = Asked(InitializeRequestSpec.METHOD, params: initializeParams())
    server.onRequest(asked.request)
    asked.answer().getResultOrThrow()
    server
}

/**
 * Recurses until the stack runs out. Each frame holds 8 KB, read at an index only the call below
 * gives, so no optimization makes a loop of it, and the stack, half a gigabyte, runs out in a
 * second rather than tens of millions of frames.
 */
func deeper(depth: Int64): Int64 {
    var kept = VArray<Int64, $1024>(repeat: 0)
    kept[depth % 1024] = depth
    let below = deeper(depth + 1)
    depth - below + kept[(below & 0x7fff_ffff) % 1024]
}

func overflowTheStack(): Nothing {
    deeper(0)
    throw IllegalStateException("the stack never ran out")
}

let PARKED_PATH = VfsPath.file(getTempDirectory().join("a.cj"))

/**
 * The answer to a hover whose handler takes its snapshot, parks until `interrupt` has run, then
 * queries it.
 */
func answerOfAQueryParkedUntil(interrupt: (ServerState, InboundRequest) -> Unit): ResultOrError {
    answerOfAQueryParkedUntil(HoverRequestSpec.METHOD, interrupt)
}

/**
 * The same for a request of `method`, a hover or a diagnostic pull.
 */
func answerOfAQueryParkedUntil(method: String, interrupt: (ServerState, InboundRequest) -> Unit): ResultOrError {
    let release = LinkedBlockingQueue<Bool>()
    let state = ServerState()
    state.setFileContents(PARKED_PATH, Rope("a"))
    let parked = {snapshot: ServerSnapshot =>
        release.remove()
        snapshot.sourceFile(PARKED_PATH).getOrThrow().text(snapshot.analysis)
    }
    let server = initialized(lifecycleRouter()
        .withState(state)
        .route(HoverRequestSpec()) {
            ctx: ReadOnlyContext<HoverParams> =>
                parked(ctx.snapshot)
                Nullable<Hover>.Null
        }
        .route(DocumentDiagnosticRequestSpec()) {
            ctx: ReadOnlyContext<DocumentDiagnosticParams> =>
                parked(ctx.snapshot)
                DocumentDiagnosticReport.AsRelatedFullDocumentDiagnosticReport(
                    RelatedFullDocumentDiagnosticReport(items: []))
        })
    let asked = Asked(method, params: hoverParams())
    server.onRequest(asked.request)

    interrupt(state, asked.request)
    release.add(true)
    asked.answer()
}

let describedClients = LinkedBlockingQueue<Client>()

/**
 * Tells what it was given: the line and the cancellation in its answer, the client on a queue.
 */
@LspHandler[readonly]
func describeHover(client: Client, cancellation: CancellationToken, params: HoverParams): Nullable<Hover> {
    describedClients.add(client)
    let described = "${params.position.line}:${cancellation.isCancelled}"
    Nullable.Value(Hover(contents: MarkupContentOrMarkedStringOrMarkedStrings.AsMarkupContent(
        MarkupContent(kind: MarkupKind.PlainText, value: described))))
}

@Test
class ServerLifecycleTest {
    @TestCase
    func aRequestBeforeInitializeIsRefused() {
        // arrange
        let server = serverOf(lifecycleRouter())
        let asked = Asked(ShutdownRequestSpec.METHOD)

        // act
        server.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.SERVER_NOT_INITIALIZED, asked.answer().getErrorOrThrow().code)
    }

    @TestCase
    func aNotificationBeforeInitializeIsDropped() {
        // arrange - a `route` handler runs within `onNotification`: once that returns, it has run or never will
        let ran = AtomicBool(false)
        let server = serverOf(lifecycleRouter().route(InitializedNotificationSpec()) {_: Context<InitializedParams> => ran.store(true)})

        // act
        server.onNotification(InitializedNotificationSpec.METHOD, paramsOf("{}"))

        // assert
        @Expect(!ran.load())
    }

    @TestCase
    func aSuccessfulInitializeStartsTheServer() {
        // act
        let server = initialized(lifecycleRouter())

        // assert
        @Expect(Lifecycle.Initialized, server.lifecycle)
    }

    @TestCase
    func aFailedInitializeLeavesTheServerUninitialized() {
        // arrange - `capabilities` is required, so these params do not decode
        let server = serverOf(lifecycleRouter())
        let asked = Asked(InitializeRequestSpec.METHOD, params: paramsOf("{}"))

        // act
        server.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.INVALID_PARAMS, asked.answer().getErrorOrThrow().code)
        @Expect(Lifecycle.Uninitialized, server.lifecycle)
    }

    @TestCase
    func aSecondInitializeIsRefused() {
        // arrange
        let server = initialized(lifecycleRouter())
        let asked = Asked(InitializeRequestSpec.METHOD, params: initializeParams())

        // act
        server.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.INVALID_REQUEST, asked.answer().getErrorOrThrow().code)
    }

    @TestCase
    func aRequestAfterShutdownIsRefused() {
        // arrange
        let server = initialized(lifecycleRouter())
        let shutdown = Asked(ShutdownRequestSpec.METHOD)
        server.onRequest(shutdown.request)
        let again = Asked(ShutdownRequestSpec.METHOD)

        // act
        server.onRequest(again.request)

        // assert
        @Expect(shutdown.answer().getResultOrThrow().toString() == "null")
        @Expect(ErrorCode.INVALID_REQUEST, again.answer().getErrorOrThrow().code)
    }

    @TestCase
    func exitAfterShutdownExitsCleanly() {
        // arrange
        let server = initialized(lifecycleRouter())
        let shutdown = Asked(ShutdownRequestSpec.METHOD)
        server.onRequest(shutdown.request)
        shutdown.answer()

        // act
        server.onNotification(ExitNotificationSpec.METHOD, Option<RawJson>.None)

        // assert
        @Expect(0, server.exitCode)
        @Expect(Lifecycle.Exited, server.lifecycle)
    }

    @TestCase
    func exitWithoutShutdownExitsWithAnError() {
        // arrange - `exit` is honoured in any state, even before `initialize`
        let server = serverOf(lifecycleRouter())

        // act
        server.onNotification(ExitNotificationSpec.METHOD, Option<RawJson>.None)

        // assert
        @Expect(1, server.exitCode)
    }
}

@Test
class ServerDispatchTest {
    @TestCase
    func anUnknownMethodIsNotFound() {
        // arrange
        let server = initialized(lifecycleRouter())
        let asked = Asked("textDocument/hover")

        // act
        server.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.METHOD_NOT_FOUND, asked.answer().getErrorOrThrow().code)
    }

    @TestCase
    func aReadOnlyRequestIsAnsweredFromAThreadOfItsOwn() {
        // arrange - the handler parks until released; `onRequest` returning while it is parked
        // shows it did not run on the calling thread
        let release = LinkedBlockingQueue<Bool>()
        let server = initialized(lifecycleRouter().route(HoverRequestSpec()) {
            _: ReadOnlyContext<HoverParams> =>
                release.remove()
                Nullable<Hover>.Null
        })
        let asked = Asked(HoverRequestSpec.METHOD, params: hoverParams())

        // act
        server.onRequest(asked.request)
        @Expect(!asked.request.isAnswered)
        release.add(true)

        // assert
        @Expect(asked.answer().getResultOrThrow().toString() == "null")
    }

    @TestCase
    func aQueryTheFilesChangedUnderIsAnsweredContentModified() {
        // act
        let answer = answerOfAQueryParkedUntil {state, _ => state.setFileContents(PARKED_PATH, Rope("b"))}

        // assert
        @Expect(ErrorCode.CONTENT_MODIFIED, answer.getErrorOrThrow().code)
    }

    @TestCase
    func aPullTheFilesChangedUnderIsAnsweredServerCancelledToBeAskedAgain() {
        // act
        let answer = answerOfAQueryParkedUntil(DocumentDiagnosticRequestSpec.METHOD) {
            state, _ => state.setFileContents(PARKED_PATH, Rope("b"))
        }

        // assert
        let error = answer.getErrorOrThrow()
        @Expect(ErrorCode.SERVER_CANCELLED, error.code)
        @Expect(error.data.getOrThrow().read<DiagnosticServerCancellationData>().retriggerRequest)
    }

    @TestCase
    func aPullTheClientCancelledIsAnsweredRequestCancelled() {
        // act
        let answer = answerOfAQueryParkedUntil(DocumentDiagnosticRequestSpec.METHOD) {
            _, request => request.cancellation.cancel()
        }

        // assert
        @Expect(ErrorCode.REQUEST_CANCELLED, answer.getErrorOrThrow().code)
    }

    @TestCase
    func aQueryOfARequestTheClientCancelledStopsMidway() {
        // act
        let answer = answerOfAQueryParkedUntil {_, request => request.cancellation.cancel()}

        // assert
        @Expect(ErrorCode.REQUEST_CANCELLED, answer.getErrorOrThrow().code)
    }

    @TestCase
    func aHandlerGetsItsParamsAndWhatItAsksFor() {
        // arrange
        let client = Client()
        let server = initialized(lifecycleRouter().route(HoverRequestSpec(), describeHover), client: client)
        let asked = Asked(HoverRequestSpec.METHOD, params: hoverParams())
        asked.request.cancellation.cancel()

        // act
        server.onRequest(asked.request)

        // assert
        let contents = treeOf(asked.answer().getResultOrThrow())["contents"]
        @Expect("3:true", contents["value"].asString())
        @Expect(refEq(client, describedClients.remove()))
    }

    @TestCase
    func paramsTheReadLoopDecodedInPlaceAreTheOnesAHandlerGets() {
        // arrange - the bytes say line 3, what was decoded in place line 7
        let server = initialized(lifecycleRouter().route(HoverRequestSpec(), describeHover))
        let decoded: Any = HoverParams(textDocument: TextDocumentIdentifier(uri: "file:///a.cj"),
            position: Position(line: 7, character: 1))
        let asked = Asked(HoverRequestSpec.METHOD, params: hoverParams(), decodedParams: decoded)

        // act
        server.onRequest(asked.request)

        // assert
        let contents = treeOf(asked.answer().getResultOrThrow())["contents"]
        @Expect("7:false", contents["value"].asString())
        describedClients.remove()
    }

    @TestCase
    func theServerReadsARoutedMethodsParamsInPlaceAndNoOthers() {
        // arrange
        let server = serverOf(lifecycleRouter().route(HoverRequestSpec(), describeHover))

        // act
        let readInPlace = server.paramsReader(HoverRequestSpec.METHOD).getOrThrow()
        let params = readInPlace(FjReader(hoverParams().bytes))

        // assert
        @Expect(3, (params as HoverParams).getOrThrow().position.line)
        @Expect(server.paramsReader(DefinitionRequestSpec.METHOD).isNone())
    }

    @TestCase
    func aHandlerThatThrowsAnswersWithItsError() {
        // arrange
        let server = initialized(lifecycleRouter().route(HoverRequestSpec()) {
            _: Context<HoverParams> => throw RpcException(ErrorCode.UNKNOWN_ERROR_CODE, "no")
        })
        let asked = Asked(HoverRequestSpec.METHOD, params: hoverParams())

        // act
        server.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.UNKNOWN_ERROR_CODE, asked.answer().getErrorOrThrow().code)
    }

    @TestCase
    func aReadOnlyHandlerThatOverflowsItsStackAnswersInternalError() {
        // arrange
        let server = initialized(lifecycleRouter().route(HoverRequestSpec()) {
            _: ReadOnlyContext<HoverParams> => overflowTheStack()
        })
        let asked = Asked(HoverRequestSpec.METHOD, params: hoverParams())

        // act
        server.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.INTERNAL_ERROR, asked.answer().getErrorOrThrow().code)
    }

    @TestCase
    func aContextHandlerThatOverflowsItsStackAnswersInternalErrorOnTheReadLoop() {
        // arrange - a `Context` handler runs within `onRequest`, so nothing may escape it
        let server = initialized(lifecycleRouter().route(HoverRequestSpec()) {
            _: Context<HoverParams> => overflowTheStack()
        })
        let asked = Asked(HoverRequestSpec.METHOD, params: hoverParams())

        // act
        server.onRequest(asked.request)

        // assert
        @Expect(ErrorCode.INTERNAL_ERROR, asked.answer().getErrorOrThrow().code)
        @Expect(Lifecycle.Initialized, server.lifecycle)
    }

    @TestCase
    func aNotificationHandlerThatOverflowsItsStackDoesNotStopTheServer() {
        // arrange
        let server = initialized(lifecycleRouter().route(InitializedNotificationSpec()) {
            _: Context<InitializedParams> => overflowTheStack()
        })

        // act
        server.onNotification(InitializedNotificationSpec.METHOD, paramsOf("{}"))

        // assert
        @Expect(Lifecycle.Initialized, server.lifecycle)
    }

    @TestCase
    func aNotificationHandlerThatThrowsDoesNotStopTheServer() {
        // arrange
        let server = initialized(lifecycleRouter().route(InitializedNotificationSpec()) {_: Context<InitializedParams> => throw Exception("no")})

        // act
        server.onNotification(InitializedNotificationSpec.METHOD, paramsOf("{}"))

        // assert
        @Expect(Lifecycle.Initialized, server.lifecycle)
    }
}

@Test
class RouterTest {
    @TestCase
    func twoHandlersForOneMethodAreRefused() {
        // act & assert
        @AssertThrows[IllegalArgumentException](lifecycleRouter().route(ShutdownRequestSpec()) {_: Context<Unit> => ()})
    }

    @TestCase
    func aLifecycleMethodHandledOffTheReadLoopIsRefused() {
        // act & assert - whatever arrives after `shutdown` has to see the state it leaves
        @AssertThrows[IllegalArgumentException](Router().route(ShutdownRequestSpec()) {_: ReadOnlyContext<Unit> => ()})
    }
}
