package fnum

import std.convert.*
import std.random.Random
import std.unittest.*
import std.unittest.testmacro.*

/*
 * A `Float64` written: Ryu against what `std.convert` offers, `.17g` (round-trips, not the
 * shortest) and `toString()` (six decimals, neither). A thousand values of random bits - long
 * digits, any exponent - and a thousand short ones, `12.34`, as a decimal an editor sends.
 *
 * `cjpm bench '--filter=RyuBench*'`
 */

let RANDOM_FLOATS: Array<Float64> = {
    =>
    let random = Random(7)
    Array<Float64>(1000) {
        _ =>
        var v = Float64.NaN
        while (v.isNaN() || v.isInf()) {
            v = Float64.fromBits(random.nextUInt64())
        }
        v
    }
}()

let SHORT_FLOATS: Array<Float64> = Array<Float64>(1000) {i => Float64(i * 37 % 10000) / 100.0}

var ryuSink = 0

let FLOAT_BUFFER = Array<Byte>(FLOAT64_CHARS_MAX, repeat: 0)

func ryuAll(values: Array<Float64>): Int64 {
    var n = 0
    for (v in values) {
        n += writeShortest(FLOAT_BUFFER, 0, v)
    }
    n
}

func formatAll(values: Array<Float64>, spec: String): Int64 {
    var n = 0
    for (v in values) {
        n += v.format(spec).size
    }
    n
}

func toStringAll(values: Array<Float64>): Int64 {
    var n = 0
    for (v in values) {
        n += v.toString().size
    }
    n
}

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class RyuBench {
    @Bench
    func random1000Ryu(): Unit {
        ryuSink += ryuAll(RANDOM_FLOATS)
    }

    @Bench
    func random1000Format17g(): Unit {
        ryuSink += formatAll(RANDOM_FLOATS, ".17g")
    }

    @Bench
    func random1000ToString(): Unit {
        ryuSink += toStringAll(RANDOM_FLOATS)
    }

    @Bench
    func short1000Ryu(): Unit {
        ryuSink += ryuAll(SHORT_FLOATS)
    }

    @Bench
    func short1000Format17g(): Unit {
        ryuSink += formatAll(SHORT_FLOATS, ".17g")
    }

    @Bench
    func short1000ToString(): Unit {
        ryuSink += toStringAll(SHORT_FLOATS)
    }
}
