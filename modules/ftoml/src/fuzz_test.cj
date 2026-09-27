package ftoml

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import std.unittest.prop_test.*

/*
 * Whatever the bytes, `parseToml` either reads them or throws `FtException`: any other exception,
 * or a hang, is a bug. And whatever it reads, `FtWriter` writes so that it reads back the same. The
 * valid documents of toml-test cut short and with bytes dropped, one by one; mutated at random, and
 * random documents written and read back, shrunk to the smallest that fails.
 */

/** The valid documents of the suite. */
let VALID_DOCUMENTS: Array<Array<Byte>> = {
    =>
    // not `TOML_TEST`: a global of another file may not be initialized yet
    let tests = Path("modules/ftoml/testdata/toml-test")
    listed(tests, "1.1.0").filter {name => name.startsWith("valid/") && name.endsWith(".toml")}.map {
        name => File.readFrom(tests.join(name))
    }
}()

/** Whether two values are the same TOML: tables as maps, floats by their bits, NaNs alike. */
func sameValue(a: FtValue, b: FtValue): Bool {
    match ((a.data, b.data)) {
        case (AsTable(x), AsTable(y)) => x.size == y.size && x.iterator().all {
            entry => match (y.get(entry[0])) {
                case Some(other) => sameValue(entry[1], other)
                case None => false
            }
        }
        case (AsArray(x), AsArray(y)) => x.size == y.size && (0..x.size).iterator().all {i => sameValue(x[i], y[i])}
        case (AsString(x), AsString(y)) => x == y
        case (AsInteger(x), AsInteger(y)) => x == y
        case (AsFloat(x), AsFloat(y)) => (x.isNaN() && y.isNaN()) || x.toBits() == y.toBits()
        case (AsBool(x), AsBool(y)) => x == y
        case (AsOffsetDateTime(x), AsOffsetDateTime(y)) => x == y
        case (AsLocalDateTime(x), AsLocalDateTime(y)) => x == y
        case (AsLocalDate(x), AsLocalDate(y)) => x == y
        case (AsLocalTime(x), AsLocalTime(y)) => x == y
        case _ => false
    }
}

/**
 * What went wrong reading `bytes`, `None` when nothing did: they were refused with `FtException`,
 * or read, and what was read written and read back the same.
 */
func misreadOf(bytes: Array<Byte>): ?String {
    let document = try {
        parseToml(bytes)
    } catch (_: FtException) {
        return None
    } catch (e: Exception) {
        return "refused with ${e}"
    }
    try {
        let written = toTomlBytes(document.root)
        if (sameValue(parseToml(written).root, document.root)) {
            None
        } else {
            "written as `${String.fromUtf8(written)}`, which reads otherwise"
        }
    } catch (e: Exception) {
        "read, but written back: ${e}"
    }
}

func shown(bytes: Array<Byte>): String {
    String.fromUtf8(bytes.map {b => if (b < 0x80) { b } else { 0x3F }})
}

@Test
class FtFuzzTest {
    @TestCase
    func everyTruncationOfAValidDocumentReadsOrIsRefused() {
        // arrange
        let failures = ArrayList<String>()

        for (document in VALID_DOCUMENTS) {
            for (end in 0..document.size) {
                // act
                let cut = document[0..end]
                if (let Some(misread) <- misreadOf(cut)) {
                    failures.add("`${shown(cut)}`: ${misread}")
                }
            }
        }

        // assert
        @Expect(failures.toArray(), Array<String>())
    }

    @TestCase
    func everyDocumentWithOneByteDroppedReadsOrIsRefused() {
        // arrange
        let failures = ArrayList<String>()

        for (document in VALID_DOCUMENTS) {
            for (at in 0..document.size) {
                // act
                let dropped = document[0..at].concat(document[at + 1..document.size])
                if (let Some(misread) <- misreadOf(dropped)) {
                    failures.add("`${shown(dropped)}`: ${misread}")
                }
            }
        }

        // assert
        @Expect(failures.toArray(), Array<String>())
    }

    @TestCase
    func keysNestAsDeepAsArraysAndNoDeeper() {
        // arrange
        let deepest = String.join(Array(NESTING_MAX, repeat: "a"), delimiter: ".")
        // an array of tables is a level, and its tables one more
        let deepestArray = String.join(Array(NESTING_MAX - 1, repeat: "a"), delimiter: ".")
        let tooDeep = String.join(Array(100_000, repeat: "a"), delimiter: ".")

        // act, assert
        for (text in ["[${deepest}]\nx = 1\n", "${deepest} = 1\n", "[[${deepestArray}]]\n"]) {
            @Expect(misreadOf(text.toArray()), Option<String>.None)
            @Expect(parseToml(text).root.data.kindName, "a table")
        }
        for (text in ["[${tooDeep}]\n", "${tooDeep} = 1\n", "[[${deepest}]]\n", "[${deepest}]\na = []\n"]) {
            @Expect(errorOf(text).reason, "nested too deep")
        }
    }
}

/** A byte TOML's grammar turns on, or any byte at all. */
let SIGNIFICANT_BYTES: Array<Byte> = "\"'[]{}=.,#\n\r\\ \t0-+:TZe_xtfin".toArray().concat([0x00, 0x7F, 0x80, 0xC3, 0xFF])

/** Bytes dropped, replaced and inserted in one of the suite's valid documents. */
struct Mutation <: Arbitrary<Mutation> & Shrink<Mutation> & ToString {
    Mutation(let document: Int64, let edits: Array<(Int64, Int64, Byte)>) {}

