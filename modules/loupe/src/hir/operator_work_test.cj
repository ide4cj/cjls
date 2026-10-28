package loupe.hir

import std.sync.AtomicInt64
import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

@Test
class OperatorInferenceWorkTest {
    @TestCase[contextual in [false, true]]
    func overloadedChainsFitABoundedAmountOfQueryWork(contextual: Bool) {
        // arrange: retrying every left subtree doubles the work at each link. Query cancellation
        // checks count memo hits too, so the bound detects retries without timing the machine.
        let chain = "v" + " + v" * 31
        let expression = if (contextual) { "(${chain}) % 1" } else { chain }
        let returned = if (contextual) { "UInt64" } else { "V" }
        let expectedCallees = if (contextual) { 32 } else { 31 }
        let parsed =
            Fixture
                .parse(
                    """
                    package m
                    struct V {
                        operator func +(rhs: V): V { this }
                        operator func %(rhs: Int64): UInt64 { 0 }
                    }
                    func chain(v: V): ${returned} { ${expression} }
                    """
                )
        let db = parsed.database()
        let source = db.sourceFile(parsed.files[0].fileId).getOrThrow()
        let item =
            itemTree(db, source)
                .items
                .iterator()
                .filter { one => one.names.contains("chain") }
                .next()
                .getOrThrow()
        let def = DefId(db, ItemFile.Source(source), item.id)
        let checks = AtomicInt64(0)
        // Ordinary inference takes a few thousand reads here; keep broad headroom while
        // bounding the exponential retry failure independently of machine speed.
        let limit = 100_000
        let bounded = db.snapshot(cancelledBy: { => checks.fetchAdd(1) >= limit })

        // act
        let result = inferBody(bounded, def)

        // assert
        @Expect(result.diagnostics, [])
        @Expect(result.ty.getOrThrow().text(db), returned)
        @Expect(result.callees.size, expectedCallees)
        @Expect(checks.load() <= limit, true)
    }
}
