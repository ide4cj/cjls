package cjls.macro_host

import std.collection.concurrent.LinkedBlockingQueue
import std.time.MonoTime
import std.unittest.*
import std.unittest.testmacro.*

@Test
class BackoffTest {
    @TestCase
    func eachDelayDoublesTheLastUpToTheCapAndResetStartsOver() {
        // arrange
        let backoff = Backoff(Duration.second, Duration.second * 5)

        // act
        let delays = [backoff.next(), backoff.next(), backoff.next(), backoff.next()]
        backoff.reset()
        let afterReset = backoff.next()

        // assert
        @Expect(delays, [Duration.second, Duration.second * 2, Duration.second * 4, Duration.second * 5])
        @Expect(afterReset, Duration.second)
    }
}

@Test
class WakeupsTest {
    let t0 = MonoTime.now()

    @TestCase
    func aWakeIsTakenOnceWithTheBuildAnyWakeAskedFor() {
        // arrange
        let wakeups = Wakeups()
        wakeups.wake(true)
        wakeups.wake(false)

        // act
        let first = wakeups.take(t0)
        let second = wakeups.take(t0)

        // assert
        @Expect(describe(first), "work, build")
        @Expect(describe(second), "wait")
    }

    @TestCase
    func aBuildThatFoundTheLockTakenIsBuiltAgainOnceItsDelayPassedWithoutAWake() {
        // arrange
        let wakeups = Wakeups()
        wakeups.built(false, t0)

        // act
        let before = wakeups.take(t0)
        let due = wakeups.take(t0 + Duration.second)
        let after = wakeups.take(t0 + Duration.second)

        // assert
        @Expect(describe(before), "wait 1s")
        @Expect(describe(due), "work, build")
        @Expect(describe(after), "wait")
    }

    @TestCase
    func eachRetryThatFindsTheLockTakenWaitsTwiceAsLongUntilABuildRuns() {
        // arrange
        let wakeups = Wakeups()

        // act
        wakeups.built(false, t0)
        wakeups.built(false, t0)
        let second = wakeups.take(t0)
        wakeups.built(false, t0)
        let third = wakeups.take(t0)
        wakeups.built(true, t0)
        wakeups.built(false, t0)
        let afterARun = wakeups.take(t0)

        // assert
        @Expect(describe(second), "wait 2s")
        @Expect(describe(third), "wait 4s")
        @Expect(describe(afterARun), "wait 1s")
    }

    @TestCase
    func anyWakeWhileARetryWaitsBuildsAtOnceAndTheNextRetryWaitsTheFirstDelayAgain() {
        // arrange
        let wakeups = Wakeups()
        wakeups.built(false, t0)
        wakeups.built(false, t0)
        wakeups.built(false, t0)

        // act
        wakeups.wake(false)
        let woken = wakeups.take(t0)
        wakeups.built(false, t0)
        let retry = wakeups.take(t0)

        // assert
        @Expect(describe(woken), "work, build")
        @Expect(describe(retry), "wait 1s")
    }

    @TestCase
    func aStopEndsTheThreadWithARetryDueOrAWakeWaiting() {
        // arrange
        let wakeups = Wakeups()
        wakeups.built(false, t0)
        wakeups.wake(true)

        // act
        wakeups.stop()

        // assert
        @Expect(describe(wakeups.take(t0 + Duration.second)), "ended")
    }

    private func describe(next: NextWork): String {
        match (next) {
            case Work(true) => "work, build"
            case Work(false) => "work"
            case Ended => "ended"
            case WaitFor(None) => "wait"
            case WaitFor(Some(left)) => "wait ${left.toSeconds()}s"
        }
    }
}

/**
 * A clock a test sets.
 */
class FakeClock {
    var now = MonoTime.now()
}

/**
 * The host's wait (`Wakeups.next`), on a thread of its own as the host's: what it returns is parked on a queue.
 */
@Test
class HostWaitTest {
    @TestCase
    func anEditWhileTheHostWaitsForARetryBuildsAtOnceAndTheBackoffStartsOver() {
        // arrange
        let clock = FakeClock()
        let wakeups = Wakeups()
        wakeups.built(false, clock.now)
        wakeups.built(false, clock.now)
        wakeups.built(false, clock.now)
        let taken = LinkedBlockingQueue<?Bool>()
        spawn {
            taken.add(wakeups.next(clock: {=> clock.now}))
        }

        // act
        wakeups.wake(false)
        let next = taken.remove()
        wakeups.built(false, clock.now)
        let retry = match (wakeups.take(clock.now)) {
            case WaitFor(Some(left)) => left
            case _ => Duration.Zero
        }

        // assert
        @Expect(next, Some(true))
        @Expect(retry, Duration.second)
    }

    @TestCase
    func aStopEndsTheHostWaitingForARetry() {
        // arrange
        let clock = FakeClock()
        let wakeups = Wakeups()
        wakeups.built(false, clock.now)
        let taken = LinkedBlockingQueue<?Bool>()
        spawn {
            taken.add(wakeups.next(clock: {=> clock.now}))
        }

        // act
        wakeups.stop()

        // assert
        @Expect(taken.remove(), None)
    }
}
