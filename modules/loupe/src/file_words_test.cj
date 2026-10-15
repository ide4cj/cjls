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

    @TestCase
    func anEmptyTextHasNoWord() {
        // act, assert
        @Expect(wordsOf(Rope("")).hashes.size, 0)
        @Expect(!wordsOf(Rope("")).has(wordHash("a")))
    }
}
