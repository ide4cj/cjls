package fjson

/*
 * The shortest decimal that reads back as the same `Float64`: Ryu (Ulf Adams, PLDI 2018), its
 * `ryu/d2s.c` ported, laid out as the Rust `ryu` crate lays it out for serde_json - `0.1`,
 * `100.0`, `1e21`, `1.2345e-7`. An integral value keeps its `.0`, so what reads it back as any
 * JSON (`AnyValue`) still has a float. `std.convert`'s `.17g` round-trips too, but writes
 * `0.10000000000000001`, and slower (`FjsonFloatBench`).
 *
 * The arithmetic is C's: unsigned and wrapping, hence `@OverflowWrapping` on every function that
 * computes.
 */

const DOUBLE_MANTISSA_BITS: Int64 = 52
const DOUBLE_EXPONENT_MASK: UInt64 = 0x7FF
const DOUBLE_BIAS: Int64 = 1023

/** The most `writeShortest` writes: a sign, 17 digits, a point, `e-` and three exponent digits. */
const FLOAT64_CHARS_MAX: Int64 = 25

// floor(log10(2^e)) for 0 <= e <= 1650
func log10Pow2(e: Int64): Int64 {
    (e * 78913) >> 18
}

// floor(log10(5^e)) for 0 <= e <= 2620
func log10Pow5(e: Int64): Int64 {
    (e * 732923) >> 20
}

// ceil(log2(5^e)), 1 for e = 0, for 0 <= e <= 3528
func pow5bits(e: Int64): Int64 {
    ((e * 1217359) >> 19) + 1
}

@OverflowWrapping
func pow5Factor(value: UInt64): Int64 {
    // 5 * M_INV_5 = 1 (mod 2^64), and N_DIV_5 = 2^64 / 5: a multiple of 5 times M_INV_5 is at most it
    var v = value
    var count = 0
    while (true) {
        v = v * 14757395258967641293
        if (v > 3689348814741910323) {
            return count
        }
        count++
    }
    count
}

func multipleOfPowerOf5(value: UInt64, p: Int64): Bool {
    pow5Factor(value) >= p
}

func multipleOfPowerOf2(value: UInt64, p: Int64): Bool {
    (value & ((1 << UInt64(p)) - 1)) == 0
}

/** The high 64 bits of `a * b`, and the low: in 32-bit halves, as Cangjie has no 128-bit integer. */
@OverflowWrapping
func umul128(a: UInt64, b: UInt64): (UInt64, UInt64) {
    let aLo = a & 0xFFFF_FFFF
    let aHi = a >> 32
    let bLo = b & 0xFFFF_FFFF
    let bHi = b >> 32
    let b00 = aLo * bLo
    let b01 = aLo * bHi
    let b10 = aHi * bLo
    let b11 = aHi * bHi
    let mid1 = b10 + (b00 >> 32)
    let mid2 = b01 + (mid1 & 0xFFFF_FFFF)
    let hi = b11 + (mid1 >> 32) + (mid2 >> 32)
    let lo = (mid2 << 32) | (b00 & 0xFFFF_FFFF)
    (hi, lo)
}

/** `(m * mul) >> j`, `mul` being a table entry of 128 bits and `j` at least 64. */
@OverflowWrapping
func mulShift64(m: UInt64, mulLo: UInt64, mulHi: UInt64, j: Int64): UInt64 {
    let (high1, low1) = umul128(m, mulHi)
    let (high0, _) = umul128(m, mulLo)
    let sum = high0 + low1
    let high = if (sum < high0) {
        high1 + 1
    } else {
        high1
    }
    let dist = UInt64(j - 64)
    (high << (64 - dist)) | (sum >> dist)
}

