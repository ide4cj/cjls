package calca

import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

@CalcaTracked
func label(db: TestDb): String {
    db.log("label()")
    "none"
}

@CalcaTracked
func label(db: TestDb, file: SourceFile): String {
    db.log("label(${file})")
    file.path(db)
}

@CalcaTracked
func label(db: TestDb, mode: Mode): String {
    db.log("label(${mode})")
    if (mode.cyclic(db)) {
        "cyclic"
    } else {
        "plain"
    }
}

@CalcaTracked
func label(db: TestDb, file: SourceFile, width: Int64): String {
    db.log("label(${file}, ${width})")
    label(db, file)[0..width]
}

@CalcaTracked
func label(db: TestDb, mode: Mode, width: Int64): String {
    db.log("label(${mode}, ${width})")
    label(db, mode)[0..width]
}

@CalcaTracked
func label(db: TestDb, width: ?Int64): String {
    db.log("label(?Int64)")
    "${width}"
}

@CalcaTracked
func label(db: TestDb, width: ?String): String {
    db.log("label(?String)")
    width ?? "none"
}

/**
 * Named as `SourceFile.size`'s holder would be, but for the escaping: a function never meets a method.
 */
@CalcaTracked
func SourceFile_size(db: TestDb): Int64 {
    db.log("SourceFile_size()")
    -1
}

@Test
class OverloadTest {
    @TestCase
    func overloadsAreQueriesOfTheirOwn(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "")
        let mode = Mode(db, true)

        // act
        let results = [label(db), label(db, file), label(db, mode), label(db, file, 2), label(db, mode, 2),
            label(db, Some(1)), label(db, Some("x"))]

        // assert
        @Expect(results, ["none", "a.cj", "cyclic", "a.", "cy", "Some(1)", "x"])
        @Expect(db.events.take(),
            ["label()", "label(SourceFile(0))", "label(Mode(0))", "label(SourceFile(0), 2)", "label(Mode(0), 2)",
                "label(?Int64)", "label(?String)"])
    }

    @TestCase
    func eachOverloadIsRememberedOnItsOwn(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "")
        let mode = Mode(db, false)
        label(db, file, 1)
        label(db, mode, 1)
        db.events.take()

        // act
        mode.setCyclic(db).to(true)
        let results = [label(db, file, 1), label(db, mode, 1)]

        // assert - only what read the mode runs again
        @Expect(results, ["a", "c"])
        @Expect(db.events.take(), ["label(Mode(0))", "label(Mode(0), 1)"])
    }

    @TestCase
    func aFunctionNamedLikeAMethodIsAQueryOfItsOwn(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "hello")

        // act
        let results = [SourceFile_size(db), file.size(db)]

        // assert
        @Expect(results, [-1, 5])
        @Expect(db.events.take(), ["SourceFile_size()", "size(SourceFile(0))"])
    }
}
