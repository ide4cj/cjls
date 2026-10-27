package calca

import std.unittest.*
import std.unittest.testmacro.*
import calca.macros.*

const VERIFY_BENCH_BODIES = 1024

const VERIFY_BENCH_SIGNATURES = 256

const VERIFY_BENCH_CALLS = 48

const VERIFY_BENCH_NAMES = 24

class VerifyBenchState {
    let db = TestDatabase()
    let signatures = SourceFile(db, "signatures.cj", "signatures")
    let edited = SourceFile(db, "edited.cj", "a")
    var edits = 0
}

let VERIFY_BENCH_STATE = VerifyBenchState()

@CalcaTracked
func benchSignature(db: TestDb, at: Int64): Int64 {
    VERIFY_BENCH_STATE.signatures.text(db).size + at
}

/**
 * Reads as many memos and interned values as `loupe`'s `inferBody` of a body does, two to one.
 */
@CalcaTracked
func benchBody(db: TestDb, at: Int64): Int64 {
    var sum = 0
    for (call in 0..VERIFY_BENCH_CALLS) {
        sum += benchSignature(db, (at * 7 + call) % VERIFY_BENCH_SIGNATURES)
    }
    for (name in 0..VERIFY_BENCH_NAMES) {
        sum += Name(db, "n${(at + name) % VERIFY_BENCH_SIGNATURES}").text(db).size
    }
    sum
}

/**
 * Every body fetched again after an input none of them reads changed: each of their memos verified
 * edge by edge, the memos they read verified in this revision already but by the first body to ask,
 * as `loupe`'s bodies of a file after an edit in another. `cjpm bench '--filter=VerifyBench.*'`.
 */
@Test
class VerifyBench {
    @Bench
    func everyBodyAfterAnUnrelatedEdit(): Int64 {
        let state = VERIFY_BENCH_STATE
        state.edits++
        state.edited.setText(state.db).to(if (state.edits % 2 == 0) { "a" } else { "b" })
        var sum = 0
        for (at in 0..VERIFY_BENCH_BODIES) {
            sum += benchBody(state.db, at)
        }
        sum
    }
}
