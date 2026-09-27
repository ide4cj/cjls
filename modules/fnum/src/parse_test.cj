package fnum

import std.math.numeric.BigInt
import std.random.Random
import std.unittest.*
import std.unittest.testmacro.*

/** Whether `text` reads as the one `Float64` it rounds to, checked exactly against `roundsTo`. */
func readsCorrectly(text: String): Bool {
    let value = parseFloat64(text)
    let (digits, exponent) = decimalOf(text)
    if (digits == BigInt(0)) {
        return value == 0.0
    }
    roundsTo(digits, exponent, Float64.fromBits(value.toBits() & 0x7FFF_FFFF_FFFF_FFFF))
}

/** A random decimal of `count` digits, the point anywhere, and an exponent up to `spread`. */
func randomDecimal(random: Random, count: Int64, spread: Int64): String {
    let digits = StringBuilder()
    digits.append(Rune(UInt32(0x31 + random.nextUInt8(9))))
    for (_ in 1..count) {
        digits.append(Rune(UInt32(0x30 + random.nextUInt8(10))))
    }
    let text = digits.toString()
    let point = random.nextInt64(count) + 1
    let exponent = random.nextInt64(2 * spread + 1) - spread
    let fraction = if (point < count) { "." + text[point..count] } else { "" }
    "${text[0..point]}${fraction}e${exponent}"
}

@Test
class ParseFloat64Test {
    @TestCase
    func readsTheNearestFloat() {
        // act, assert
        @Expect(parseFloat64("0.1"), 0.1)
        @Expect(parseFloat64("-2.5e100"), -2.5e100)
        @Expect(parseFloat64("1e23"), 1e23)
        @Expect(parseFloat64("1.7976931348623157e308"), Float64.Max)
        @Expect(parseFloat64("5e-324").toBits(), 1)
        @Expect(parseFloat64("2.2250738585072011e-308").toBits(), 0x000F_FFFF_FFFF_FFFF)
        @Expect(parseFloat64("26110439075397.418").toBits(), 4807521475180250475)
    }

    @TestCase
    func aHalfwayValueGoesToTheEvenNeighbour() {
        // act, assert: 2^53 + 1 and 2^53 + 3 lie halfway between two floats
        @Expect(parseFloat64("9007199254740993"), 9007199254740992.0)
        @Expect(parseFloat64("9007199254740995"), 9007199254740996.0)
        // one digit past halfway, far beyond the 19 Eisel-Lemire reads, decides it
        @Expect(parseFloat64("9007199254740993.0000000000000000000000000001"), 9007199254740994.0)
        @Expect(parseFloat64("9007199254740993.0000000000000000000000000000"), 9007199254740992.0)
    }

    @TestCase
    func beyondTheRangeIsInfinityOrZero() {
        // act, assert
        @Expect(parseFloat64("1e309"), Float64.Inf)
        @Expect(parseFloat64("-1e99999999999999999999"), -Float64.Inf)
        @Expect(parseFloat64("1e-400"), 0.0)
        @Expect(parseFloat64("-1e-400").toBits(), 0x8000_0000_0000_0000)
        @Expect(parseFloat64("2.4703282292062328e-324").toBits(), 1)
        @Expect(parseFloat64("2.4703282292062327e-324").toBits(), 0)
    }

    @TestCase
    func zeroKeepsItsSign() {
        // act, assert
        @Expect(parseFloat64("0").toBits(), 0)
        @Expect(parseFloat64("-0.0").toBits(), 0x8000_0000_0000_0000)
        @Expect(parseFloat64("+0e10").toBits(), 0)
        @Expect(parseFloat64("0.000e-5").toBits(), 0)
    }

    @TestCase
    func underscoresAreSkipped() {
        // act, assert
        @Expect(parseFloat64("224_617.445_991_228"), 224617.445991228)
        @Expect(parseFloat64("1e1_0"), 1e10)
    }

    @TestCase
    func whatIsNotADecimalIsRefused() {
        // act, assert
        for (text in ["", "-", ".5", "5.", "1e", "1e+", "1.2.3", "1x", "0x10", "inf", "nan", " 1"]) {
            @AssertThrows[IllegalArgumentException](parseFloat64(text))
        }
    }

    @TestCase
    func theShortestDecimalOfEveryValueReadsBackAsIt() {
        // arrange
        let random = Random(20260927)

        for (_ in 0..20000) {
            let value = Float64.fromBits(random.nextUInt64() & 0x7FFF_FFFF_FFFF_FFFF)
            if (value.isNaN() || value.isInf()) {
                continue
            }

            // act, assert
            @Assert(parseFloat64(formatShortest(value)).toBits(), value.toBits())
        }
    }

    @TestCase
    func everyDecimalReadsAsTheFloatItRoundsTo() {
        // arrange
        let random = Random(7)

        for (i in 0..20000) {
            // short and long mantissas, exponents to the ends of the range and past them
            let count = if (i % 4 == 0) { 17 + random.nextInt64(40) } else { 1 + random.nextInt64(19) }
            let text = randomDecimal(random, count, 330)

            // act, assert
            let value = parseFloat64(text)
            if (value.isInf() || value == 0.0) {
                continue
            }
            @Assert(readsCorrectly(text))
        }
    }

    @TestCase
    func decimalsNextToAHalfwayPointReadCorrectly() {
        // arrange: the midpoint between a value and the next one, then a hair either side of it
        let random = Random(11)

        for (_ in 0..2000) {
            let value = Float64.fromBits(random.nextUInt64() & 0x7FEF_FFFF_FFFF_FFFF)
            if (value.isNaN() || value.isInf() || value == 0.0) {
                continue
            }
            let bits = value.toBits()
            let ieeeExponent = Int64((bits >> 52) & 0x7FF)
            let (m2, e2) = if (ieeeExponent == 0) {
                (bits & 0x000F_FFFF_FFFF_FFFF, -1074)
            } else {
                ((bits & 0x000F_FFFF_FFFF_FFFF) | 0x0010_0000_0000_0000, ieeeExponent - 1075)
            }
            // (2 * m2 + 1) * 2^(e2 - 1), exactly, as a decimal: times 5^n / 10^n when e2 - 1 < 0
            let (digits, exponent) = if (e2 - 1 >= 0) {
                (BigInt(Int64(2 * m2 + 1)) * pow(2, e2 - 1), 0)
            } else {
                (BigInt(Int64(2 * m2 + 1)) * pow(5, 1 - e2), e2 - 1)
            }
            for (text in ["${digits}e${exponent}", "${digits}1e${exponent - 1}", "${digits - BigInt(1)}9e${exponent - 1}"]) {
                // act, assert
                @Assert(readsCorrectly(text))
            }
        }
    }
}