    public static func arbitrary(random: RandomSource): Generator<Mutation> {
        Generators.generate {
            =>
            let document = Int64(random.nextUInt64() % UInt64(VALID_DOCUMENTS.size))
            let count = 1 + Int64(random.nextUInt8() % 6)
            let edits = Array(count) {
                _ =>
                let at = Int64(random.nextUInt64() % 4096)
                let kind = Int64(random.nextUInt8() % 3)
                let b = if (random.nextBool()) {
                    SIGNIFICANT_BYTES[Int64(random.nextUInt64() % UInt64(SIGNIFICANT_BYTES.size))]
                } else {
                    random.nextUInt8()
                }
                (at, kind, b)
            }
            Mutation(document, edits)
        }
    }

    /** The same with one edit fewer. */
    public func shrink(): Iterable<Mutation> {
        (0..edits.size).iterator().map {i => Mutation(document, edits[0..i].concat(edits[i + 1..edits.size]))} |>
            collectArray
    }

    /** The document, edited: `at` wraps around its size; a kind of 0 drops, 1 replaces, 2 inserts. */
    func apply(): Array<Byte> {
        var bytes = VALID_DOCUMENTS[document]
        for ((at, kind, b) in edits) {
            if (bytes.isEmpty()) {
                return [b]
            }
            let i = at % bytes.size
            bytes = match (kind) {
                case 0 => bytes[0..i].concat(bytes[i + 1..bytes.size])
                case 1 => bytes[0..i].concat([b]).concat(bytes[i + 1..bytes.size])
                case _ => bytes[0..i].concat([b]).concat(bytes[i..bytes.size])
            }
        }
        bytes
    }

    public func toString(): String {
        "`${shown(apply())}`"
    }
}

/** A random document: every kind of value, keys that need quoting, strings of any characters. */
struct RandomDocument <: Arbitrary<RandomDocument> & Shrink<RandomDocument> & ToString {
    RandomDocument(let root: FtValue) {}

    public static func arbitrary(random: RandomSource): Generator<RandomDocument> {
        Generators.generate {=> RandomDocument(FtValue(AsTable(randomTable(random, 3)), 0, 0))}
    }

    /** The same with one entry of the root table fewer, or one of its tables emptied. */
    public func shrink(): Iterable<RandomDocument> {
        let table = root.asTable()
        let smaller = ArrayList<RandomDocument>()
        for ((key, _) in table) {
            let without = FtTable(Braced)
            for ((other, value) in table where other != key) {
                without.add(other, value, 0, 0)
            }
            smaller.add(RandomDocument(FtValue(AsTable(without), 0, 0)))
        }
        smaller
    }

    public func toString(): String {
        try {
            "`${toTomlString(root)}`"
        } catch (e: Exception) {
            "unwritable: ${e}"
        }
    }
}

let KEYS: Array<String> = ["a", "b-c", "1", "", "a.b", "é", "q\"", "t t", "_", "\n", "[x]", "#"]

func randomString(random: RandomSource): String {
    let length = Int64(random.nextUInt8() % 6)
    String(Array(length) {_ => random.suggestRune()})
}

func randomTable(random: RandomSource, depth: Int64): FtTable {
    let table = FtTable(Braced)
    for (_ in 0..Int64(random.nextUInt8() % 5)) {
        let key = if (random.nextBool()) {
            KEYS[Int64(random.nextUInt64() % UInt64(KEYS.size))]
        } else {
            randomString(random)
        }
        if (!table.contains(key)) {
            table.add(key, randomValue(random, depth), 0, 0)
        }
    }
    table
}

func randomValue(random: RandomSource, depth: Int64): FtValue {
    let kinds: UInt8 = if (depth > 0) { 10 } else { 8 }
    let data = match (random.nextUInt8() % kinds) {
        case 0 => AsString(randomString(random))
        case 1 => AsInteger(random.suggestInt64())
        case 2 => AsFloat(random.suggestFloat64())
        case 3 => AsBool(random.nextBool())
        case 4 => AsLocalDate(randomDate(random))
        case 5 => AsLocalTime(randomTime(random))
        case 6 => AsLocalDateTime(LocalDateTime(randomDate(random), randomTime(random)))
        case 7 => AsOffsetDateTime(OffsetDateTime(LocalDateTime(randomDate(random), randomTime(random)),
            Int64(random.nextUInt16() % 2879) - 1439))
        case 8 =>
            let array = FtArray(false)
            for (_ in 0..Int64(random.nextUInt8() % 4)) {
                array.items.add(randomValue(random, depth - 1))
            }
            AsArray(array)
        case _ => AsTable(randomTable(random, depth - 1))
    }
    FtValue(data, 0, 0)
}

func randomDate(random: RandomSource): LocalDate {
    let year = Int64(random.nextUInt16() % 10000)
    let month = 1 + Int64(random.nextUInt8() % 12)
    LocalDate(year, month, 1 + Int64(random.nextUInt8()) % daysIn(year, month))
}

func randomTime(random: RandomSource): LocalTime {
    let nanosecond = if (random.nextBool()) { 0 } else { Int64(random.nextUInt32() % 1_000_000_000) }
    LocalTime(Int64(random.nextUInt8() % 24), Int64(random.nextUInt8() % 60), second: Int64(random.nextUInt8() % 61),
        nanosecond: nanosecond)
}

@Test
class FtPropertyTest {
    @TestCase[mutation in random()]
    @Configure[generationSteps: 20000]
    func aMutatedDocumentReadsOrIsRefused(mutation: Mutation): Unit {
        // act, assert
        @Expect(misreadOf(mutation.apply()), Option<String>.None)
    }

    @TestCase[document in random()]
    @Configure[generationSteps: 5000]
    func aDocumentWrittenReadsBackAsItWas(document: RandomDocument): Unit {
        // act
        let written = toTomlBytes(document.root)

        // assert
        @Expect(sameValue(parseToml(written).root, document.root))
    }
}
