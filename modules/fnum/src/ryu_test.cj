package fnum

import std.convert.*
import std.math.numeric.BigInt
import std.random.Random
import std.unittest.*
import std.unittest.testmacro.*

func shortest(value: Float64): String {
    formatShortest(value)
}

/** `text`, a decimal, as `digits * 10^exponent`, sign dropped. */
func decimalOf(text: String): (BigInt, Int64) {
    let parts = text.removePrefix("-").split("e")
    let exponent = if (parts.size > 1) {
        Int64.parse(parts[1].replace("+", ""))
    } else {
        0
    }
    let pointed = parts[0].split(".")
    let fraction = if (pointed.size > 1) {
        pointed[1]
    } else {
        ""
    }
    (BigInt(pointed[0] + fraction), exponent - fraction.size)
}

func pow(base: Int64, exponent: Int64): BigInt {
    var result = BigInt(1)
    for (_ in 0..exponent) {
        result = result * BigInt(base)
    }
    result
}

/**
 * Whether `digits * 10^exponent` rounds to the positive, finite `value`: whether it lies in the
 * interval of reals that read as it, its ends included when its mantissa is even. Exact, in
 * `BigInt`s - `Float64.parse` is no oracle: it reads ~0.5% of shortest decimals one ulp off.
 */
func roundsTo(digits: BigInt, exponent: Int64, value: Float64): Bool {
    let bits = value.toBits()
    let ieeeMantissa = bits & 0x000F_FFFF_FFFF_FFFF
    let ieeeExponent = Int64((bits >> 52) & 0x7FF)
    let (m2, e2) = if (ieeeExponent == 0) {
        (ieeeMantissa, -1074)
    } else {
        (ieeeMantissa | 0x0010_0000_0000_0000, ieeeExponent - 1075)
    }
    // the ends in units of 2^(e2 - 2); the lower one closer when the mantissa is a power of two
    let upper = BigInt(Int64(4 * m2 + 2))
    let lower = if (ieeeMantissa == 0 && ieeeExponent > 1) {
        BigInt(Int64(4 * m2 - 1))
    } else {
        BigInt(Int64(4 * m2 - 2))
    }
    let scaledDecimal = digits * pow(10, max(exponent, 0)) * pow(2, max(2 - e2, 0))
    let scale = pow(10, max(-exponent, 0)) * pow(2, max(e2 - 2, 0))
    let (low, high) = (lower * scale, upper * scale)
    if (m2 % 2 == 0) {
        low <= scaledDecimal && scaledDecimal <= high
    } else {
        low < scaledDecimal && scaledDecimal < high
    }
}

func significantDigits(digits: BigInt): Int64 {
    digits.toString().trimEnd("0").size
}

@Test
class RyuTest {
    @TestCase
    func writesTheShortestDecimalAsSerdeJsonDoes() {
        // act, assert
        @Expect(shortest(0.1), "0.1")
        @Expect(shortest(0.1 + 0.2), "0.30000000000000004")
        @Expect(shortest(100.0), "100.0")
        @Expect(shortest(-0.0), "-0.0")
        @Expect(shortest(0.0), "0.0")
        @Expect(shortest(123456.789), "123456.789")
        @Expect(shortest(1e15), "1000000000000000.0")
        @Expect(shortest(1e16), "1e16")
        @Expect(shortest(1e21), "1e21")
        @Expect(shortest(0.00001), "0.00001")
        @Expect(shortest(0.000001), "1e-6")
        @Expect(shortest(1.2345e-7), "1.2345e-7")
        @Expect(shortest(-2.5e100), "-2.5e100")
        @Expect(shortest(Float64.Max), "1.7976931348623157e308")
        @Expect(shortest(Float64.fromBits(1)), "5e-324")
        @Expect(shortest(Float64.fromBits(0x000F_FFFF_FFFF_FFFF)), "2.225073858507201e-308")
        @Expect(shortest(Float64.fromBits(4807521475180250475)), "26110439075397.418")
    }

    @TestCase
    func refusesWhatHasNoDecimal() {
        // act, assert
        @AssertThrows[IllegalArgumentException](formatShortest(Float64.NaN))
        @AssertThrows[IllegalArgumentException](formatShortest(-Float64.Inf))
    }

    @TestCase
    func everyFiniteValueIsWrittenInTheFewestDigitsThatReadBackAsIt() {
        // arrange
        let random = Random(20260927)

        for (_ in 0..20000) {
            let value = Float64.fromBits(random.nextUInt64() & 0x7FFF_FFFF_FFFF_FFFF)
            if (value.isNaN() || value.isInf() || value == 0.0) {
                continue
            }

            // act
            let (digits, exponent) = decimalOf(shortest(value))

            // assert
            @Assert(roundsTo(digits, exponent, value))
            let n = significantDigits(digits)
            if (n > 1) {
                // the nearest decimal of one digit fewer, and its neighbours, all read as another value
                let (nearest, at) = decimalOf(value.format(".${n - 2}e"))
                for (candidate in [nearest - BigInt(1), nearest, nearest + BigInt(1)]) {
                    @Assert(!roundsTo(candidate, at, value))
                }
            }
        }
    }
}
