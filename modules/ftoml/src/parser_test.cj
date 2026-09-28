package ftoml

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import fjson.*

func errorOf(bytes: Array<Byte>): FtException {
    try {
        parseToml(bytes)
    } catch (e: FtException) {
        return e
    }
    throw AssertException("read `${String.fromUtf8(bytes)}` without an error")
}

func errorOf(text: String): FtException {
    errorOf(text.toArray())
}

func keysOf(table: FtTable): Array<String> {
    let keys = ArrayList<String>()
    for ((key, _) in table) {
        keys.add(key)
    }
    keys.toArray()
}

func textAt(text: String, start: Int64, end: Int64): String {
    String.fromUtf8(text.toArray()[start..end])
}

@Test
class FtParserTest {
    @TestCase
    func tablesKeepTheOrderTheirKeysWereFirstMet() {
        // arrange
        let text = "b = 1\na = 2\n[c]\nz = 3\n[d]\n[c.y]\n"

        // act
        let root = parseToml(text).table

        // assert
        @Expect(keysOf(root), ["b", "a", "c", "d"])
        @Expect(keysOf(root.get("c").getOrThrow().asTable()), ["z", "y"])
    }

    @TestCase
    func aValueKnowsTheBytesItWasReadFrom() {
        // arrange
        let text = "name = \"demo\" # the package\n[deps]\nfjson = { path = \"../fjson\" }\n"

        // act
        let root = parseToml(text).table
        let name = root.get("name").getOrThrow()
        let deps = root.get("deps").getOrThrow()
        let fjson = deps.asTable().get("fjson").getOrThrow()

        // assert
        @Expect(textAt(text, name.start, name.end), "\"demo\"")
        @Expect(textAt(text, deps.start, deps.end), "[deps]")
        @Expect(textAt(text, fjson.start, fjson.end), "{ path = \"../fjson\" }")
        let (keyStart, keyEnd) = deps.asTable().keySpan("fjson").getOrThrow()
        @Expect(textAt(text, keyStart, keyEnd), "fjson")
    }

    @TestCase
    func aTableAHeaderDefinesLaterIsPlacedAtThatHeader() {
        // arrange
        let text = "[a.b]\n[a]\n"

        // act
        let a = parseToml(text).table.get("a").getOrThrow()

        // assert
        @Expect(textAt(text, a.start, a.end), "[a]")
    }

    @TestCase
    func anErrorIsPlacedByLineAndColumn() {
        // act
        let e = errorOf("a = 1\nb = \"é\" c = 2\n")

        // assert: the column counts characters, not bytes
        @Expect(e.line, 2)
        @Expect(e.column, 9)
        @Expect(e.offset, 15)
        @Expect(e.reason, "expected a newline or the end of the document")
        @Expect(e.message, "expected a newline or the end of the document at line 2, column 9")
    }

    @TestCase
    func aKeyDefinedTwiceIsReportedAtItsSecondDefinition() {
        // act
        let e = errorOf("[t]\nx = 1\nx.y = 2\n")

        // assert
        @Expect(e.line, 3)
        @Expect(e.column, 1)
        @Expect(e.reason, "`x` is already an integer")
    }

    @TestCase
    func whatDottedKeysDefinedAHeaderCannotDefineAgain() {
        // act, assert
        @Expect(errorOf("[a]\nb.c = 1\n[a.b]\n").reason, "table `a.b` is defined twice")
        // a header may add a table under them, though
        @Expect(parseToml("[a]\nb.c = 1\n[a.b.d]\ne = 2\n").table.get("a").getOrThrow().asTable().size, 1)
    }

