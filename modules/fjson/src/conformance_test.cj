package fjson

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import std.io.*
import stdx.encoding.json.*
import stdx.encoding.json.stream.*

/*
 * fjson against JSONTestSuite (`testdata/JSONTestSuite`, vendored as it is upstream: its README
 * names the commit), stdx's parser, and bytes a fuzzer would throw at it. Whatever the input, the
 * reader either reads it or throws `FjException`: any other exception, or an error, is a bug.
 */

/** A JSON value read through the pull API, as a decoder would: what the suites are checked on. */
enum Tree {
    | TObject(Array<(String, Tree)>)
    | TArray(Array<Tree>)
    | TString(String)
    | TInt(Int64)
    | TFloat(Float64)
    | TBool(Bool)
    | TNull
}

/** The value at the reader, containers past `MAX_DEPTH` refused as `skipValue` refuses them. */
func readTree(r: FjReader, depth: Int64): Tree {
    match (r.peekKind()) {
        case FjKind.JsonObject | FjKind.JsonArray where depth >= MAX_DEPTH => throw FjException("nested too deep")
        case FjKind.JsonObject =>
            let members = ArrayList<(String, Tree)>()
            r.beginObject()
            while (r.nextKey()) {
                let key = r.key()
                members.add((key, readTree(r, depth + 1)))
            }
            TObject(members.toArray())
        case FjKind.JsonArray =>
            let items = ArrayList<Tree>()
            r.beginArray()
            while (r.nextItem()) {
                items.add(readTree(r, depth + 1))
            }
            TArray(items.toArray())
        case FjKind.JsonString => TString(r.readString())
        case FjKind.JsonBool => TBool(r.readBool())
        case FjKind.JsonNull =>
            r.readNull()
            TNull
        case FjKind.JsonNumber =>
            // as `AnyValue` reads one: an integer while it fits an Int64
            let number = r.rawValue()
            if (number.iterator().any {b => b == 0x2E || b == 0x65 || b == 0x45}) {
                TFloat(FjReader(number).readFloat64())
            } else {
                try {
                    TInt(FjReader(number).readInt64())
                } catch (_: FjException) {
                    TFloat(FjReader(number).readFloat64())
                }
            }
    }
}

func treeOf(bytes: Array<Byte>): Tree {
    let r = FjReader(bytes)
    let tree = readTree(r, 0)
    r.end()
    tree
}

func skipAll(bytes: Array<Byte>): Unit {
    let r = FjReader(bytes)
    r.skipValue()
    r.end()
}

func writeTree(w: FjWriter, tree: Tree): Unit {
    match (tree) {
        case TObject(members) =>
            w.beginObject()
            for ((key, value) in members) {
                w.name(key)
                writeTree(w, value)
            }
            w.endObject()
        case TArray(items) =>
            w.beginArray()
            for (item in items) {
                writeTree(w, item)
            }
            w.endArray()
        case TString(s) => w.string(s)
        case TInt(i) => w.int64(i)
        case TFloat(f) => w.float64(f)
        case TBool(b) => w.bool(b)
        case TNull => w.null()
    }
}

func bytesOf(tree: Tree): Array<Byte> {
    let w = FjWriter()
    writeTree(w, tree)
    w.bytes()
}

/**
 * Whether two floats are at most `ulps` apart: `readFloat64` reads ~0.5% of shortest decimals one
 * ulp off and ~1 in 20 000 two (`-1.9767441860465116`, #31), so a round trip holds to two.
 */
func near(a: Float64, b: Float64, ulps: Int64): Bool {
    if (a == b) {
        return true
    }
    if (a.isNaN() || b.isNaN() || (a < 0.0) != (b < 0.0)) {
        return false
    }
    // of one sign, the bits of floats are in their order
    let (x, y) = (a.toBits(), b.toBits())
    let distance = if (x > y) { x - y } else { y - x }
    distance <= UInt64(ulps)
}

func sameTree(a: Tree, b: Tree, ulps!: Int64 = 0): Bool {
    match ((a, b)) {
        case (TObject(x), TObject(y)) => x.size == y.size &&
            (0..x.size).iterator().all {i => x[i][0] == y[i][0] && sameTree(x[i][1], y[i][1], ulps: ulps)}
        case (TArray(x), TArray(y)) => x.size == y.size &&
            (0..x.size).iterator().all {i => sameTree(x[i], y[i], ulps: ulps)}
        case (TString(x), TString(y)) => x == y
        case (TInt(x), TInt(y)) => x == y
        case (TFloat(x), TFloat(y)) => near(x, y, ulps)
        case (TBool(x), TBool(y)) => x == y
        case (TNull, TNull) => true
        case _ => false
    }
}

