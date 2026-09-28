package ftoml

import std.unittest.*
import std.unittest.testmacro.*

func writtenBy(write: (FtWriter) -> Unit): String {
    let w = FtWriter()
    write(w)
    String.fromUtf8(w.bytes())
}

@Test
class FtWriterTest {
    @TestCase
    func plainKeysGoOnTheirLinesAndTablesUnderHeaders() {
        // act
        let text = writtenBy {
            w =>
            w.beginTable()
            w.key("name")
            w.string("demo")
            w.key("dependencies")
            w.beginTable()
            w.key("fjson")
            w.beginTable()
            w.key("path")
            w.string("../fjson")
            w.endTable()
            w.endTable()
            w.endTable()
        }

        // assert
        @Expect(text, "name = \"demo\"\n\n[dependencies]\n\n[dependencies.fjson]\npath = \"../fjson\"\n")
    }

    @TestCase
    func anArrayOfTablesIsAHeaderPerTable() {
        // act
        let text = writtenBy {
            w =>
            w.beginTable()
            w.key("bin")
            w.beginTableArray()
            for (name in ["a", "b"]) {
                w.beginTable()
                w.key("name")
                w.string(name)
                w.endTable()
            }
            w.endTableArray()
            w.endTable()
        }

        // assert
        @Expect(text, "[[bin]]\nname = \"a\"\n\n[[bin]]\nname = \"b\"\n")
    }

    @TestCase
    func insideAValueTablesAreInline() {
        // act
        let text = writtenBy {
            w =>
            w.beginTable()
            w.key("points")
            w.beginArray()
            w.beginTable()
            w.key("x")
            w.int64(1)
            w.key("tags")
            w.beginTableArray()
            w.beginTable()
            w.endTable()
            w.endTableArray()
            w.endTable()
            w.float64(2.0)
            w.endArray()
            w.endTable()
        }

        // assert
        @Expect(text, "points = [{x = 1, tags = [{}]}, 2.0]\n")
    }

    @TestCase
    func aKeyIsQuotedOnlyWhenItHasToBe() {
        // act
        let text = writtenBy {
            w =>
            w.beginTable()
            w.key("bare-key_1")
            w.bool(true)
            w.key("a.b")
            w.bool(false)
            w.key("")
            w.int64(0)
            w.key("t t")
            w.beginTable()
            w.endTable()
            w.endTable()
        }

        // assert
        @Expect(text, "bare-key_1 = true\n\"a.b\" = false\n\"\" = 0\n\n[\"t t\"]\n")
    }

    @TestCase
    func stringsEscapeControlCharactersAsTomlOneOneDoes() {
        // act
        let text = writtenBy {
            w =>
            w.beginTable()
            w.key("s")
            w.string("q\" b\\ \t\n\u{1B}\u{7F} é")
            w.endTable()
        }

        // assert
        @Expect(text, #"s = "q\" b\\ \t\n\e\x7F é""# + "\n")
    }

    @TestCase
    func floatsAreShortestAndSpelledAsTomlSpellsThem() {
        // act
        let text = writtenBy {
            w =>
            w.beginTable()
            w.key("a")
            w.beginArray()
            for (v in [0.1, 100.0, 1e30, Float64.Inf, -Float64.Inf, Float64.NaN]) {
                w.float64(v)
            }
            w.endArray()
            w.endTable()
        }

        // assert
        @Expect(text, "a = [0.1, 100.0, 1e30, inf, -inf, nan]\n")
    }

    @TestCase
    func aKeyAfterASubTableOfItsTableIsRefused() {
        // act, assert
        @AssertThrows[FtException](writtenBy {
            w =>
            w.beginTable()
            w.key("t")
            w.beginTable()
            w.endTable()
            w.key("x")
            w.int64(1)
        })
    }

    @TestCase
    func aDocumentIsATable() {
        // act, assert
        @AssertThrows[FtException](writtenBy {w => w.int64(1)})
        @AssertThrows[FtException](toTomlBytes(1))
    }

    @TestCase
    func aTableWritesItsPlainKeysBeforeItsTables() {
        // arrange
        let doc = parseToml("t = {x = 1}\nn = 2\ne = []\na = [{y = 3}]\n").root

        // act
        let text = toTomlString(doc)

        // assert
        @Expect(text, "n = 2\ne = []\n\n[t]\nx = 1\n\n[[a]]\ny = 3\n")
    }

    @TestCase
    func whatIsWrittenReadsBackEqual() {
        // arrange
        let text = "s = \"x\"\nd = 1979-05-27T07:32:00Z\nl = 07:32:00.5\n[a.\"b c\"]\nz = [1, [2.5, \"w\"]]\n[[a.q]]\n[[a.q]]\nk = true\n"

        // act
        let written = toTomlString(parseToml(text).root)

        // assert
        @Expect(written, "s = \"x\"\nd = 1979-05-27T07:32:00Z\nl = 07:32:00.5\n\n[a]\n\n[a.\"b c\"]\nz = [1, [2.5, \"w\"]]\n\n[[a.q]]\n\n[[a.q]]\nk = true\n")
        @Expect(toTomlString(parseToml(written).root), written)
    }
}
