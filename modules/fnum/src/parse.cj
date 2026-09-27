package fnum

import std.math.numeric.BigInt

/*
 * A decimal read as the nearest `Float64`, ties to even - what `std.convert`'s `Float64.parse` does
 * not do (it reads ~0.5% of shortest decimals one ulp off, Q20). Three paths, as Go's `strconv`:
 * Clinger's exact one for short mantissas and small exponents, Eisel-Lemire (Go's
 * `eisel_lemire.go`, after Lemire's fast_float) for nearly everything else, and exact arithmetic
 * on `BigInt`s for what it cannot decide - halfway cases, subnormals, more than 19 digits whose
 * truncation matters.
 */

const MANTISSA_DIGITS_MAX: Int64 = 19
// past it, an exponent only decides between zero and infinity: the digits cannot bring it back
const EXPONENT_CLAMP: Int64 = 1_000_000
const FLOAT64_INF_BITS: UInt64 = 0x7FF0_0000_0000_0000
const FLOAT64_SIGN_BIT: UInt64 = 0x8000_0000_0000_0000
const MANTISSA_MASK: UInt64 = 0x000F_FFFF_FFFF_FFFF

/** `10^e` for 0 <= e <= 22, every one exact in a `Float64`. */
let POW10_EXACT: Array<Float64> = [1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14,
    1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22]

/**
 * `bytes[from..to]` as the nearest `Float64`, ties to even: `[+-]? digits ('.' digits)? ([eE]
 * [+-]? digits)?`, a `_` anywhere among the digits skipped - where TOML lets one stand is its
 * reader's to check. Too large a value is an infinity, too small a zero, of its sign.
 *
 * @throws IllegalArgumentException - if the bytes are not of that form
 */
public func parseFloat64(bytes: Array<Byte>, from: Int64, to: Int64): Float64 {
    let decimal = Decimal.read(bytes, from, to)
    let bits = decimal.toBits(bytes)
    Float64.fromBits(if (decimal.negative) { bits | FLOAT64_SIGN_BIT } else { bits })
}

/** `text` as the nearest `Float64`: `parseFloat64` over its bytes. */
public func parseFloat64(text: String): Float64 {
    let bytes = unsafe { text.rawData() }
    parseFloat64(bytes, 0, bytes.size)
}

/**
 * A decimal as its first 19 significant digits and a power of ten, and where its digits lie, for
 * the exact path to read them all again.
 */
struct Decimal {
    Decimal(
        let negative!: Bool,
        let mantissa!: UInt64,
        let exponent!: Int64,
        let truncated!: Bool,
        let digitsFrom!: Int64,
        let digitsTo!: Int64,
        let explicitExponent!: Int64
    ) {}

