package macro_host

import std.collection.ArrayList
import std.env.getTempDirectory
import std.fs.{Directory, File, remove}
import std.time.MonoTime
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.{Attr, Logger, LogLevel, LogRecord}
import macro_server.{MacroCallData, MacroResult, MacroResultData, MacroServerException}

/**
 * Counts the output boundaries: each attempted failed expansion stands for SDK stderr, each log for cjls output.
 */
class RetryTestHost <: Logger & MacroSession {
    var clock = MonoTime.now()
    var starts = 0
    var attempts = 0
    var kills = 0
    var closes = 0
    var hasStartupFailure = false
    var canAnswer = false
    var onCall: () -> Unit = {=> ()}
    let messages = ArrayList<String>()

    func server(deadlines!: Deadlines = HandFiredDeadlines()): GuardedServer {
        GuardedServer(Duration.second, this, deadlines, {=>
            starts++
            if (hasStartupFailure) {
                throw MacroServerException("cannot start")
            }
            this
        }, {=> clock})
    }

    public func expand(call: MacroCallData): MacroResult {
        attempts++
        onCall()
        if (canAnswer || call.methodName == Some("Healthy")) {
            return resultOf(MacroResultData(status: 1))
        }
        throw MacroServerException("cannot load library or macro crashed")
    }

    public func kill(): Unit { kills++ }
    public func close(): Unit { closes++ }
    public func isClosed(): Bool { false }
    public mut prop level: LogLevel { get() { LogLevel.ALL } set(_) {} }
    public func withAttrs(_: Array<Attr>): Logger { this }
    public func log(record: LogRecord): Unit { messages.add(record.message) }
}

/**
 * A call without tokens: the fake session only observes its library and method.
 */
func retryCall(library: String, method!: String = "Broken"): MacroCallData {
    MacroCallData(libPath: library, methodName: method)
}

@Test
class MacroRetriesTest {
    @TestCase
    func manyMethodsOfAnUnresponsiveLibraryHaveABoundedNumberOfStartsAndLogs() {
        // arrange
        let host = RetryTestHost()
        let server = host.server()

        // act
        for (i in 0..100) {
            server.expand(retryCall("missing-library", method: "Macro${i}"))
        }

        // assert
        @Expect(host.starts, 3)
        @Expect(host.attempts, 3)
        @Expect(host.kills, 3)
        @Expect(host.messages.size, 2)

        // act - a different library is not paused
        let healthy = server.expand(retryCall("healthy-library", method: "Healthy"))

        // assert
        match (healthy) {
            case Answered(_) => ()
            case Unanswered(reason) => @Fail(reason)
        }
        @Expect(host.attempts, 4)
        server.close()
    }

    @TestCase
    func aCooldownAllowsOnlyOneFailedProbeAndASuccessResetsTheBudget() {
        // arrange
        let host = RetryTestHost()
        let server = host.server()
        for (_ in 0..3) { server.expand(retryCall("missing-library")) }

        // act
        host.clock = host.clock + Duration.second * 59
        server.expand(retryCall("missing-library"))

        // assert
        @Expect(host.attempts, 3)

        // act
        host.clock = host.clock + Duration.second
        for (_ in 0..100) { server.expand(retryCall("missing-library")) }

        // assert
        @Expect(host.attempts, 4)
        @Expect(host.messages.size, 3)

        // act
        host.clock = host.clock + Duration.minute
        host.canAnswer = true
        let recovered = server.expand(retryCall("missing-library"))
        host.canAnswer = false
        server.expand(retryCall("missing-library"))
        host.canAnswer = true
        let afterCrash = server.expand(retryCall("missing-library"))

        // assert
        match (recovered) {
            case Answered(_) => ()
            case Unanswered(reason) => @Fail(reason)
        }
        match (afterCrash) {
            case Answered(_) => ()
            case Unanswered(reason) => @Fail(reason)
        }
        @Expect(host.attempts, 7)
        server.close()
    }

    @TestCase
    func repeatedCrashesOfALoadableLibraryPauseOnlyTheFailingMethod() {
        // arrange
        let host = RetryTestHost()
        let server = host.server()
        server.expand(retryCall("library", method: "Healthy"))

        // act
        for (_ in 0..100) { server.expand(retryCall("library")) }
        let healthy = server.expand(retryCall("library", method: "Healthy"))

        // assert
        @Expect(host.starts, 4)
        @Expect(host.attempts, 5)
        match (healthy) {
            case Answered(_) => ()
            case Unanswered(reason) => @Fail(reason)
        }
        server.close()
    }

