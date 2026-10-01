package cjls.server

import std.collection.concurrent.LinkedBlockingQueue
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.*
import stdxx.Nullable
import jsonrpc.*
import cjls.lsp_types.*

/**
 * A transport that only takes what is written, so a test can wait for it; nothing is ever read.
 */
class WrittenTransport <: JsonRpcTransport {
    private let written = LinkedBlockingQueue<Body>()
    private let closed = AtomicBool(false)

    /**
     * Blocks until something is written, so no test has to poll a spawned publish.
     */
    func nextNotification(): NotificationBody {
        written.remove().getNotificationBodyOrThrow()
    }

    /**
     * Whether nothing was written that was not taken.
     */
    func isEmpty(): Bool {
        written.size == 0
    }

    public func isClosed(): Bool {
        closed.load()
    }

    public func close(): Unit {
        closed.store(true)
    }

    public func read(): ?Body {
        None
    }

    public func write(body: Body): Unit {
        written.add(body)
    }
}

/**
 * A client connected to `transport`, answering nothing.
 */
func clientOn(transport: WrittenTransport): Client {
    let client = Client()
    client.connect(Connection(transport, serverOf(Router()), NoopLogger()))
    client
}

func publishedOf(notification: NotificationBody): PublishDiagnosticsParams {
    notification.params.getOrThrow().read<PublishDiagnosticsParams>()
}

/**
 * A logger that keeps the level and message of each line, so a test can wait for one written
 * off-thread.
 */
class RecordingLogger <: Logger {
    let lines = LinkedBlockingQueue<(LogLevel, String)>()

    public mut prop level: LogLevel {
        get() {
            LogLevel.ALL
        }
        set(_) {}
    }

    public func withAttrs(_: Array<Attr>): Logger {
        this
    }

    public func log(record: LogRecord): Unit {
        lines.add((record.level, record.message))
    }

    public func isClosed(): Bool {
        false
    }

    public func close(): Unit {}
}

/**
 * A transport that answers every request written with an error, read back by the connection's
 * loop.
 */
class RefusingTransport <: JsonRpcTransport {
    private let inbound = LinkedBlockingQueue<?Body>()
    private let closed = AtomicBool(false)

    public func isClosed(): Bool {
        closed.load()
    }

    public func close(): Unit {
        if (!closed.swap(true)) {
            inbound.add(Option<Body>.None)
        }
    }

    public func read(): ?Body {
        inbound.remove()
    }

    public func write(body: Body): Unit {
        if (let Request(request) <- body) {
            inbound.add(ResponseBody(Nullable.Value(request.id),
                ResultOrError.Error(ResponseError(ErrorCode.METHOD_NOT_FOUND, "no such method"))).enveloped())
        }
    }
}

@Test
class ClientTest {
    @TestCase
    func aRequestTheClientRefusesIsAWarning() {
        // arrange
        let transport = RefusingTransport()
        let client = Client()
        let connection = Connection(transport, serverOf(Router()), NoopLogger())
        client.connect(connection)
        let serving = spawn {
            connection.serve()
        }
        let logger = RecordingLogger()

        // act
        client.request(RegistrationRequestSpec(), RegistrationParams(registrations: []), logger)

        // assert
        let (level, message) = logger.lines.remove()
        client.close()
        serving.get()
        @Expect(level, LogLevel.WARN)
        @Expect(message, "request failed")
    }

    @TestCase
    func aRequestLeftUnansweredAsTheConnectionClosesIsDropped() {
        // arrange
        let transport = WrittenTransport()
        let client = clientOn(transport)
        let logger = RecordingLogger()
        client.request(RegistrationRequestSpec(), RegistrationParams(registrations: []), logger)

        // act
        client.close()

        // assert
        let (level, message) = logger.lines.remove()
        @Expect(level, LogLevel.DEBUG)
        @Expect(message, "request dropped")
    }

    @TestCase
    func aNotificationGoesByTheMethodOfItsSpec() {
        // arrange
        let transport = WrittenTransport()
        let client = clientOn(transport)

        // act
        client.notify(PublishDiagnosticsNotificationSpec(), PublishDiagnosticsParams(uri: "file:///a.cj", diagnostics: []))

        // assert
        let sent = transport.nextNotification()
        @Expect(sent.method, "textDocument/publishDiagnostics")
        @Expect(publishedOf(sent).uri, "file:///a.cj")
    }

    @TestCase
    func aClientIsClosedOnceItsConnectionIs() {
        // arrange
        let transport = WrittenTransport()
        let client = clientOn(transport)
        let before = client.isClosed()

        // act
        client.close()

        // assert
        @Expect(!before)
        @Expect(client.isClosed())
    }

    @TestCase
    func aClientNotYetConnectedIsNotClosed() {
        // act
        let closed = Client().isClosed()

        // assert
        @Expect(!closed)
    }
}
