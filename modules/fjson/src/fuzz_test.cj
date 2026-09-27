package fjson

import std.collection.*
import std.convert.*
import std.unittest.*
import std.unittest.testmacro.*
import std.unittest.prop_test.*

/*
 * What a fuzzer finds: values std.unittest generates and shrinks, and bytes it mutates, guided by
 * the comparisons the reader makes when fjson is built with `--fuzz` (D24). The exhaustive ones,
 * every truncation and every byte replaced, are `FjFuzzTest`'s.
 */
extend Tree <: ToString {
    public func toString(): String {
        showTree(this)
    }
}

/** Values of every kind, up to 4 containers deep, their numbers and characters biased to the edges. */
extend Tree <: Arbitrary<Tree> {
    public static func arbitrary(random: RandomSource): Generator<Tree> {
        Generators.generate {generateTree(random, 0)}
    }
}

/** A tree shrinks to `null`, to one of its children, to one child fewer, or to a child or a leaf shrunk. */
extend Tree <: Shrink<Tree> {
    public func shrink(): Iterable<Tree> {
        let smaller = ArrayList<Tree>()
        match (this) {
            case TNull => return smaller
            case _ => smaller.add(TNull)
        }
        match (this) {
            case TObject(members) =>
                smaller.add(all: members.map {m => m[1]})
                for (i in 0..members.size) {
                    smaller.add(TObject(without(members, i)))
                }
                for (i in 0..members.size) {
                    let (key, value) = members[i]
                    for (k in shrinkString(key)) {
                        smaller.add(TObject(replaced(members, i, (k, value))))
                    }
                    for (v in value.shrink()) {
                        smaller.add(TObject(replaced(members, i, (key, v))))
                    }
                }
            case TArray(items) =>
                smaller.add(all: items)
                for (i in 0..items.size) {
                    smaller.add(TArray(without(items, i)))
                }
                for (i in 0..items.size) {
                    for (v in items[i].shrink()) {
                        smaller.add(TArray(replaced(items, i, v)))
                    }
                }
            case TString(s) => smaller.add(all: shrinkString(s).map {t => TString(t)})
            case TInt(i) where i != 0 => smaller.add(all: [TInt(0), TInt(i / 2)])
            case TFloat(f) where f != 0.0 => smaller.add(all: [TFloat(0.0), TFloat(f / 2.0)])
            case TBool(true) => smaller.add(TBool(false))
            case _ => ()
        }
        smaller
    }
}

func without<T>(items: Array<T>, at: Int64): Array<T> {
    items[0..at].concat(items[at + 1..])
}

func replaced<T>(items: Array<T>, at: Int64, item: T): Array<T> {
    let copy = items.clone()
    copy[at] = item
    copy
}

/** Shorter strings, the characters in them kept: the one without each character, and the halves. */
func shrinkString(s: String): Array<String> {
    let runes = s.toRuneArray()
    if (runes.size == 0) {
        return []
    }
    let halves = [String(runes[0..runes.size / 2]), String(runes[runes.size / 2..])]
    halves.concat(Array(runes.size) {i => String(without(runes, i))})
}

func generateTree(random: RandomSource, depth: Int64): Tree {
    let choice = if (depth >= 4) {
        2 + random.nextInt64(5)
    } else {
        random.nextInt64(7)
    }
    match (choice) {
        case 0 => TObject(Array(random.nextInt64(5)) {_ => (generateString(random), generateTree(random, depth + 1))})
        case 1 => TArray(Array(random.nextInt64(5)) {_ => generateTree(random, depth + 1)})
        case 2 => TString(generateString(random))
        case 3 => TInt(random.suggestInt64())
        case 4 => TFloat(generateFloat(random))
        case 5 => TBool(random.nextBool())
        case _ => TNull
    }
}

/** Characters from every range the reader and the writer treat apart: control, escaped, ASCII, 2, 3 and 4 bytes. */
func generateString(random: RandomSource): String {
    let runes = Array(random.nextInt64(12)) {
        _: Int64 =>
            let cp: UInt32 = match (random.nextInt64(7)) {
                case 0 => random.nextUInt32(0x20)
                case 1 => [0x22u32, 0x5Cu32, 0x2Fu32, 0x7Fu32][random.nextInt64(4)]
                case 2 => 0x20 + random.nextUInt32(0x60)
                case 3 => 0x80 + random.nextUInt32(0x780)
                case 4 =>
                    let c = 0x800 + random.nextUInt32(0xF800)
                    if (c >= 0xD800 && c <= 0xDFFF) {
                        0xFFFDu32
                    } else {
                        c
                    }
                case 5 => 0x10000 + random.nextUInt32(0x100000)
                case _ => UInt32(random.suggestRune())
            }
            Rune(cp)
    }
    String(runes)
}

