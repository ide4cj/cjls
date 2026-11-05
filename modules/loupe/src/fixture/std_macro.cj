package loupe.fixture

import std.unittest.assertEqual
import loupe.db.AnalysisDatabase

/**
 * Checks the same source annotations through cjls's built-in std expansions and supplied server
 * answers (#434). Separate databases prevent an earlier inference from hiding a replacement bug.
 * `serve` must answer the selected std calls with text and mapped spans before observation;
 * `observe` returns source-coordinate answers, including any diagnostics the case needs to guard.
 * SDK interaction stays in macro_host's ServedDiagnosticsGateTest; these fixtures need only cjos.
 *
 * @throws FixtureException - if the fixture or its supplied answer/observation setup is invalid
 * @throws IllegalStateException - if the selected SDK does not provide the required std cjos
 */
public func checkStdMacroReadings(
    fixture: String,
    serve: (Fixture, AnalysisDatabase) -> Unit,
    observe: (Fixture, AnalysisDatabase) -> Array<Annotation>
): Unit {
    let parsed = Fixture.parse(fixture)
    let binaries =
        [
            "std.core",
            "std.deriving",
            "std.unittest",
            "std.unittest.common",
            "std.unittest.testmacro"
        ]
            .map { name => stdCjoRead(name, stdCjo(name)) }
    let own = observe(parsed, parsed.database(binaries: binaries))
    let served = parsed.database(binaries: binaries)
    serve(parsed, served)
    let actual = observe(parsed, served)
    // Compare before UPDATE_EXPECT can rewrite an expectation and hide a difference between readings.
    assertEqual("built-in expansion", "server expansion", parsed.render(own), parsed.render(actual))
    expectAnnotations(fixture, actual)
}
