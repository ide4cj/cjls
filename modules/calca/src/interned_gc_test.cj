package calca

import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

/**
 * Collected once unused for one active revision.
 */
@CalcaInterned[revisions: 1]
struct Word {
    let text: String
}

/**
 * Collected once unused for the default 3.
 */
@CalcaInterned
struct Term {
    let text: String
}

@CalcaInterned[forever]
struct Keyword {
    let text: String
}

/**
 * Interns the file's text and never reads it.
 */
@CalcaTracked
func wordOf(db: TestDb, file: SourceFile): Word {
    db.log("wordOf(${file})")
    Word(db, file.text(db))
}

@CalcaTracked
func wordsOf(db: TestDb, file: SourceFile): Array<Word> {
    file.text(db).split(" ").map {text => Word(db, text)}
}

@CalcaTracked
func wordLength(db: TestDb, word: Word): Int64 {
    db.log("wordLength(${word})")
    word.text(db).size
}

@CalcaTracked
func lengthOfWord(db: TestDb, file: SourceFile): Int64 {
    db.log("lengthOfWord(${file})")
    wordLength(db, Word(db, file.text(db)))
}

@CalcaTracked
func termOf(db: TestDb, file: SourceFile): Term {
    Term(db, file.text(db))
}

@CalcaTracked
func keywordOf(db: TestDb, file: SourceFile): Keyword {
    Keyword(db, file.text(db))
}

@CalcaTracked
func repeatedLength(db: TestDb, word: Word, times: Int64): Int64 {
    word.text(db).size * times
}

@CalcaTracked
func doubledLengthOfWord(db: TestDb, file: SourceFile): Int64 {
    repeatedLength(db, Word(db, file.text(db)), 2)
}

@CalcaTracked
extend Word {
    @CalcaTracked
    func paddedLength(db: TestDb, width: Int64): Int64 {
        max(text(db).size, width)
    }
}

@CalcaTracked
func paddedLengthOfWord(db: TestDb, file: SourceFile): Int64 {
    Word(db, file.text(db)).paddedLength(db, 4)
}

@CalcaTracked
func pairLength(db: TestDb, first: Word, second: Word): Int64 {
    first.text(db).size + second.text(db).size
}

/**
 * The length of the file's first two words, `first second`.
 */
@CalcaTracked
func lengthOfPair(db: TestDb, file: SourceFile): Int64 {
    let words = file.text(db).split(" ")
    pairLength(db, Word(db, words[0]), Word(db, words[1]))
}

@Test
class InternedGcTest {
    @TestCase
    func aValueUnusedIsCollectedAndItsSlotReusedUnderTheNextGeneration(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        let foo = wordOf(db, a)
        activeRevisions(db, other, 1)
        other.setText(db).to("collects")

        // act
        let bar = Word(db, "bar")

        // assert
        @Expect(foo.toString(), "Word(0)")
        @Expect(bar.toString(), "Word(0g1)")
        @AssertThrows[IllegalStateException](foo.text(db))
    }

    @TestCase
    func aQueryThatOnlyInternsIsComputedAgainOnceItsValueIsCollected(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        let foo = wordOf(db, a)
        activeRevisions(db, other, 2)
        db.events.take()

        // act
        let again = wordOf(db, a)

        // assert
        @Expect(db.events.take(), ["wordOf(SourceFile(0))"])
        @Expect(again != foo)
        @Expect(again.text(db), "foo")
    }

    @TestCase
    func verifyingTheQueryThatInternedAValueKeepsItAlive(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        let foo = wordOf(db, a)
        db.events.take()

        // act
        for (i in 0..3) {
            other.setText(db).to("${i}")
            wordOf(db, other)
            @Expect(wordOf(db, a), foo)
        }

        // assert
        @Expect(db.events.take(), ["wordOf(SourceFile(1))", "wordOf(SourceFile(1))", "wordOf(SourceFile(1))"])
        @Expect(foo.text(db), "foo")
    }

    @TestCase
    func batchesThatChangeNothingLeaveAValueAQueryHoldsAlive(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, _) = files(db, "foo")
        let foo = wordOf(db, a)
        db.events.take()

        // act
        for (_ in 0..2) {
            db.storage.batch {}
            // the table used, by no query
            Word(db, "bar")
        }
        let again = wordOf(db, a)