/** Ryu's step 2 to 4: the shortest `mantissa * 10^exponent` in the interval that rounds to the value. */
@OverflowWrapping
func d2d(ieeeMantissa: UInt64, ieeeExponent: Int64): (UInt64, Int64) {
    // two more bits, for the bounds
    let (e2, m2) = if (ieeeExponent == 0) {
        (1 - DOUBLE_BIAS - DOUBLE_MANTISSA_BITS - 2, ieeeMantissa)
    } else {
        (ieeeExponent - DOUBLE_BIAS - DOUBLE_MANTISSA_BITS - 2, (1 << UInt64(DOUBLE_MANTISSA_BITS)) | ieeeMantissa)
    }
    let acceptBounds = (m2 & 1) == 0

    let mv = 4 * m2
    let mmShift: UInt64 = if (ieeeMantissa != 0 || ieeeExponent <= 1) {
        1
    } else {
        0
    }

    var vr: UInt64 = 0
    var vp: UInt64 = 0
    var vm: UInt64 = 0
    var e10: Int64 = 0
    var vmIsTrailingZeros = false
    var vrIsTrailingZeros = false
    if (e2 >= 0) {
        let q = log10Pow2(e2) - if (e2 > 3) {
            1
        } else {
            0
        }
        e10 = q
        let k = RYU_POW5_INV_BITCOUNT + pow5bits(q) - 1
        let i = -e2 + q + k
        let mulLo = RYU_POW5_INV_SPLIT[2 * q]
        let mulHi = RYU_POW5_INV_SPLIT[2 * q + 1]
        vr = mulShift64(4 * m2, mulLo, mulHi, i)
        vp = mulShift64(4 * m2 + 2, mulLo, mulHi, i)
        vm = mulShift64(4 * m2 - 1 - mmShift, mulLo, mulHi, i)
        if (q <= 21) {
            // only one of mp, mv and mm can be a multiple of 5, if any
            if (mv % 5 == 0) {
                vrIsTrailingZeros = multipleOfPowerOf5(mv, q)
            } else if (acceptBounds) {
                vmIsTrailingZeros = multipleOfPowerOf5(mv - 1 - mmShift, q)
            } else if (multipleOfPowerOf5(mv + 2, q)) {
                vp--
            }
        }
    } else {
        let q = log10Pow5(-e2) - if (-e2 > 1) {
            1
        } else {
            0
        }
        e10 = q + e2
        let i = -e2 - q
        let k = pow5bits(i) - RYU_POW5_BITCOUNT
        let j = q - k
        let mulLo = RYU_POW5_SPLIT[2 * i]
        let mulHi = RYU_POW5_SPLIT[2 * i + 1]
        vr = mulShift64(4 * m2, mulLo, mulHi, j)
        vp = mulShift64(4 * m2 + 2, mulLo, mulHi, j)
        vm = mulShift64(4 * m2 - 1 - mmShift, mulLo, mulHi, j)
        if (q <= 1) {
            // mv = 4 * m2 has at least two trailing 0 bits
            vrIsTrailingZeros = true
            if (acceptBounds) {
                // mm = mv - 1 - mmShift has one iff mmShift is 1
                vmIsTrailingZeros = mmShift == 1
            } else {
                // mp = mv + 2 has at least one
                vp--
            }
        } else if (q < 63) {
            vrIsTrailingZeros = multipleOfPowerOf2(mv, q)
        }
    }

    var removed: Int64 = 0
    var lastRemovedDigit: UInt64 = 0
    let output: UInt64
    if (vmIsTrailingZeros || vrIsTrailingZeros) {
        // the general case, ~0.7% of values
        while (vp / 10 > vm / 10) {
            vmIsTrailingZeros = vmIsTrailingZeros && vm % 10 == 0
            vrIsTrailingZeros = vrIsTrailingZeros && lastRemovedDigit == 0
            lastRemovedDigit = vr % 10
            vr /= 10
            vp /= 10
            vm /= 10
            removed++
        }
        if (vmIsTrailingZeros) {
            while (vm % 10 == 0) {
                vrIsTrailingZeros = vrIsTrailingZeros && lastRemovedDigit == 0
                lastRemovedDigit = vr % 10
                vr /= 10
                vp /= 10
                vm /= 10
                removed++
            }
        }
        if (vrIsTrailingZeros && lastRemovedDigit == 5 && vr % 2 == 0) {
            // round to even when the exact value is ...50..0
            lastRemovedDigit = 4
        }
        // vr + 1 if vr is outside the bounds or has to round up
        let up = (vr == vm && (!acceptBounds || !vmIsTrailingZeros)) || lastRemovedDigit >= 5
        output = if (up) {
            vr + 1
        } else {
            vr
        }
    } else {
        // the common case
        var roundUp = false
        if (vp / 100 > vm / 100) {
            // two digits at a time, ~86% of values
            roundUp = vr % 100 >= 50
            vr /= 100
            vp /= 100
            vm /= 100
            removed += 2
        }
        while (vp / 10 > vm / 10) {
            roundUp = vr % 10 >= 5
            vr /= 10
            vp /= 10
            vm /= 10
            removed++
        }
        output = if (vr == vm || roundUp) {
            vr + 1
        } else {
            vr
        }
    }
    (output, e10 + removed)
}