    static func read(bytes: Array<Byte>, from: Int64, to: Int64): Decimal {
        func invalid(): IllegalArgumentException {
            IllegalArgumentException("not a decimal: ${String.fromUtf8(bytes[from..to])}")
        }
        var i = from
        var negative = false
        if (i < to && (bytes[i] == 0x2D || bytes[i] == 0x2B)) {
            negative = bytes[i] == 0x2D
            i++
        }
        let digitsFrom = i
        var mantissa: UInt64 = 0
        var taken = 0
        var exponent: Int64 = 0
        var truncated = false
        var integerDigits = 0
        var fractionDigits = 0
        var afterPoint = false
        while (i < to) {
            let b = bytes[i]
            if (b >= 0x30 && b <= 0x39) {
                let d = UInt64(b - 0x30)
                if (afterPoint) {
                    fractionDigits++
                } else {
                    integerDigits++
                }
                if (mantissa == 0 && d == 0) {
                    // a leading zero: a place after the point, nothing before it
                    if (afterPoint) {
                        exponent--
                    }
                } else if (taken < MANTISSA_DIGITS_MAX) {
                    mantissa = mantissa * 10 + d
                    taken++
                    if (afterPoint) {
                        exponent--
                    }
                } else {
                    truncated = truncated || d != 0
                    if (!afterPoint) {
                        exponent++
                    }
                }
            } else if (b == 0x5F) {
                // `_`, placed by the caller's grammar
                ()
            } else if (b == 0x2E && !afterPoint) {
                afterPoint = true
            } else {
                break
            }
            i++
        }
        if (integerDigits == 0 || (afterPoint && fractionDigits == 0)) {
            throw invalid()
        }
        let digitsTo = i

        var explicitExponent: Int64 = 0
        if (i < to && (bytes[i] == 0x65 || bytes[i] == 0x45)) {
            i++
            var exponentNegative = false
            if (i < to && (bytes[i] == 0x2D || bytes[i] == 0x2B)) {
                exponentNegative = bytes[i] == 0x2D
                i++
            }
            var exponentDigits = 0
            while (i < to && ((bytes[i] >= 0x30 && bytes[i] <= 0x39) || bytes[i] == 0x5F)) {
                if (bytes[i] != 0x5F) {
                    exponentDigits++
                    if (explicitExponent < EXPONENT_CLAMP) {
                        explicitExponent = explicitExponent * 10 + Int64(bytes[i] - 0x30)
                    }
                }
                i++
            }
            if (exponentDigits == 0) {
                throw invalid()
            }
            if (exponentNegative) {
                explicitExponent = -explicitExponent
            }
        }
        if (i != to) {
            throw invalid()
        }

        Decimal(
            negative: negative,
            mantissa: mantissa,
            exponent: exponent + explicitExponent,
            truncated: truncated,
            digitsFrom: digitsFrom,
            digitsTo: digitsTo,
            explicitExponent: explicitExponent
        )
    }

    /** The bits of the nearest `Float64` to the decimal's magnitude. */
    func toBits(bytes: Array<Byte>): UInt64 {
        if (mantissa == 0) {
            return 0
        }
        if (!truncated && mantissa <= (1 << 53) && exponent >= -22 && exponent <= 22) {
            // both exact, so one rounding: the product's or the quotient's
            let m = Float64(mantissa)
            let value = if (exponent < 0) { m / POW10_EXACT[-exponent] } else { m * POW10_EXACT[exponent] }
            return value.toBits()
        }
        if (let Some(bits) <- eiselLemire(mantissa, exponent)) {
            // a truncated mantissa lies between the digits taken and the next: both have to agree
            if (!truncated) {
                return bits
            }
            if (let Some(up) <- eiselLemire(mantissa + 1, exponent)) {
                if (up == bits) {
                    return bits
                }
            }
        }
        exactBits(bytes)
    }

    /** Every digit, exactly: the value as a fraction of `BigInt`s, divided to 53 bits and rounded. */
    func exactBits(bytes: Array<Byte>): UInt64 {
        let digits = StringBuilder()
        var fractionDigits = 0
        var afterPoint = false
        for (i in digitsFrom..digitsTo) {
            let b = bytes[i]
            if (b == 0x2E) {
                afterPoint = true
            } else if (b != 0x5F) {
                if (afterPoint) {
                    fractionDigits++
                }
                // a leading zero changes nothing of the digits as an integer
                if (digits.size > 0 || b != 0x30) {
                    digits.append(Rune(b))
                }
            }
        }
        let text = digits.toString().trimEnd("0")
        let trailingZeros = digits.size - text.size
        let count = text.size
        // value = text * 10^e
        let e = explicitExponent - fractionDigits + trailingZeros
        // 10^(count - 1 + e) <= value < 10^(count + e)
        if (count - 1 + e > 309) {
            return FLOAT64_INF_BITS
        }
        if (count + e < -324) {
            // below 10^-325, under half the least subnormal (~2.47e-324)
            return 0
        }

        var num = BigInt.parse(text, radix: 10)
        var den = BigInt(1)
        if (e >= 0) {
            num = num * BigInt(10) ** UInt64(e)
        } else {
            den = BigInt(10) ** UInt64(-e)
        }
        // q = num / (den * 2^k), in [2^52, 2^53) unless subnormal
        var k = num.bitLen - den.bitLen - 53
        if (k < -1074) {
            k = -1074
        }
        let two52 = BigInt(1) << 52
        let two53 = BigInt(1) << 53
        var q = BigInt(0)
        var r = BigInt(0)
        var d = BigInt(0)
        while (true) {
            let (scaledNum, scaledDen) = if (k < 0) { (num << -k, den) } else { (num, den << k) }
            q = scaledNum / scaledDen
            r = scaledNum % scaledDen
            d = scaledDen
            if (q >= two53) {
                k++
            } else if (q < two52 && k > -1074) {
                k--
            } else {
                break
            }
        }
        let twice = r << 1
        let order = twice.compare(d)
        if (order == Ordering.GT || (order == Ordering.EQ && q % BigInt(2) == BigInt(1))) {
            q = q + BigInt(1)
            if (q == two53) {
                q = two52
                k++
            }
        }
        if (k + 52 > 1023) {
            return FLOAT64_INF_BITS
        }
        let m = q.toUInt64()
        if (m < (1 << 52)) {
            // subnormal, k is -1074
            return m
        }
        (UInt64(k + 52 + 1023) << 52) | (m & MANTISSA_MASK)
    }
}

