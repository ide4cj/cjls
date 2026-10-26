package cjformat

import std.unittest.*
import std.unittest.testmacro.*
import cjsyntax.{CjParse, parse}

let BENCH_FILES =
    [100, 1000, 10000]
        .map {
            n =>
            parse("func f() {\n${"call(firstArgument, secondArgument, thirdArgument)\n" * n}}\n")
        }

/** Pre-parsed files isolate layout and printing from parser costs. */
@Test
class FormatBench {
    @Bench[p in BENCH_FILES]
    func largeFile(p: CjParse): ?Array<TextEdit> {
        format(p)
    }
}

let BENCH_DOCS =
    [100, 1000, 10000]
        .map {
            depth =>
            var doc = textDoc("x")
            for (_ in 0..depth) {
                doc = group(concat([textDoc("a"), softline(), doc]))
            }
            doc
        }

/** Nested groups expose a repeated suffix-measurement regression. */
@Test
class PrinterBench {
    @Bench[doc in BENCH_DOCS]
    func nestedGroups(doc: Doc): String {
        Printer(LINE_WIDTH, "\n").print(doc)
    }
}
