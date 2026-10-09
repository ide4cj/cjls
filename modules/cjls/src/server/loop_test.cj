package cjls.server

import std.collection.ArrayList
import std.collection.concurrent.LinkedBlockingQueue
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.{LogLevel, NoopLogger}
import rope.Rope

@Test
class LoopTest {
    @TestCase
    func aWriteFromATaskIsFollowedByThePushOfTheOpenDocuments() {
        // arrange
        let state = stateWith("a")
        state.pushesDiagnostics = true
        state.openDocuments[PUSHED_PATH] = 1
        let transport = WrittenTransport()
        let loop = Loop(state, DiagnosticsPush(textAsDiagnostic, clientOn(transport), NoopLogger()))

        // act
        loop.start(NoopLogger()) {
            loop.write {state: ServerState => state.setFileContents(PUSHED_PATH, Rope("written"))}
        }
        loop.join()

        // assert
        let published = publishedOf(transport.nextNotification())
        @Expect(messageOf(published.diagnostics[0]), "written")
    }

    @TestCase[row in [(true, true, 1), (true, false, 0), (false, true, 0)]]
    func aWriteChangingTheFilesAsksAClientThatCanForItsTokensAgain(row: (Bool, Bool, Int64)) {
        // arrange
        let (refreshes, changes, asked) = row
        let state = stateWith("a")
        state.refreshesSemanticTokens = refreshes
        // what setting the state up changed
        state.takeFilesChanged()
        let refreshed = ArrayList<Bool>()
        let loop = Loop(state, Option<DiagnosticsPush>.None, refresh: {=> refreshed.add(true)})

        // act
        loop.write {
            state: ServerState => if (changes) {
                state.setFileContents(PUSHED_PATH, Rope("written"))
            }
        }

        // assert
        @Expect(refreshed.size, asked)
    }

    @TestCase
    func aWriteWaitsForTheOneInProgress() {
        // arrange
        let loop = Loop(ServerState())
        let entered = LinkedBlockingQueue<Bool>()
        let release = LinkedBlockingQueue<Bool>()
        let order = LinkedBlockingQueue<String>()
        loop.start(NoopLogger()) {
            loop.write {
                _: ServerState =>
                entered.add(true)
                release.remove()
                order.add("first")
            }
        }
        entered.remove()

        // act
        loop.start(NoopLogger()) {
            loop.write {_: ServerState => order.add("second")}
        }
        release.add(true)
        loop.join()

        // assert
        @Expect(order.remove(), "first")
        @Expect(order.remove(), "second")
    }

    @TestCase
    func aTaskThatThrowsIsAnErrorOfItsLoggerAndJoinReturns() {
        // arrange
        let loop = Loop(ServerState())
        let logger = RecordingLogger()

        // act
        loop.start(logger) {
            throw IllegalStateException("broken")
        }
        loop.join()

        // assert
        let (level, message) = logger.lines.remove()
        @Expect(level, LogLevel.ERROR)
        @Expect(message, "failed")
    }

    @TestCase
    func joinWaitsForTheTasksATaskStarted() {
        // arrange
        let loop = Loop(ServerState())
        let ran = ArrayList<String>()

        // act
        loop.start(NoopLogger()) {
            loop.start(NoopLogger()) {
                loop.write {_: ServerState => ran.add("inner")}
            }
        }
        loop.join()

        // assert
        @Expect(loop.write {_: ServerState => ran.toArray()}, ["inner"])
    }
}
