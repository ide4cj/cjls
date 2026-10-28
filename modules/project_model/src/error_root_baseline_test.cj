package project_model

import std.collection.*
import std.convert.Parsable
import std.sort.sort
import std.unittest.*
import std.unittest.testmacro.*

/** Keeps root attribution attached to its file/kind when a count changes. */
class ErrorRootBaseline {
    let counts = HashMap<String, Int64>()
    private let reasons = HashMap<String, String>()
    private let header: Array<String>

    ErrorRootBaseline(lines: Array<String>) {
        header = lines.filter { line => line.startsWith("#") }
        for (line in lines where !line.startsWith("#") && !line.isEmpty()) {
            let parts = line.split("  # ", 2)
            let at = parts[0].lastIndexOf(": ").getOrThrow()
            let key = parts[0][..at]
            counts[key] = Int64.parse(parts[0][at + 2..])
            if (let Some(reason) <- parts.get(1)) {
                reasons[key] = reason
            }
        }
    }

    /** A new local group remains visibly unattributed until its cause is investigated. */
    func updated(found: HashMap<String, Int64>): Array<String> {
        let written =
            found
                .keys()
                .toArray()
                .map {
                    key =>
                    let reason =
                        reasons.get(key) ?? if (key.endsWith(": local")) { "?" } else { "" }
                    let comment = if (reason.isEmpty()) { "" } else { "  # ${reason}" }
                    "${key}: ${found[key]}${comment}"
                }
        sort(written)
        header.concat(written)
    }

    func unattributedLocals(): Array<String> {
        counts
            .keys()
            .toArray()
            .filter {
                key =>
                let reason = reasons.get(key) ?? ""
                key.endsWith(": local") && (reason.isEmpty() || reason == "?")
            }
    }
}

@Test
class ErrorRootBaselineTest {
    @TestCase
    func readsAttributedAndLegacyCounts() {
        // arrange
        let lines = ["# header", "a.cj: local: 3  # pipeline (#246)", "b.cj: member found: 2"]

        // act
        let baseline = ErrorRootBaseline(lines)
        let missing = baseline.unattributedLocals()

        // assert
        @Expect(baseline.counts["a.cj: local"], 3)
        @Expect(baseline.counts["b.cj: member found"], 2)
        @Expect(missing, [])
    }

    @TestCase
    func aShrinkingCountKeepsItsReasonAndAnAbsentGroupDisappears() {
        // arrange
        let baseline =
            ErrorRootBaseline(
                [
                    "# header",
                    "a.cj: local: 3  # pipeline (#246)",
                    "b.cj: local: 1  # callback (#551)"
                ]
            )
        let found = HashMap<String, Int64>([("a.cj: local", 1)])

        // act
        let written = baseline.updated(found)

        // assert
        @Expect(written, ["# header", "a.cj: local: 1  # pipeline (#246)"])
    }

    @TestCase
    func aNewLocalGroupNeedsAttributionAfterUpdating() {
        // arrange
        let baseline = ErrorRootBaseline([])
        let found = HashMap<String, Int64>([("new.cj: local", 2), ("other.cj: index", 1)])

        // act
        let written = baseline.updated(found)
        let missing = ErrorRootBaseline(written).unattributedLocals()

        // assert
        @Expect(written, ["new.cj: local: 2  # ?", "other.cj: index: 1"])
        @Expect(missing, ["new.cj: local"])
    }
}
