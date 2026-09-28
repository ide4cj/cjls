package fnum

import std.convert.*
import std.unittest.*
import std.unittest.testmacro.*

/*
 * A decimal read: `parseFloat64` against `std.convert`'s `Float64.parse`, which is not correctly
 * rounded. The shortest decimals of the values `RyuBench` writes, long and short.
 *
 * `cjpm bench '--filter=ParseFloat64Bench*'`
 */

let RANDOM_DECIMALS: Array<String> = RANDOM_FLOATS.map {v => formatShortest(v)}

let SHORT_DECIMALS: Array<String> = SHORT_FLOATS.map {v => formatShortest(v)}

var parseSink = 0.0

func parseAll(texts: Array<String>): Float64 {
    var sum = 0.0
    for (text in texts) {
        sum += parseFloat64(text)
    }
    sum
}

func stdParseAll(texts: Array<String>): Float64 {
    var sum = 0.0
    for (text in texts) {
        sum += Float64.parse(text)
    }
    sum
}

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class ParseFloat64Bench {
    @Bench
    func random1000ParseFloat64(): Unit {
        parseSink += parseAll(RANDOM_DECIMALS)
    }

    @Bench
    func random1000StdParse(): Unit {
        parseSink += stdParseAll(RANDOM_DECIMALS)
    }

    @Bench
    func short1000ParseFloat64(): Unit {
        parseSink += parseAll(SHORT_DECIMALS)
    }

    @Bench
    func short1000StdParse(): Unit {
        parseSink += stdParseAll(SHORT_DECIMALS)
    }
}
