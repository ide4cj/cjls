package loupe.hir

import std.sync.AtomicInt64
import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.{Fixture, FixtureException}

@Test
class OperatorInferenceWorkTest {
    /**
     * The SDK's @TestCase generates positional calls, so its parameter cannot be named.
     */
    @TestCase[contextual in [false, true]]
    func overloadedChainsFitABoundedAmountOfQueryWork(contextual: Bool): Unit {
        // arrange: retrying every left subtree doubles the work at each link. Query cancellation
        // checks count memo hits too, so the bound detects retries without timing the machine.
        let suffix = " + v" * 31
        let chain = "v${suffix}"
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
        let source =
            db
                .sourceFile(parsed.files[0].fileId)
                .getOrThrow { FixtureException("fixture must contain m") }
        let item =
            itemTree(db, source)
                .items
                .iterator()
                .filter { one => one.names.contains("chain") }
                .next()
                .getOrThrow { FixtureException("fixture must declare chain") }
        let def = DefId(db, ItemFile.Source(source), item.id)
        let checks = AtomicInt64(0)
        // Ordinary inference takes a few thousand reads here; keep broad headroom while
        // bounding the exponential retry failure independently of machine speed.
        const LIMIT = 100_000
        let bounded = db.snapshot(cancelledBy: { => checks.fetchAdd(1) >= LIMIT })

        // act
        let result = inferBody(bounded, def)
        let ty = result.ty.getOrThrow { IllegalStateException("chain must infer a return type") }

        // assert
        @Expect(result.diagnostics, [])
        @Expect(ty.text(db), returned)
        @Expect(result.callees.size, expectedCallees)
        @Expect(checks.load() <= LIMIT, true)
    }
}