func decimalLength17(v: UInt64): Int64 {
    var length = 1
    var bound: UInt64 = 10
    while (length < 17 && v >= bound) {
        length++
        bound *= 10
    }
    length
}

/** `v`'s digits, the last at `end - 1`. */
@OverflowWrapping
func writeDigits(buf: Array<Byte>, end: Int64, v: UInt64): Unit {
    var rest = v
    var i = end - 1
    while (rest >= 10) {
        buf[i] = UInt8(rest % 10) + 0x30
        rest /= 10
        i--
    }
    buf[i] = UInt8(rest) + 0x30
}

func writeExponent(buf: Array<Byte>, at: Int64, e: Int64): Int64 {
    var i = at
    var magnitude = e
    if (e < 0) {
        buf[i] = 0x2D
        i++
        magnitude = -e
    }
    let length = if (magnitude >= 100) {
        3
    } else if (magnitude >= 10) {
        2
    } else {
        1
    }
    writeDigits(buf, i + length, UInt64(magnitude))
    i + length
}

/**
 * The shortest decimal of the finite `value` at `buf[at..]`, which has room for
 * `FLOAT64_CHARS_MAX` bytes; the index past it.
 */
@OverflowWrapping
func writeShortest(buf: Array<Byte>, at: Int64, value: Float64): Int64 {
    let bits = value.toBits()
    var i = at
    if ((bits >> 63) != 0) {
        buf[i] = 0x2D
        i++
    }
    let ieeeMantissa = bits & ((1 << UInt64(DOUBLE_MANTISSA_BITS)) - 1)
    let ieeeExponent = Int64((bits >> UInt64(DOUBLE_MANTISSA_BITS)) & DOUBLE_EXPONENT_MASK)
    if (ieeeExponent == 0 && ieeeMantissa == 0) {
        buf[i] = 0x30
        buf[i + 1] = 0x2E
        buf[i + 2] = 0x30
        return i + 3
    }

    let (output, exponent) = smallInteger(ieeeMantissa, ieeeExponent) ?? d2d(ieeeMantissa, ieeeExponent)
    let length = decimalLength17(output)
    // 10^(kk - 1) <= value < 10^kk
    let kk = length + exponent
    if (exponent >= 0 && kk <= 16) {
        // 1234e7 -> 12340000000.0
        writeDigits(buf, i + length, output)
        for (z in i + length..i + kk) {
            buf[z] = 0x30
        }
        buf[i + kk] = 0x2E
        buf[i + kk + 1] = 0x30
        i + kk + 2
    } else if (0 < kk && kk <= 16) {
        // 1234e-2 -> 12.34
        writeDigits(buf, i + length + 1, output)
        buf.copyTo(buf, i + 1, i, kk)
        buf[i + kk] = 0x2E
        i + length + 1
    } else if (-5 < kk && kk <= 0) {
        // 1234e-6 -> 0.001234
        buf[i] = 0x30
        buf[i + 1] = 0x2E
        let offset = 2 - kk
        for (z in i + 2..i + offset) {
            buf[z] = 0x30
        }
        writeDigits(buf, i + offset + length, output)
        i + offset + length
    } else if (length == 1) {
        // 1e30
        buf[i] = UInt8(output) + 0x30
        buf[i + 1] = 0x65
        writeExponent(buf, i + 2, kk - 1)
    } else {
        // 1234e30 -> 1.234e33
        writeDigits(buf, i + length + 1, output)
        buf[i] = buf[i + 1]
        buf[i + 1] = 0x2E
        buf[i + length + 1] = 0x65
        writeExponent(buf, i + length + 2, kk - 1)
    }
}

/** An integer in [1, 2^53) as itself, no Ryu needed: its trailing zeros stay in the mantissa. */
func smallInteger(ieeeMantissa: UInt64, ieeeExponent: Int64): ?(UInt64, Int64) {
    let m2 = (1 << UInt64(DOUBLE_MANTISSA_BITS)) | ieeeMantissa
    let e2 = ieeeExponent - DOUBLE_BIAS - DOUBLE_MANTISSA_BITS
    if (e2 > 0 || e2 < -52) {
        return None
    }
    let mask = (UInt64(1) << UInt64(-e2)) - 1
    if ((m2 & mask) != 0) {
        return None
    }
    (m2 >> UInt64(-e2), 0)
}
