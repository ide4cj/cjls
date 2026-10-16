package loupe

import std.unittest.*
import std.unittest.testmacro.*
import rope.Rope

@Test
class FileWordsTest {
    @TestCase
    func aWordIsFoundAtEveryOffsetAroundTheBoundaryOfTwoChunks() {
        // arrange - a two-byte character before the word moves where a chunk may end
        let filler = String.join(Array<String>(1500, repeat: "é "))
        let first = Rope(filler).chunks().next().getOrThrow().size
        for (at in first - 8..first + 8 where at >= 0 && at < filler.size && (filler[at] & 0xC0) != 0x80) {
            let text = Rope(filler[..at] + " needle " + filler[at..])

            // act
            let words = wordsOf(text)

            // assert
            @Expect(words.has(wordHash("needle")))
            @Expect(!words.has(wordHash("needles")))
            @Expect(!words.has(wordHash("needl")))
        }
    }

    @TestCase
    func aNameIsAWordWhereverTheLexerCutsOne() {
        // arrange
        let text = Rope(
            "let a = `b` + \$c + \"\${d}e\" + f.size\n// g\nlet 数组→ = public\nlet sizeOf = 1\n")

        // act
        let words = wordsOf(text)

        // assert
        for (name in ["b", "c", "d", "size", "g", "数组", "public", "sizeOf"]) {
            @Expect(words.has(wordHash(name)))
        }
        for (name in ["数", "→", "siz", "Of"]) {
            @Expect(!words.has(wordHash(name)))
        }
    }

    @TestCase
    func aWordEndingTheTextIsAWord() {
        // act
        let words = wordsOf(Rope("let a = last"))

        // assert
        @Expect(words.has(wordHash("last")))
    }

    /**
     * `(word, hash)`: rustc-hash 2.1.1's `FxHasher`, `write_u8` for each byte of the word, then `finish`.
     */
    @TestCase[row in [
        ("a", 0xee4d894e95950e4au64),
        ("size", 0xb0efaedfaeffb597u64),
        ("getRawArray", 0x8519663407cee33au64),
        ("数组", 0xd1956ca507ed3a59u64),
        ("computeTheTypeArgumentsOfACallNotWrittenOut", 0x853011e4e92df95au64)
    ]]
    func aWordIsHashedAsRustcHash2HashesItByteByByte(row: (String, UInt64)) {
        // arrange
        let (word, hash) = row

        // act, assert
        @Expect(wordHash(word), hash)
    }

    @TestCase
    func anEmptyTextHasNoWord() {
        // act, assert
        @Expect(!wordsOf(Rope("")).has(wordHash("a")))
    }
}
