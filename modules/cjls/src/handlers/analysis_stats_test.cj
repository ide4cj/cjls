package cjls.handlers

import std.unittest.*
import std.unittest.testmacro.*
import fjson.RawJson
import rope.Encoding
import cjls.server.*

@Test
class AnalysisStatsTest {
    let file = "func twice(n: Int64): Int64 { n * 2 }\nfunc f() {\n    twice(1)\n}\n"

    @TestCase
    func aRequestAnsweredFromWhatTheAnalysisRememberedExecutesNoQuery() {
        // arrange
        let (state, dir) = loaded([("a.cj", file)])
        let before = handleAnalysisStats(state.snapshot(), ()).queriesExecuted
        hoverOf(state, dir.join("a.cj"), 2, 6)
        let first = handleAnalysisStats(state.snapshot(), ()).queriesExecuted

        // act
        hoverOf(state, dir.join("a.cj"), 2, 6)

        // assert
        @Expect(first > before)
        @Expect(handleAnalysisStats(state.snapshot(), ()).queriesExecuted, first)
    }

    @TestCase
    func theServerAdvertisesItAsAnExperimentalCapability() {
        // act
        let json = RawJson.of(capabilities(Encoding.Utf16)).toString()

        // assert
        @Expect(json.contains(##""analysisStats":true"##))
    }
}