func showTree(tree: Tree): String {
    String.fromUtf8(bytesOf(tree))
}

/** How reading `bytes` ends: `None` if it read, the message if it threw `FjException`. */
func refusal(read: () -> Unit): ?String {
    try {
        read()
        None
    } catch (e: FjException) {
        e.message
    }
}

/**
 * Both ways of reading `bytes` — skipping and building a tree — end alike and throw nothing but
 * `FjException`, or else what went wrong; and whether they read it.
 */
func readBothWays(name: String, bytes: Array<Byte>, problems: ArrayList<String>): Bool {
    try {
        let skipped = refusal {skipAll(bytes)}
        let built = refusal {treeOf(bytes)}
        if (skipped.isSome() != built.isSome()) {
            problems.add("${name}: skipped ${skipped ?? "fine"}, but read ${built ?? "fine"}")
        }
        built.isNone()
    } catch (e: Exception) {
        problems.add("${name}: ${e}")
        false
    } catch (e: Error) {
        problems.add("${name}: ${e}")
        false
    }
}

let SUITE = "modules/fjson/testdata/JSONTestSuite"

/** The files of one of the suite's directories whose name starts with `prefix`, and their bytes. */
func corpus(dir: String, prefix!: String = ""): Array<(String, Array<Byte>)> {
    let path = Path(SUITE).join(dir)
    Directory.readFrom(path)
        .filter {info => info.name.startsWith(prefix)}
        .map {info => (info.name, File.readFrom(path.join(info.name)))}
}

func report(problems: ArrayList<String>): String {
    String.join(problems.toArray(), delimiter: "\n")
}

/** The tree stdx's parser reads, in `Tree`'s terms, or `None` if it refuses the bytes. */
func stdxTree(bytes: Array<Byte>): ?Tree {
    try {
        fromStdx(JsonValue.fromStr(String.fromUtf8(bytes)))
    } catch (_: Exception) {
        None
    }
}

/**
 * The tree `stdx.encoding.json.stream`'s pull reader reads, or `None` if it refuses the bytes: the
 * reader like fjson's, over bytes, keys kept in order and repeated.
 */
func stdxStreamTree(bytes: Array<Byte>): ?Tree {
    try {
        let buffer = ByteBuffer()
        buffer.write(bytes)
        let r = JsonReader(buffer)
        let tree = fromStream(r)
        if (r.peek().isSome()) {
            return None
        }
        tree
    } catch (_: Exception) {
        None
    }
}

func fromStream(r: JsonReader): Tree {
    match (r.peek()) {
        case Some(JsonToken.BeginObject) =>
            let members = ArrayList<(String, Tree)>()
            r.startObject()
            while (r.peek() != Some(JsonToken.EndObject)) {
                let key = r.readName()
                members.add((key, fromStream(r)))
            }
            r.endObject()
            TObject(members.toArray())
        case Some(JsonToken.BeginArray) =>
            let items = ArrayList<Tree>()
            r.startArray()
            while (r.peek() != Some(JsonToken.EndArray)) {
                items.add(fromStream(r))
            }
            r.endArray()
            TArray(items.toArray())
        case Some(JsonToken.JsonString) => TString(r.readValue<String>())
        case Some(JsonToken.JsonNumber) => TFloat(r.readValue<Float64>())
        case Some(JsonToken.JsonBool) => TBool(r.readValue<Bool>())
        case Some(JsonToken.JsonNull) =>
            r.readValue<Option<String>>()
            TNull
        case _ => throw Exception("expected a value")
    }
}

/** The tree with every number `0`: what the stream reader is compared on. */
func withoutNumbers(tree: Tree): Tree {
    match (tree) {
        case TObject(members) => TObject(members.map {m => (m[0], withoutNumbers(m[1]))})
        case TArray(items) => TArray(items.map {item => withoutNumbers(item)})
        case TInt(_) | TFloat(_) => TInt(0)
        case _ => tree
    }
}