/** A finite float, half of them the edge values `suggestFloat64` picks. */
func generateFloat(random: RandomSource): Float64 {
    while (true) {
        let f = if (random.nextBool()) {
            random.suggestFloat64()
        } else {
            Float64.fromBits(random.nextUInt64())
        }
        if (!f.isNaN() && !f.isInf()) {
            return f
        }
    }
    0.0
}

@Test
@Configure[randomSeed: 42, generationSteps: 500]
class TreePropertyTest {
    /** The writer escapes what it has to, and the reader undoes it; stdx reads it as the same value. */
    @TestCase[tree in random()]
    func writesValuesThatReadBackAsThemselves(tree: Tree) {
        // act
        let bytes = bytesOf(tree)
        let again = treeOf(bytes)

        // assert
        @Expect(sameTree(again, tree, ulps: 2), true)
        let theirs = stdxTree(bytes)
        @Expect(theirs.isSome(), true)
        if (let Some(t) <- theirs) {
            @Expect(sameTree(sortedMembers(t), sortedMembers(lastWins(tree)), ulps: 2), true)
        }
    }
}

/** The documents a mutant starts from: the suite's `y_` and `i_` ones, those under 4 KB. */
let FUZZ_SEEDS: Array<Array<Byte>> = corpus("test_parsing", prefix: "y_")
    .concat(corpus("test_parsing", prefix: "i_"))
    .map {file => file[1]}
    .filter {bytes => bytes.size <= 4096}

/**
 * A document of the suite with a few edits: bytes dropped, inserted, replaced, a run of them
 * repeated, or the rest cut off. Under the coverage-guided fuzzer, the draws that make it are
 * mutated towards the comparisons the reader makes.
 */
struct Mutant <: ToString {
    Mutant(let bytes: Array<Byte>) {}

    public func toString(): String {
        let text = StringBuilder()
        for (b in bytes) {
            if (b >= 0x20 && b < 0x7F && b != 0x5C) {
                text.append(Rune(b))
            } else {
                text.append("\\x${b.format("02x")}")
            }
        }
        text.toString()
    }
}

extend Mutant <: Arbitrary<Mutant> {
    public static func arbitrary(random: RandomSource): Generator<Mutant> {
        Generators.generate {mutate(FUZZ_SEEDS[random.nextInt64(FUZZ_SEEDS.size)], random)}
    }
}

extend Mutant <: Shrink<Mutant> {
    public func shrink(): Iterable<Mutant> {
        bytes.shrink() |> map {b: Array<Byte> => Mutant(b)}
    }
}

func mutate(seed: Array<Byte>, random: RandomSource): Mutant {
    let bytes = ArrayList(seed)
    for (_ in 0..1 + random.nextInt64(4)) {
        let at = random.nextInt64(bytes.size + 1)
        match (random.nextInt64(5)) {
            case 0 where at < bytes.size => bytes.remove(at: at)
            case 1 => bytes.add(random.suggestUInt8(), at: at)
            case 2 where at < bytes.size => bytes[at] = random.suggestUInt8()
            case 3 where at < bytes.size =>
                let run = bytes[at..min(bytes.size, at + 1 + random.nextInt64(8))].toArray()
                bytes.add(all: run, at: at)
            case 4 => bytes.remove(at..bytes.size)
            case _ => ()
        }
    }
    Mutant(bytes.toArray())
}

@Test
@Configure[randomSeed: 42, coverageGuided: true, generationSteps: 20000]
class FjCoverageGuidedFuzzTest {
    /** Whatever the bytes, both ways of reading them end alike, in the value or in `FjException`. */
    @TestCase[mutant in random()]
    func readsOrRefusesMutatedDocumentsAlike(mutant: Mutant) {
        // arrange
        let problems = ArrayList<String>()

        // act
        readBothWays("${mutant}", mutant.bytes, problems)

        // assert
        @Expect(report(problems), "")
    }
}