    @TestCase
    func stringsReadAsTheirFourFormsSay() {
        // arrange
        let text = String.join([
            #"basic = "tab\there \u00E9 \U0001F600 \x41\e""#,
            #"literal = 'C:\Users\'"#,
            #"multi = """"#,
            #"one \"#,
            #"   two"""""#,
            "raw = '''",
            "it's '' here'''"
        ], delimiter: "\n")

        // act
        let root = parseToml(text).table

        // assert
        @Expect(root.get("basic").getOrThrow().asString(), "tab\there é 😀 A\u{1B}")
        @Expect(root.get("literal").getOrThrow().asString(), #"C:\Users\"#)
        @Expect(root.get("multi").getOrThrow().asString(), "one two\"")
        @Expect(root.get("raw").getOrThrow().asString(), "it's '' here")
    }

    @TestCase
    func numbersReadInEveryBase() {
        // arrange
        let text = "a = 0xDEAD_beef\nb = 0o755\nc = 0b1010\nd = -9_223_372_036_854_775_808\ne = 6.626e-34\nf = -inf\n"

        // act
        let root = parseToml(text).table

        // assert
        @Expect(root.get("a").getOrThrow().asInteger(), 0xDEADBEEF)
        @Expect(root.get("b").getOrThrow().asInteger(), 493)
        @Expect(root.get("c").getOrThrow().asInteger(), 10)
        @Expect(root.get("d").getOrThrow().asInteger(), Int64.Min)
        @Expect(root.get("e").getOrThrow().asFloat(), 6.626e-34)
        @Expect(root.get("f").getOrThrow().asFloat(), -Float64.Inf)
    }

    @TestCase
    func anIntegerPastSixtyFourBitsIsAnError() {
        // act, assert
        @Expect(errorOf("a = 9223372036854775808").reason, "an integer out of the range of 64 bits")
        @Expect(errorOf("a = 0x8000000000000000").reason, "an integer out of the range of 64 bits")
    }

    @TestCase
    func inlineTablesSpanLinesAndTakeATrailingComma() {
        // arrange: TOML 1.1
        let text = "t = {\n  a = 1, # one\n  b.c = 2,\n}\n"

        // act
        let t = parseToml(text).table.get("t").getOrThrow().asTable()

        // assert
        @Expect(t.get("a").getOrThrow().asInteger(), 1)
        @Expect(t.get("b").getOrThrow().asTable().get("c").getOrThrow().asInteger(), 2)
    }

    @TestCase
    func anInlineTableIsCompleteAsWritten() {
        // act, assert
        @Expect(errorOf("t = {}\n[t.u]\n").reason, "`t` is an inline table, complete as written")
        @Expect(errorOf("t = {}\nt.u = 1\n").reason, "`t` is a table defined elsewhere")
    }

    @TestCase
    func aHeaderOfATableArrayAddsToItsLastElement() {
        // arrange
        let text = "[[f]]\nn = 1\n[f.p]\nc = 2\n[[f]]\nn = 3\n"

        // act
        let f = parseToml(text).table.get("f").getOrThrow().asArray()

        // assert
        @Expect(f.size, 2)
        @Expect(f[0].asTable().get("p").getOrThrow().asTable().get("c").getOrThrow().asInteger(), 2)
        @Expect(f[1].asTable().get("n").getOrThrow().asInteger(), 3)
        @Expect(errorOf("a = []\n[[a]]\n").reason, "`a` is an array written as a value, complete as written")
    }

    @TestCase
    func datesAndTimesReadInEachOfTheirKinds() {
        // arrange
        let text = "a = 1979-05-27T07:32:00.999999999999-07:00\nb = 1979-05-27 07:32\nc = 2000-02-29\nd = 07:32\n"

        // act
        let root = parseToml(text).table

        // assert
        @Expect(describe(root.get("a").getOrThrow().data), "datetime 1979-05-27T07:32:00.999999999-07:00")
        @Expect(describe(root.get("b").getOrThrow().data), "datetime-local 1979-05-27T07:32:00")
        @Expect(describe(root.get("c").getOrThrow().data), "date-local 2000-02-29")
        @Expect(describe(root.get("d").getOrThrow().data), "time-local 07:32:00")
        @Expect(errorOf("a = 2001-02-29").reason, "no such date")
    }

    @TestCase
    func aByteOrderMarkIsNoPartOfTheText() {
        // act
        let bom: Array<Byte> = [0xEF, 0xBB, 0xBF]
        let root = parseToml(bom.concat("a = 1".toArray())).table

        // assert
        @Expect(root.get("a").getOrThrow().asInteger(), 1)
    }

    @TestCase
    func invalidUtf8IsAnError() {
        // act, assert
        let overlong: Array<Byte> = [0xC0, 0xAF]
        @Expect(errorOf("a = \"x".toArray().concat(overlong).concat("\"".toArray())).reason, "invalid UTF-8")
    }

    @TestCase
    func nestingIsBounded() {
        // act, assert
        @Expect(errorOf("a = " + "[" * 100_000).reason, "nested too deep")
        @Expect(errorOf("a = " + "{b = " * 100_000).reason, "nested too deep")
    }

    @TestCase
    func theComparisonWithTheSuiteNoticesADifference() {
        // arrange
        let expected = Json.read(FjReader(#"{"a": {"type": "integer", "value": "2"}}"#.toArray()))

        // act
        let difference = differenceOf(parseToml("a = 1").root, expected, "doc")

        // assert
        @Expect(difference, Some("doc.a: read as integer 1, expected integer 2"))
    }
}

@Test
class FtDateTimeTest {
    @TestCase
    func eachIsWrittenAsRfc3339() {
        // act, assert
        @Expect(LocalDate(1979, 5, 27).toString(), "1979-05-27")
        @Expect(LocalTime(7, 32, second: 0, nanosecond: 500_000_000).toString(), "07:32:00.5")
        @Expect(LocalDateTime(LocalDate(1979, 5, 27), LocalTime(0, 32)).toString(), "1979-05-27T00:32:00")
        @Expect(OffsetDateTime(LocalDateTime(LocalDate(1979, 5, 27), LocalTime(0, 32)), -420).toString(),
            "1979-05-27T00:32:00-07:00")
        @Expect(OffsetDateTime(LocalDateTime(LocalDate(1979, 5, 27), LocalTime(7, 32)), 0).toString(),
            "1979-05-27T07:32:00Z")
    }

    @TestCase
    func whatIsNoDayOrTimeCannotBeMade() {
        // act, assert
        @AssertThrows[IllegalArgumentException](LocalDate(2023, 2, 29))
        @AssertThrows[IllegalArgumentException](LocalTime(24, 0))
        @AssertThrows[IllegalArgumentException](LocalTime.parse("07:32:"))
    }
}