func leadingZeros(value: UInt64): Int64 {
    var n = 0
    var v = value
    if ((v >> 32) == 0) {
        n += 32
        v <<= 32
    }
    if ((v >> 48) == 0) {
        n += 16
        v <<= 16
    }
    if ((v >> 56) == 0) {
        n += 8
        v <<= 8
    }
    if ((v >> 60) == 0) {
        n += 4
        v <<= 4
    }
    if ((v >> 62) == 0) {
        n += 2
        v <<= 2
    }
    if ((v >> 63) == 0) {
        n += 1
    }
    n
}

/**
 * The bits of `mantissa * 10^exp10`, mantissa non-zero, or `None` when 128 bits of the power of
 * ten cannot decide the rounding, or the result is subnormal or infinite: Go's `eiselLemire64`.
 */
@OverflowWrapping
func eiselLemire(mantissa: UInt64, exp10: Int64): ?UInt64 {
    if (exp10 < POW10_MIN_EXP10 || exp10 > POW10_MAX_EXP10) {
        return None
    }
    // normalization
    let clz = leadingZeros(mantissa)
    let man = mantissa << UInt64(clz)
    var retExp2 = ((217706 * exp10) >> 16) + 64 + 1023 - clz

    // multiplication
    let index = (exp10 - POW10_MIN_EXP10) * 2
    var (xHi, xLo) = umul128(man, POW10_128[index + 1])

    // wider approximation
    if ((xHi & 0x1FF) == 0x1FF && xLo + man < man) {
        let (yHi, yLo) = umul128(man, POW10_128[index])
        var mergedHi = xHi
        let mergedLo = xLo + yHi
        if (mergedLo < xLo) {
            mergedHi++
        }
        if ((mergedHi & 0x1FF) == 0x1FF && mergedLo + 1 == 0 && yLo + man < man) {
            return None
        }
        xHi = mergedHi
        xLo = mergedLo
    }

    // shifting to 54 bits
    let msb = xHi >> 63
    var retMantissa = xHi >> (msb + 9)
    retExp2 -= Int64(1 ^ msb)

    // half-way ambiguity
    if (xLo == 0 && (xHi & 0x1FF) == 0 && (retMantissa & 3) == 1) {
        return None
    }

    // from 54 to 53 bits
    retMantissa += retMantissa & 1
    retMantissa >>= 1
    if ((retMantissa >> 53) > 0) {
        retMantissa >>= 1
        retExp2 += 1
    }
    if (retExp2 <= 0 || retExp2 >= 0x7FF) {
        return None
    }
    (UInt64(retExp2) << 52) | (retMantissa & MANTISSA_MASK)
}