func fromStdx(value: JsonValue): Tree {
    match (value) {
        case o: JsonObject =>
            let members = ArrayList<(String, Tree)>()
            for ((key, member) in o.getFields()) {
                members.add((key, fromStdx(member)))
            }
            TObject(members.toArray())
        case a: JsonArray => TArray(a.getItems().toArray().map {item => fromStdx(item)})
        case s: JsonString => TString(s.getValue())
        case i: JsonInt => TInt(i.getValue())
        case f: JsonFloat => TFloat(f.getValue())
        case b: JsonBool => TBool(b.getValue())
        case _ => TNull
    }
}

/** An object's members as stdx keeps them: a key once, its last value, in the order of the keys. */
func lastWins(tree: Tree): Tree {
    match (tree) {
        case TObject(members) =>
            let map = HashMap<String, Tree>()
            for ((key, value) in members) {
                map[key] = lastWins(value)
            }
            TObject(map.keys().toArray().map {key => (key, map[key])})
        case TArray(items) => TArray(items.map {item => lastWins(item)})
        case _ => tree
    }
}

func sortedMembers(tree: Tree): Tree {
    match (tree) {
        case TObject(members) =>
            let sorted = ArrayList(members.map {m => (m[0], sortedMembers(m[1]))})
            sorted.sortBy(stable: true) {a, b => a[0].compare(b[0])}
            TObject(sorted.toArray())
        case TArray(items) => TArray(items.map {item => sortedMembers(item)})
        case _ => tree
    }
}

@Test
class JsonTestSuiteTest {
    @TestCase
    func readsEveryValidDocument() {
        // arrange
        let problems = ArrayList<String>()
        let files = corpus("test_parsing", prefix: "y_")

        for ((name, bytes) in files) {
            // act
            let read = readBothWays(name, bytes, problems)

            // assert
            if (!read) {
                problems.add("${name}: refused")
            }
        }
        @Expect(files.size, 95)
        @Expect(report(problems), "")
    }

    @TestCase
    func refusesEveryInvalidDocumentWithFjException() {
        // arrange
        let problems = ArrayList<String>()
        let files = corpus("test_parsing", prefix: "n_")

        for ((name, bytes) in files) {
            // act
            let read = readBothWays(name, bytes, problems)

            // assert
            if (read) {
                problems.add("${name}: read")
            }
        }
        @Expect(files.size, 188)
        @Expect(report(problems), "")
    }

    /**
     * What JSON leaves to the parser: a number past Float64 is read (±Inf, or 0 below it), 500
     * nested arrays are, and so is a lone surrogate (as U+FFFD). What is not UTF-8 is not: a BOM,
     * UTF-16, invalid UTF-8 and an encoded surrogate — LSP is UTF-8, without a BOM.
     */
    @TestCase
    func decidesTheImplementationDefinedOnesAsPinned() {
        // arrange
        let refused = [
            "i_string_UTF-16LE_with_BOM.json",
            "i_string_UTF-8_invalid_sequence.json",
            "i_string_UTF8_surrogate_U+D800.json",
            "i_string_invalid_utf-8.json",
            "i_string_iso_latin_1.json",
            "i_string_lone_utf8_continuation_byte.json",
            "i_string_not_in_unicode_range.json",
            "i_string_overlong_sequence_2_bytes.json",
            "i_string_overlong_sequence_6_bytes.json",
            "i_string_overlong_sequence_6_bytes_null.json",
            "i_string_truncated-utf-8.json",
            "i_string_utf16BE_no_BOM.json",
            "i_string_utf16LE_no_BOM.json",
            "i_structure_UTF-8_BOM_empty_object.json"
        ]
        let problems = ArrayList<String>()
        let files = corpus("test_parsing", prefix: "i_")

        for ((name, bytes) in files) {
            // act
            let read = readBothWays(name, bytes, problems)

            // assert
            if (read == refused.contains(name)) {
                problems.add("${name}: ${if (read) { "read" } else { "refused" }}")
            }
        }
        @Expect(files.size, 35)
        @Expect(report(problems), "")
    }

    /** A document both read is the same tree to both, but for what stdx does not keep: key order, repeated keys. */
    @TestCase
    func readsWhatStdxReadsAsStdxReadsIt() {
        // arrange
        let problems = ArrayList<String>()
        var compared = 0

        for ((name, bytes) in corpus("test_parsing")) {
            let theirs = stdxTree(bytes) ?? continue
            let ours = try {
                treeOf(bytes)
            } catch (_: FjException) {
                continue
            }
            compared++

            // act
            let expected = sortedMembers(theirs)
            let actual = sortedMembers(lastWins(ours))

            // assert
            if (!sameTree(actual, expected)) {
                problems.add("${name}: ${showTree(actual)}, stdx ${showTree(expected)}")
            }
        }
        @Expect(compared >= 95, true)
        @Expect(report(problems), "")
    }

