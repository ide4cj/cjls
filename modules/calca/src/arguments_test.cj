package calca

import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

@CalcaTracked
func slice(db: TestDb, file: SourceFile, start: Int64, end: Int64): String {
    db.log("slice(${file}, ${start}, ${end})")
    file.text(db)[start..end]
}

@CalcaTracked
func joined(db: TestDb, first: SourceFile, second: SourceFile): String {
    db.log("joined")
    slice(db, first, 0, 1) + slice(db, second, 0, 1)
}

@Test
class ArgumentsTest {
    @TestCase
    func aFunctionOfSeveralArgumentsRunsOncePerDistinctOnes(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")

        // act
        let results = [slice(db, file, 0, 2), slice(db, file, 0, 2), slice(db, file, 1, 3), slice(db, file, 0, 3)]

        // assert
        @Expect(results, ["he", "he", "el", "hel"])
        @Expect(db.events.take(), ["slice(SourceFile(0), 0, 2)", "slice(SourceFile(0), 1, 3)", "slice(SourceFile(0), 0, 3)"])
    }

    @TestCase
    func changingWhatOneArgumentsQueryReadLeavesTheOthersBe(): Unit {
        // arrange
        let db = TestDatabase()
        let a = SourceFile(db, "a.cj", "hello")
        let b = SourceFile(db, "b.cj", "world")
        slice(db, a, 0, 2)
        slice(db, b, 0, 2)
        db.events.take()

        // act
        a.setText(db).to("goodbye")
        let results = [slice(db, a, 0, 2), slice(db, b, 0, 2)]

        // assert
        @Expect(results, ["go", "wo"])
        @Expect(db.events.take(), ["slice(SourceFile(0), 0, 2)"])
    }

    @TestCase
    func aFunctionOfSeveralArgumentsIsADependencyLikeAnyOther(): Unit {
        // arrange
        let db = TestDatabase()
        let a = SourceFile(db, "a.cj", "hello")
        let b = SourceFile(db, "b.cj", "world")
        @Expect(joined(db, a, b), "hw")
        db.events.take()

        // act
        a.setText(db).to("happy")
        let result = joined(db, a, b)

        // assert - the slice is backdated, so `joined` does not run again
        @Expect(result, "hw")
        @Expect(db.events.take(), ["slice(SourceFile(0), 0, 1)"])
    }

    @TestCase
    func theOrderOfTheArgumentsIsPartOfTheKey(): Unit {
        // arrange
        let db = TestDatabase()
        let a = SourceFile(db, "a.cj", "hello")
        let b = SourceFile(db, "b.cj", "world")

        // act
        let results = [joined(db, a, b), joined(db, b, a)]

        // assert
        @Expect(results, ["hw", "wh"])
        @Expect(db.events.take().filter {event => event == "joined"}.size, 2)
    }
}
