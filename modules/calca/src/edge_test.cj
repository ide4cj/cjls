package calca

import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

@CalcaTracked
func edgeLength(db: TestDb, file: SourceFile): Int64 {
    db.log("edgeLength")
    file.text(db).size
}

@CalcaTracked
func edgeFirstReader(db: TestDb, file: SourceFile): Int64 {
    db.log("edgeFirstReader")
    edgeLength(db, file)
}

@CalcaTracked
func edgeSecondReader(db: TestDb, file: SourceFile): Int64 {
    db.log("edgeSecondReader")
    edgeLength(db, file) * 2
}

@CalcaTracked
func edgeFirstInterner(db: TestDb, file: SourceFile): Int64 {
    db.log("edgeFirstInterner")
    file.text(db).size + Name(db, "shared").text(db).size
}

@CalcaTracked
func edgeSecondInterner(db: TestDb, file: SourceFile): Int64 {
    db.log("edgeSecondInterner")
    file.text(db).size * Name(db, "shared").text(db).size
}

/**
 * What a memo verifying learns from the edges of its dependencies alone: a memo verified in this
 * revision already, an interned value used in it already.
 */
@Test
class EdgeTest {
    @TestCase
    func aMemoVerifiedInThisRevisionThatChangedRunsItsOtherReadersAgain(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "abc")
        edgeFirstReader(db, file)
        edgeSecondReader(db, file)
        db.events.take()
        file.setText(db).to("abcd")

        // act
        let first = edgeFirstReader(db, file)
        let second = edgeSecondReader(db, file)

        // assert
        @Expect([first, second], [4, 8])
        @Expect(db.events.take(), ["edgeLength", "edgeFirstReader", "edgeSecondReader"])
    }

    @TestCase
    func aMemoVerifiedInThisRevisionThatKeptItsValueRunsNoReaderAgain(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "abc")
        edgeFirstReader(db, file)
        edgeSecondReader(db, file)
        db.events.take()
        file.setText(db).to("xyz")

        // act
        let first = edgeFirstReader(db, file)
        let second = edgeSecondReader(db, file)

        // assert
        @Expect([first, second], [3, 6])
        @Expect(db.events.take(), ["edgeLength"])
    }

    @TestCase
    func aValueInternedThatIsUsedInThisRevisionAlreadyHasNotChanged(): Unit {
        // arrange
        let db = TestDatabase()
        let file = SourceFile(db, "a.cj", "abc")
        let other = SourceFile(db, "b.cj", "")
        edgeFirstInterner(db, file)
        edgeSecondInterner(db, file)
        db.events.take()
        other.setText(db).to("changed")

        // act
        let first = edgeFirstInterner(db, file)
        let second = edgeSecondInterner(db, file)

        // assert
        @Expect([first, second], [9, 18])
        @Expect(db.events.take().size, 0)
    }
}
