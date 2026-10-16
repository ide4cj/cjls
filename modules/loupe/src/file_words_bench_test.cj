package loupe

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import rope.Rope
import cjsyntax.{SyntaxKind, tokenize}
import loupe.fixture.stdSourcesDir
import loupe.vfs.isCangjieFile

/**
 * std's sources, `.corpora/`'s (D65), read once a bench asks: a large workspace's texts.
 */
class StdTexts {
    private var loaded: ?Array<Rope> = None
    private var indexed: ?Array<FileWords> = None

    prop texts: Array<Rope> {
        get() {
            if (let Some(some) <- loaded) {
                return some
            }
            let found = ArrayList<Rope>()
            func walk(at: Path): Unit {
                for (info in Directory.readFrom(at)) {
                    if (info.isDirectory()) {
                        walk(info.path)
                    } else if (info.isRegular() && isCangjieFile(info.name)) {
                        found.add(Rope(String.fromUtf8(File.readFrom(info.path))))
                    }
                }
            }
            walk(stdSourcesDir().filePath.getOrThrow())
            let some = found.toArray()
            loaded = some
            some
        }
    }

    prop words: Array<FileWords> {
        get() {
            if (let Some(some) <- indexed) {
                return some
            }
            let some = texts.map {text => wordsOf(text)}
            indexed = some
            some
        }
    }
}

let stdTexts = StdTexts()

/**
 * What a search of references over std's sources (about 500 files, 6 MB) costs before it reads any file it
 * parses: the words of every file made (`fileWords`, once per file, on the first search), a name looked up in
 * them (every search after), and the identifiers of every file by the lexer, the other way to make them.
 * `cjpm bench --target-dir target/bench '--filter=FileWordsBench.*'`.
 */
@Test
class FileWordsBench {
    @Bench
    func wordsOfEveryFileOfStd(): Int64 {
        let hash = wordHash("size")
        var count = 0
        for (text in stdTexts.texts) {
            if (wordsOf(text).has(hash)) {
                count += 1
            }
        }
        count
    }

    @Bench
    func identifiersOfEveryFileOfStdByTheLexer(): Int64 {
        var count = 0
        for (text in stdTexts.texts) {
            let lexed = tokenize(text.toString())
            let found = HashSet<UInt64>()
            for (i in 0..lexed.size) {
                let kind = lexed.kind(i)
                if (kind == SyntaxKind.Ident || kind == SyntaxKind.DollarIdent || kind.isKeyword()) {
                    found.add(wordHash(lexed.tokenText(i)))
                }
            }
            count += found.size
        }
        count
    }

    @Bench
    func aRareNameLookedUpInTheWordsOfEveryFileOfStd(): Int64 {
        let hash = wordHash("getRawArray")
        stdTexts.words.iterator().filter {words => words.has(hash)}.count()
    }

    @Bench
    func aCommonNameLookedUpInTheWordsOfEveryFileOfStd(): Int64 {
        let hash = wordHash("size")
        stdTexts.words.iterator().filter {words => words.has(hash)}.count()
    }
}