    /**
     * A document both read is the same tree to `stdx.encoding.json.stream`'s pull reader, numbers
     * aside: it reads them several ulps off (`1.23e47` as `1.2300000000000002e47`), where fjson
     * reads what a correctly rounding parser does. Where the two disagree on reading at all, fjson
     * holds to the suite's verdict and the stream reader does not: it takes trailing commas,
     * leading zeros and raw control characters, and refuses `1E+2` and 500 nested arrays.
     */
    @TestCase
    func readsWhatTheStdxStreamReaderReadsAsItReadsIt() {
        // arrange
        let problems = ArrayList<String>()
        var compared = 0

        for ((name, bytes) in corpus("test_parsing").concat(corpus("test_transform"))) {
            let theirs = stdxStreamTree(bytes) ?? continue
            let ours = try {
                treeOf(bytes)
            } catch (_: FjException) {
                continue
            }
            compared++

            // act
            let expected = withoutNumbers(theirs)
            let actual = withoutNumbers(ours)

            // assert
            if (!sameTree(actual, expected)) {
                problems.add("${name}: ${showTree(ours)}, stdx stream ${showTree(theirs)}")
            }
        }
        @Expect(compared >= 80, true)
        @Expect(report(problems), "")
    }

    @TestCase
    func writesWhatItReadsSoThatItReadsBackTheSame() {
        // arrange
        let problems = ArrayList<String>()

        for ((name, bytes) in corpus("test_parsing", prefix: "y_")) {
            let tree = treeOf(bytes)

            // act
            let again = treeOf(bytesOf(tree))

            // assert
            if (!sameTree(again, tree, ulps: 1)) {
                problems.add("${name}: ${showTree(tree)} read back as ${showTree(again)}")
            }
        }
        @Expect(report(problems), "")
    }

    /** `test_transform`: numbers and strings at the edges, and keys repeated or normalized apart. */
    @TestCase
    func readsTheEdgesAsPinned() {
        // arrange
        let expected: Array<(String, ?Tree)> = [
            ("number_-9223372036854775808.json", TArray([TInt(Int64.Min)])),
            ("number_-9223372036854775809.json", TArray([TFloat(-9223372036854775808.0)])),
            ("number_1.0.json", TArray([TFloat(1.0)])),
            ("number_1.000000000000000005.json", TArray([TFloat(1.0)])),
            ("number_1000000000000000.json", TArray([TInt(1000000000000000)])),
            ("number_10000000000000000999.json", TArray([TFloat(1e19)])),
            ("number_1e-999.json", TArray([TFloat(0.0)])),
            ("number_1e6.json", TArray([TFloat(1e6)])),
            ("number_9223372036854775807.json", TArray([TInt(Int64.Max)])),
            ("number_9223372036854775808.json", TArray([TFloat(9223372036854775808.0)])),
            // keys are bytes: no normalization, and a repeated key is the decoder's (a map keeps the last)
            ("object_key_nfc_nfd.json", TObject([("\u{E9}", TString("NFC")), ("e\u{301}", TString("NFD"))])),
            ("object_key_nfd_nfc.json", TObject([("e\u{301}", TString("NFD")), ("\u{E9}", TString("NFC"))])),
            ("object_same_key_different_values.json", TObject([("a", TInt(1)), ("a", TInt(2))])),
            ("object_same_key_same_value.json", TObject([("a", TInt(1)), ("a", TInt(1))])),
            ("object_same_key_unclear_values.json", TObject([("a", TInt(0)), ("a", TInt(0))])),
            ("string_1_escaped_invalid_codepoint.json", TArray([TString("\u{FFFD}")])),
            ("string_2_escaped_invalid_codepoints.json", TArray([TString("\u{FFFD}\u{FFFD}")])),
            ("string_3_escaped_invalid_codepoints.json", TArray([TString("\u{FFFD}\u{FFFD}\u{FFFD}")])),
            ("string_1_invalid_codepoint.json", None),
            ("string_2_invalid_codepoints.json", None),
            ("string_3_invalid_codepoints.json", None),
            ("string_with_escaped_NULL.json", TArray([TString("A\u{0}B")]))
        ]
        let files = HashMap<String, Array<Byte>>(corpus("test_transform"))
        @Expect(files.size, expected.size)

        for ((name, tree) in expected) {
            // act
            let actual: ?Tree = try {
                treeOf(files[name])
            } catch (_: FjException) {
                None
            }

            // assert
            let same = match ((actual, tree)) {
                case (Some(a), Some(e)) => sameTree(a, e)
                case (None, None) => true
                case _ => false
            }
            @Expect(same, true)
            if (!same) {
                @Expect(name, actual.map(showTree) ?? "refused")
            }
        }
    }
}

