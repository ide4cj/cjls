package loupe

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import rope.Rope
import cjsyntax.isIdentLike
import loupe.db.{AnalysisDatabase, SourceFile}

// the hash of no byte, which every word's starts from
const WORD_SEED: UInt64 = 0

// bits set per word: 13 at 19.17 bits a word, of 9 bits each, 7 from one remix
const PROBES = 13

/**
 * The words of a file's text, each by its `wordHash`, in a bloom filter: what `findReferences` asks before it
 * reads a file, a superset of the names the file spells.
 *
 * A word is a run of what a name is made of, cut where the lexer cuts one (`isIdentLike`), so a name the parser
 * reads is a word whatever is around it: a keyword taken as a name, a `$name` of a quote, a name between
 * backquotes or in an interpolation. Words in comments and strings are words too.
 */
@Derive[Equatable]
struct FileWords {
    FileWords(let bits: Array<UInt64>) {}

    /**
     * A blocked bloom filter of `hashes` at a false positive rate of about 1e-4, Roslyn's: 19.17 bits a word, 13
     * of them set per word, all in one block of 512 bits (a cache line) the word's hash chooses.
     */
    static func of(hashes: Collection<UInt64>): FileWords {
        let blocks = max(1, (hashes.size * 1917 / 100 + 511) / 512)
        let bits = Array<UInt64>(blocks * 8, repeat: 0)
        for (hash in hashes) {
            let base = blockOf(hash, blocks)
            var mixed = remix(hash)
            for (i in 0..PROBES) {
                if (i == 7) {
                    mixed = remix(mixed)
                }
                let bit = (mixed >> UInt64((i % 7) * 9)) & 511
                bits[base + Int64(bit >> 6)] |= 1 << (bit & 63)
            }
        }
        FileWords(bits)
    }

    /**
     * Whether a word of the file may have the hash `hash`: a false `true` about once in 10 000 words it lacks.
     */
    func has(hash: UInt64): Bool {
        let base = blockOf(hash, bits.size / 8)
        var mixed = remix(hash)
        for (i in 0..PROBES) {
            if (i == 7) {
                mixed = remix(mixed)
            }
            let bit = (mixed >> UInt64((i % 7) * 9)) & 511
            if ((bits[base + Int64(bit >> 6)] & (1 << (bit & 63))) == 0) {
                return false
            }
        }
        true
    }

    private static func blockOf(hash: UInt64, blocks: Int64): Int64 {
        Int64((hash >> 32) % UInt64(blocks)) * 8
    }

    /**
     * splitmix64's finalizer: the 13 probes' 117 bits drawn from one 64-bit hash, 63 at a time.
     */
    @OverflowWrapping
    private static func remix(hash: UInt64): UInt64 {
        var z = hash + 0x9e3779b97f4a7c15
        z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) * 0x94d049bb133111eb
        z ^ (z >> 31)
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
            let (size, part) =
                if (b < 0x80) {
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
                found.add(finishWord(hash))
                hash = WORD_SEED
                inWord = false
            }
            at += size
        }
    }
    if (inWord) {
        found.add(finishWord(hash))
    }
    FileWords.of(found)
}

/**
 * The hash of the word `name`, as `wordsOf` hashes the words of a text.
 */
func wordHash(name: String): UInt64 {
    var hash = WORD_SEED
    for (b in name.toArray()) {
        hash = mixWord(hash, b)
    }
    finishWord(hash)
}

/**
 * rustc-hash 2's `FxHasher.write_u8`: a word's hash made as its bytes are read, across chunks, with nothing
 * allocated; `finishWord` ends it. Byte by byte, not its `write(&[u8])`, so not the value rustc gives a `str`. Never
 * kept beyond the process, so no hash of std's needs to be stable here; a collision only lets a file through.
 */
@OverflowWrapping
func mixWord(hash: UInt64, b: Byte): UInt64 {
    (hash + UInt64(b)) * 0xf1357aea2e62a9c5
}

/**
 * rustc-hash 2's `FxHasher.finish`: the product's high bits, the best mixed, rotated into the low ones.
 */
func finishWord(hash: UInt64): UInt64 {
    (hash << 26) | (hash >> 38)
}

func isAsciiWordByte(b: Byte): Bool {
    (b >= b'a' && b <= b'z') || (b >= b'A' && b <= b'Z') || (b >= b'0' && b <= b'9') || b == b'_'
}
