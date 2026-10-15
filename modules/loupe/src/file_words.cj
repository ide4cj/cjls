package loupe

import std.collection.*
import std.deriving.*
import std.sort.sort
import calca.*
import calca.macros.*
import rope.Rope
import cjsyntax.isIdentLike
import loupe.db.{AnalysisDatabase, SourceFile}

// the hash of no byte, which every word's starts from
const WORD_SEED: UInt64 = 0

/**
 * The words of a file's text, each by its `wordHash`, sorted and each once: what `findReferences` asks before it
 * reads a file, a superset of the names the file spells.
 *
 * A word is a run of what a name is made of, cut where the lexer cuts one (`isIdentLike`), so a name the parser
 * reads is a word whatever is around it: a keyword taken as a name, a `$name` of a quote, a name between
 * backquotes or in an interpolation. Words in comments and strings are words too.
 */
@Derive[Equatable]
struct FileWords {
    FileWords(let hashes: Array<UInt64>) {}

    /**
     * Whether a word of the file has the hash `hash`; a false `true` only when two words' hashes are equal.
     */
    func has(hash: UInt64): Bool {
        var low = 0
        var high = hashes.size
        while (low < high) {
            let middle = (low + high) / 2
            if (hashes[middle] < hash) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        low < hashes.size && hashes[low] == hash
    }
}

/**
 * The words of `file` (`FileWords`), Roslyn's `SyntaxTreeIndex` and IntelliJ's `IdIndex` in cjls's terms, computed
 * when a search first asks for them and again only when the file's text changed: a file's text is read for a
 * search once.
 */
@CalcaTracked
func fileWords(db: AnalysisDatabase, file: SourceFile): FileWords {
    wordsOf(file.text(db))
}

/**
 * The words of `text`, a word across two of its chunks too.
 */
func wordsOf(text: Rope): FileWords {
    let found = HashSet<UInt64>()
    var hash = WORD_SEED
    var inWord = false
    for (chunk in text.chunks()) {
        let bytes = chunk.toArray()
        var at = 0
        while (at < bytes.size) {
            let b = bytes[at]
            // a chunk holds whole characters: a rune never continues into the next one
            let (size, part) = if (b < 0x80) {
                (1, isAsciiWordByte(b))
            } else {
                let (r, n) = Rune.fromUtf8(bytes, at)
                (n, isIdentLike(r))
            }
            if (part) {
                for (i in at..at + size) {
                    hash = mixWord(hash, bytes[i])
                }
                inWord = true
            } else if (inWord) {
                found.add(hash)
                hash = WORD_SEED
                inWord = false
            }
            at += size
        }
    }
    if (inWord) {
        found.add(hash)
    }
    let hashes = found.toArray()
    sort(hashes)
    FileWords(hashes)
}

/**
 * The hash of the word `name`, as `wordsOf` hashes the words of a text.
 */
func wordHash(name: String): UInt64 {
    var hash = WORD_SEED
    for (b in name.toArray()) {
        hash = mixWord(hash, b)
    }
    hash
}

/**
 * rustc's `FxHasher` a byte at a time: a word's hash made as its bytes are read, across chunks, with nothing
 * allocated. Never kept beyond the process, so no hash of std's needs to be stable here; a collision only lets a
 * file through.
 */
@OverflowWrapping
func mixWord(hash: UInt64, b: Byte): UInt64 {
    (((hash << 5) | (hash >> 59)) ^ UInt64(b)) * 0x517cc1b727220a95
}

func isAsciiWordByte(b: Byte): Bool {
    (b >= b'a' && b <= b'z') || (b >= b'A' && b <= b'Z') || (b >= b'0' && b <= b'9') || b == b'_'
}