@Test
class FjFuzzTest {
    let bytesTried: Array<Byte> = [
        0x00, 0x09, 0x0A, 0x20, 0x22, 0x2C, 0x2D, 0x2E, 0x30, 0x31, 0x3A, 0x45, 0x5B, 0x5C, 0x5D, 0x65, 0x66,
        0x6E, 0x74, 0x75, 0x7B, 0x7D, 0x7F, 0x80, 0xBF, 0xC0, 0xC3, 0xED, 0xF0, 0xF4, 0xFF
    ]

    func documents(): Array<(String, Array<Byte>)> {
        corpus("test_parsing", prefix: "y_")
            .filter {file => file[1].size <= 4096}
            .concat(corpus("test_parsing", prefix: "i_"))
    }

    @TestCase
    func everyTruncationIsReadOrRefusedAlike() {
        // arrange
        let problems = ArrayList<String>()

        for ((name, bytes) in documents()) {
            for (length in 0..bytes.size) {
                // act, assert
                readBothWays("${name}[..${length}]", bytes[0..length], problems)
            }
        }
        @Expect(report(problems), "")
    }

    @TestCase
    func everyByteReplacedOrDroppedIsReadOrRefusedAlike() {
        // arrange
        let problems = ArrayList<String>()

        for ((name, bytes) in documents()) {
            for (at in 0..bytes.size) {
                let dropped = bytes[0..at].concat(bytes[at + 1..])
                // act, assert
                readBothWays("${name} without byte ${at}", dropped, problems)
                for (b in bytesTried) {
                    let replaced = bytes.clone()
                    replaced[at] = b
                    readBothWays("${name} with ${b} at ${at}", replaced, problems)
                }
            }
        }
        @Expect(report(problems), "")
    }

    @TestCase
    func readsContainersNestedToTheLimitAndRefusesDeeperOnes() {
        for ((open, close, inner) in [("[", "]", "1"), ("[", "]", ""), (#"{"a":"#, "}", "1"), (#"{"a":"#, "}", "{}")]) {
            for (depth in [MAX_DEPTH - 1, MAX_DEPTH, MAX_DEPTH + 1, 100_000]) {
                // arrange - `{}` inside is one container more
                let containers = depth + if (inner == "{}") { 1 } else { 0 }
                let text = open * depth + inner + close * depth
                let bytes = text.toArray()
                let problems = ArrayList<String>()

                // act
                let read = readBothWays("${depth} × ${open}${inner}", bytes, problems)
                let raw = refusal {FjReader(bytes).rawValue()}

                // assert
                @Expect(report(problems), "")
                @Expect(read, containers <= MAX_DEPTH)
                @Expect(raw.isNone(), containers <= MAX_DEPTH)
            }
        }
    }

    /** `Float64.parse` behind `readFloat64`, on what a number may be and no Float64 is. */
    @TestCase
    func readsNumbersOfHugeExponentsOrManyDigits() {
        // arrange
        let expected: Array<(String, Float64)> = [
            ("1e99999999999999999999", Float64.Inf),
            ("-1e99999999999999999999", -Float64.Inf),
            ("1e-99999999999999999999", 0.0),
            ("0.${"0" * 5000}1", 0.0),
            ("1${"0" * 400}", Float64.Inf),
            ("${"1" * 5000}.5e-4990", 1.1111111111111112e9),
            ("123456789012345678901234567890", 1.2345678901234568e29)
        ]

        for ((text, value) in expected) {
            // act
            let actual = try {
                "${reader(text).readFloat64()}"
            } catch (e: Exception) {
                "${e}"
            }

            // assert
            @Expect(actual, "${value}")
        }
    }

}