        // assert
        @Expect(db.events.take().size, 0)
        @Expect(again, foo)
        @Expect(again.text(db), "foo")
    }

    @TestCase
    func aValueInternedByAMoreDurableQueryIsNeverCollected(): Unit {
        // arrange
        let db = TestDatabase()
        let (m, other) = files(db, "")
        m.setText(db).withDurability(Durability.Medium).to("x")
        let x = wordOf(db, m)
        activeRevisions(db, other, 3)
        db.events.take()

        // act
        let again = wordOf(db, m)

        // assert
        @Expect(db.events.take().size, 0)
        @Expect(again, x)
        @Expect(x.text(db), "x")
    }

    @TestCase
    func aValueInternedOutsideAnyQueryIsNeverCollected(): Unit {
        // arrange
        let db = TestDatabase()
        let (_, other) = files(db, "")
        let x = Word(db, "x")

        // act
        activeRevisions(db, other, 3)

        // assert
        @Expect(x.text(db), "x")
    }

    @TestCase
    func revisionsTheTableIsNotUsedInDoNotAgeItsValues(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        let foo = wordOf(db, a)

        // act
        for (i in 0..6) {
            other.setText(db).to("${i}")
        }

        // assert
        @Expect(foo.text(db), "foo")
    }

    @TestCase
    func aValueLivesAsManyActiveRevisionsAsItsTypeSays(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        let foo = termOf(db, a)

        // act
        activeRevisions(db, other, 2, use: {=> termOf(db, other)})
        other.setText(db).to("kept")
        // reading `foo` would use it: whether its slot is free tells instead
        let probe = Term(db, "probe")
        other.setText(db).to("collects")

        // assert
        @Expect(probe.toString(), "Term(3)")
        @AssertThrows[IllegalStateException](foo.text(db))
    }

    @TestCase
    func aValueOfATypeKeptForeverIsNeverCollected(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        let foo = keywordOf(db, a)

        // act
        activeRevisions(db, other, 3, use: {=> keywordOf(db, other)})

        // assert
        @Expect(foo.text(db), "foo")
    }

    @TestCase
    func aSlotReusedByOtherFieldsNeverAnswersForTheOldValue(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "foo")
        @Expect(lengthOfWord(db, a), 3)
        activeRevisions(db, other, 1)
        other.setText(db).to("collects")
        let quux = Word(db, "quux")
        db.events.take()

        // act
        let result = lengthOfWord(db, a)

        // assert
        @Expect(quux.toString(), "Word(0g1)")
        @Expect(result, 3)
        @Expect(db.events.take(), ["lengthOfWord(SourceFile(0))", "wordLength(Word(2))"])
    }

    @TestCase
    func theSlotCollectedLastIsReusedFirst(): Unit {
        // arrange
        let db = TestDatabase()
        let (a, other) = files(db, "w0 w1 w2 w3 w4 w5")
        wordsOf(db, a)
        other.setText(db).to("w0 w1 w2 w4")
        wordsOf(db, other)
        other.setText(db).to("collects")

        // act
        let first = Word(db, "n1")
        let second = Word(db, "n2")

        // assert
        @Expect(first.toString(), "Word(5g1)")
        @Expect(second.toString(), "Word(3g1)")
    }

    @TestCase
    func snapshotsInterningTheSameFieldsAtOnceGetOneValue(): Unit {
        // arrange
        let db = TestDatabase()
        let files = Array<SourceFile>(8, {i => SourceFile(db, "${i}.cj", "same")})

        // act
        let snapshots = files.map {_ => db.snapshot()}
        let futures = Array<Future<Word>>(files.size, {i => spawn {wordOf(snapshots[i], files[i])}})
        let words = futures.map {future => future.get()}

        // assert
        @Expect(words.iterator().all {word => word == words[0]})
        @Expect(words[0].text(db), "same")
    }

    @TestCase
    func typingLeavesTheMemosOfOnlyTheWordsStillUsed(): Unit {
        // arrange
        let db = TestDatabase()
        let (typed, other) = files(db, "f")
        lengthOfWord(db, typed)

        // act
        typed.setText(db).to("fo")
        lengthOfWord(db, typed)
        typed.setText(db).to("foo")
        lengthOfWord(db, typed)
        other.setText(db).to("collects")
        lengthOfWord(db, typed)

        // assert
        let memos = wordLengthMemos(db)
        @Expect(memos.entries.size, 1)
        @Expect(memos.entries.slotCount, 2)
    }

    @TestCase
    func aMemoDroppedWithItsKeyIsChanged(): Unit {
        // arrange
        let db = TestDatabase()
        let (typed, other) = files(db, "f")
        lengthOfWord(db, typed)
        typed.setText(db).to("fo")
        lengthOfWord(db, typed)

        // act
        other.setText(db).to("collects")

        // assert
        @Expect(wordLengthMemos(db).maybeChangedAfter(db, Id(0), 0))
    }

    @TestCase
    func typingLeavesTheMemosOfAFunctionOfSeveralArgumentsOnlyForTheWordsStillUsed(): Unit {
        // arrange
        let db = TestDatabase()
        let (typed, other) = files(db, "f")
        doubledLengthOfWord(db, typed)

        // act
        typed.setText(db).to("fo")
        doubledLengthOfWord(db, typed)
        typed.setText(db).to("foo")
        doubledLengthOfWord(db, typed)
        other.setText(db).to("collects")
        let result = doubledLengthOfWord(db, typed)

        // assert
        let memos = memosOf<CalcaFields_repeatedLength_STestDb_SWord_SInt64, Int64>(db,
            CalcaTracked_repeatedLength_STestDb_SWord_SInt64.FUNCTION.index)
        @Expect(result, 6)
        @Expect(memos.entries.size, 1)
        @Expect(memos.entries.slotCount, 2)
    }

    @TestCase
    func typingLeavesTheMemosOfAMethodWithArgumentsOnlyForTheWordsStillUsed(): Unit {
        // arrange
        let db = TestDatabase()
        let (typed, other) = files(db, "f")
        paddedLengthOfWord(db, typed)

        // act
        typed.setText(db).to("fo")
        paddedLengthOfWord(db, typed)
        typed.setText(db).to("foobar")
        paddedLengthOfWord(db, typed)
        other.setText(db).to("collects")
        let result = paddedLengthOfWord(db, typed)

        // assert
        let memos = memosOf<CalcaFields_Word_DpaddedLength_STestDb_SInt64, Int64>(db,
            CalcaTracked_Word_DpaddedLength_STestDb_SInt64.FUNCTION.index)
        @Expect(result, 6)
        @Expect(memos.entries.size, 1)
        @Expect(memos.entries.slotCount, 2)
    }

    @TestCase
    func aMemoGoesWithAnyValueItsKeyHoldsAndTheOthersKeepTheirs(): Unit {
        // arrange
        let db = TestDatabase()
        let (typed, other) = files(db, "x a")
        lengthOfPair(db, typed)

        // act
        typed.setText(db).to("x b")
        lengthOfPair(db, typed)
        typed.setText(db).to("x c")
        lengthOfPair(db, typed)
        other.setText(db).to("collects")
        let result = lengthOfPair(db, typed)

        // assert
        let memos = memosOf<CalcaFields_pairLength_STestDb_SWord_SWord, Int64>(db,
            CalcaTracked_pairLength_STestDb_SWord_SWord.FUNCTION.index)
        @Expect(result, 2)
        @Expect(memos.entries.size, 1)
        @Expect(memos.entries.slotCount, 2)
    }

    /**
     * `a`, holding `text`, and `other`, which the writes go to.
     */
    private func files(db: TestDatabase, text: String): (SourceFile, SourceFile) {
        (SourceFile(db, "a.cj", text), SourceFile(db, "other.cj", ""))
    }

    /**
     * `count` revisions, each with a write and a use of the table that uses no value interned
     * before.
     */
    private func activeRevisions(db: TestDatabase, other: SourceFile, count: Int64, use!: ?() -> Any = None): Unit {
        for (i in 0..count) {
            other.setText(db).to("active ${i}")
            match (use) {
                case Some(f) => f()
                case None => wordOf(db, other)
            }
        }
    }

    private func wordLengthMemos(db: TestDatabase): MemoTable<TestDb, Word, Int64> {
        memosOf<Word, Int64>(db, CalcaTracked_wordLength_STestDb_SWord.FUNCTION.index)
    }

    private func memosOf<K, V>(db: TestDatabase, index: Int64): MemoTable<TestDb, K, V> where K <: Hashable &
        Equatable<K> {
        (db.storage.runtime.ingredientAt(index) as MemoTable<TestDb, K, V>).getOrThrow()
    }
}