    @TestCase
    func timeoutsPauseOnlyTheirMethodEvenBeforeAnyAnswer() {
        // arrange
        let host = RetryTestHost()
        let deadlines = HandFiredDeadlines()
        let server = host.server(deadlines: deadlines)
        host.onCall = {=> deadlines.fire(deadlines.armed.remove())}

        // act
        for (_ in 0..100) { server.expand(retryCall("library")) }
        host.onCall = {=> ()}
        let healthy = server.expand(retryCall("library", method: "Healthy"))

        // assert
        @Expect(host.attempts, 4)
        match (healthy) {
            case Answered(_) => ()
            case Unanswered(reason) => @Fail(reason)
        }
        server.close()
    }

    @TestCase
    func aFailedProbeCannotBypassTheCooldownByChangingFailureKind() {
        // arrange
        let host = RetryTestHost()
        let deadlines = HandFiredDeadlines()
        let server = host.server(deadlines: deadlines)
        host.onCall = {=> deadlines.fire(deadlines.armed.remove())}
        for (_ in 0..3) { server.expand(retryCall("library")) }

        // act - the probe disconnects instead of timing out
        host.clock = host.clock + Duration.minute
        host.onCall = {=> ()}
        for (_ in 0..100) { server.expand(retryCall("library")) }

        // assert
        @Expect(host.attempts, 4)
        server.close()
    }

    @TestCase
    func oneTimeoutAllowsTheSameMacroToRecoverOnItsNextCall() {
        // arrange
        let host = RetryTestHost()
        let deadlines = HandFiredDeadlines()
        let server = host.server(deadlines: deadlines)
        host.onCall = {=> deadlines.fire(deadlines.armed.remove())}

        // act
        server.expand(retryCall("library"))
        host.onCall = {=> ()}
        host.canAnswer = true
        let recovered = server.expand(retryCall("library"))

        // assert
        @Expect(host.attempts, 2)
        match (recovered) {
            case Answered(_) => ()
            case Unanswered(reason) => @Fail(reason)
        }
        server.close()
    }

    @TestCase
    func restartClearsFailureHistoryImmediately() {
        // arrange
        let host = RetryTestHost()
        let server = host.server()
        for (_ in 0..3) { server.expand(retryCall("library")) }

        // act
        server.restart()
        host.canAnswer = true
        let recovered = server.expand(retryCall("library"))

        // assert
        match (recovered) {
            case Answered(_) => ()
            case Unanswered(reason) => @Fail(reason)
        }
        @Expect(host.starts, 4)
        server.close()
    }

    @TestCase
    func replacingALibraryAtTheSamePathReleasesItsBudget() {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let path = dir.join("macro-library")
        let host = RetryTestHost()
        let server = host.server()
        try {
            File.writeTo(path, "old".toArray())
            for (_ in 0..3) { server.expand(retryCall(path.toString())) }

            // act - a size change does not depend on filesystem timestamp precision
            File.writeTo(path, "rebuilt library".toArray())
            host.canAnswer = true
            let recovered = server.expand(retryCall(path.toString()))

            // assert
            match (recovered) {
                case Answered(_) => ()
                case Unanswered(reason) => @Fail(reason)
            }
            @Expect(host.starts, 4)

            // act - replacing a loaded library also unloads the old session
            File.writeTo(path, "another rebuilt library".toArray())
            server.expand(retryCall(path.toString()))

            // assert
            @Expect(host.starts, 5)
            @Expect(host.closes, 1)
        } finally {
            server.close()
            remove(dir, recursive: true)
        }
    }

    @TestCase
    func startupFailuresShareABudgetAcrossLibrariesAndRestartReleasesIt() {
        // arrange
        let host = RetryTestHost()
        host.hasStartupFailure = true
        let server = host.server()

        // act
        for (i in 0..100) { server.expand(retryCall("library${i}")) }

        // assert
        @Expect(host.starts, 3)
        @Expect(host.attempts, 0)
        @Expect(host.messages.size, 2)

        // act
        server.restart()
        host.hasStartupFailure = false
        let recovered = server.expand(retryCall("library", method: "Healthy"))

        // assert
        match (recovered) {
            case Answered(_) => ()
            case Unanswered(reason) => @Fail(reason)
        }
        server.close()
    }
}
