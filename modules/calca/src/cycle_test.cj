package calca

import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

@CalcaTracked[cycleResult: headFallback]
func head(db: TestDb, mode: Mode): Int64 {
    db.log("head")
    if (mode.cyclic(db)) {
        tail(db, mode) + 1
    } else {
        10
    }
}

func headFallback(_: TestDb, _: Mode): Int64 {
    -1
}

@CalcaTracked[cycleResult: tailFallback]
func tail(db: TestDb, mode: Mode): Int64 {
    db.log("tail")
    head(db, mode) + 1
}

func tailFallback(_: TestDb, _: Mode): Int64 {
    -2
}

@CalcaTracked[cycleResult: recoveredFallback]
func recovered(db: TestDb, mode: Mode): Int64 {
    unrecovered(db, mode)
}

func recoveredFallback(_: TestDb, _: Mode): Int64 {
    0
}

@CalcaTracked
func unrecovered(db: TestDb, mode: Mode): Int64 {
    recovered(db, mode)
}

/**
 * A fallback of several arguments.
 */
@CalcaTracked[cycleResult: pairFallback]
func pair(db: TestDb, mode: Mode, depth: Int64): Int64 {
    pair(db, mode, depth) + depth
}

func pairFallback(_: TestDb, _: Mode, depth: Int64): Int64 {
    depth * 100
}

@Test
class CycleTest {
    @TestCase
    func everyQueryOnACycleWithFallbacksTakesItsFallback(): Unit {
        // arrange
        let db = TestDatabase()
        let mode = Mode(db, true)

        // act
        let fromHead = head(db, mode)
        let fromTail = tail(db, mode)

        // assert - `tail` was computed on the cycle, and is not computed again
        @Expect(fromHead, -1)
        @Expect(fromTail, -2)
        @Expect(db.events.take(), ["head", "tail"])
    }

    @TestCase
    func aCycleRecoveredIsComputedAgainOnceWhatItReadChanges(): Unit {
        // arrange - only `head` reads the mode, `tail` depends on it through the cycle
        let db = TestDatabase()
        let mode = Mode(db, true)
        @Expect(head(db, mode), -1)
        db.events.take()

        // act
        mode.setCyclic(db).to(false)

        // assert
        @Expect(tail(db, mode), 11)
        @Expect(head(db, mode), 10)
        @Expect(db.events.take(), ["tail", "head"])
    }

    @TestCase
    func aCycleWithAQueryWithoutFallbackStillThrows(): Unit {
        // arrange
        let db = TestDatabase()
        let mode = Mode(db, true)

        // act
        let thrown = @AssertThrows[CycleException](recovered(db, mode))

        // assert
        @Expect(thrown.participants, ["recovered(0)", "unrecovered(0)"])
        @Expect(thrown.message, "cycle: recovered(0) -> unrecovered(0) -> recovered(0)")
    }

    @TestCase
    func aCycleFoundOnlyWhileVerifyingRecoversTheSameWay(): Unit {
        // arrange - no cycle yet: `tail` reads `head`, which reads only the mode
        let db = TestDatabase()
        let mode = Mode(db, false)
        @Expect(tail(db, mode), 11)
        db.events.take()

        // act - verifying `tail` executes `head`, which now needs `tail`
        mode.setCyclic(db).to(true)
        let fromTail = tail(db, mode)

        // assert
        @Expect(fromTail, -2)
        @Expect(head(db, mode), -1)
    }

    @TestCase
    func aFallbackTakesEveryArgument(): Unit {
        // arrange
        let db = TestDatabase()
        let mode = Mode(db, true)

        // act, assert
        @Expect(pair(db, mode, 3), 300)
    }

    @TestCase
    func aCycleWithoutFallbacksNamesItsQueries(): Unit {
        // arrange
        let db = TestDatabase()
        let mode = Mode(db, true)

        // act
        let thrown = @AssertThrows[CycleException](first(db, mode))

        // assert
        @Expect(thrown.participants, ["first(0)", "second(0)"])
    }
}
