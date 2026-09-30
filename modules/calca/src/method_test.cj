package calca

import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

@CalcaTracked
extend SourceFile {
    @CalcaTracked
    func size(db: TestDb): Int64 {
        db.log("size(${this})")
        text(db).size
    }

    @CalcaTracked[noEq]
    func prefix(db: TestDb, length: Int64): String {
        db.log("prefix(${this}, ${length})")
        text(db)[0..min(length, size(db))]
    }

    /**
     * Not marked: a method as any other.
     */
    func shout(db: TestDb): String {
        db.log("shout(${this})")
        text(db).toAsciiUpper()
    }

    @CalcaTracked
    static func totalSize(db: TestDb, a: SourceFile, b: SourceFile): Int64 {
        db.log("totalSize(${a}, ${b})")
        a.size(db) + b.size(db)
    }

    @CalcaTracked
    static func greeting(db: TestDb): String {
        db.log("greeting")
        word()
    }

    private static func word(): String {
        "hello"
    }
}

@CalcaTracked
extend Mode {
    @CalcaTracked[cycleResult: fallbackDepth]
    func depth(db: TestDb): Int64 {
        if (cyclic(db)) {
            depth(db) + 1
        } else {
            0
        }
    }
}

func fallbackDepth(_: TestDb, _: Mode): Int64 {
    -1
}

@Test
class MethodTest {
    @TestCase
    func aTrackedMethodIsRememberedPerValue(): Unit {
        // arrange
        let db = TestDatabase()
        let a = SourceFile(db, "a.cj", "hello")
        let b = SourceFile(db, "b.cj", "hi")

        // act
        let results = [a.size(db), a.size(db), b.size(db)]

        // assert
        @Expect(results, [5, 5, 2])
        @Expect(db.events.take(), ["size(SourceFile(0))", "size(SourceFile(1))"])
    }

    @TestCase
    func aTrackedMethodWithArgumentsIsRememberedPerValueAndArguments(): Unit {
        // arrange
        let db = TestDatabase()
        let a = SourceFile(db, "a.cj", "hello")

        // act
        let results = [a.prefix(db, 2), a.prefix(db, 2), a.prefix(db, 3)]

        // assert
        @Expect(results, ["he", "he", "hel"])
        @Expect(db.events.take(), ["prefix(SourceFile(0), 2)", "size(SourceFile(0))", "prefix(SourceFile(0), 3)"])
    }

    @TestCase
    func aTrackedMethodRunsAgainOnceWhatItReadChanges(): Unit {
        // arrange
        let db = TestDatabase()
        let a = SourceFile(db, "a.cj", "hello")
        a.size(db)
        db.events.take()

        // act
        a.setText(db).to("hello, world")
        let result = a.size(db)

        // assert
        @Expect(result, 12)
        @Expect(db.events.take(), ["size(SourceFile(0))"])
    }

    @TestCase
    func aMethodNotMarkedIsNotAQuery(): Unit {
        // arrange
        let db = TestDatabase()
        let a = SourceFile(db, "a.cj", "hi")

        // act
        let results = [a.shout(db), a.shout(db)]

        // assert
        @Expect(results, ["HI", "HI"])
        @Expect(db.events.take(), ["shout(SourceFile(0))", "shout(SourceFile(0))"])
    }

    @TestCase
    func optionsGoOnEachMethod(): Unit {
        // arrange - `prefix` is `noEq`: what reads it runs again though its value did not change
        let db = TestDatabase()
        let a = SourceFile(db, "a.cj", "hello")
        @Expect(shortPrefix(db, a), "he")
        db.events.take()

        // act
        a.setText(db).to("heaven")
        let result = shortPrefix(db, a)

        // assert
        @Expect(result, "he")
        @Expect(db.events.take(), ["prefix(SourceFile(0), 2)", "size(SourceFile(0))", "shortPrefix"])
    }

    @TestCase
    func aTrackedMethodRecoversFromACycleWithItsFallback(): Unit {
        // arrange
        let db = TestDatabase()
        let mode = Mode(db, true)

        // act, assert
        @Expect(mode.depth(db), -1)
    }

    @TestCase
    func aStaticTrackedMethodIsRememberedPerArguments(): Unit {
        // arrange
        let db = TestDatabase()
        let a = SourceFile(db, "a.cj", "hello")
        let b = SourceFile(db, "b.cj", "hi")

        // act
        let results = [SourceFile.totalSize(db, a, b), SourceFile.totalSize(db, a, b), SourceFile.totalSize(db, b, a)]

        // assert
        @Expect(results, [7, 7, 7])
        @Expect(db.events.take(),
            ["totalSize(SourceFile(0), SourceFile(1))", "size(SourceFile(0))", "size(SourceFile(1))",
                "totalSize(SourceFile(1), SourceFile(0))"])
    }

    @TestCase
    func aStaticTrackedMethodOfNoArgumentsIsRememberedOnce(): Unit {
        // arrange
        let db = TestDatabase()

        // act
        let results = [SourceFile.greeting(db), SourceFile.greeting(db)]

        // assert
        @Expect(results, ["hello", "hello"])
        @Expect(db.events.take(), ["greeting"])
    }
}

@CalcaTracked
func shortPrefix(db: TestDb, file: SourceFile): String {
    db.log("shortPrefix")
    file.prefix(db, 2)
}
