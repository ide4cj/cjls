package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.AnalysisDatabase

@Test
class LookupTyTest {
    @TestCase
    func anAbsentReceiverIsComputedOnlyOnceAndOnlyWhenNeeded() {
        // arrange
        let calls = [0]
        let lookup =
            LookupTy(
                {
                    =>
                    calls[0]++
                    Option<Ty>.None
                }
            )

        // act
        let before = calls[0]
        let first = lookup.get()
        let second = lookup.get()

        // assert
        @Expect(before, 0)
        @Expect(first.isNone())
        @Expect(second.isNone())
        @Expect(calls[0], 1)
    }

    @TestCase
    func aKnownReceiverIsComputedOnlyOnce() {
        // arrange
        let db = AnalysisDatabase()
        let ty = Ty(db, PrimTy("Int64"))
        let calls = [0]
        let lookup =
            LookupTy(
                {
                    =>
                    calls[0]++
                    Some(ty)
                }
            )

        // act
        let before = calls[0]
        let first = lookup.get()
        let second = lookup.get()

        // assert
        @Expect(before, 0)
        @Expect(first, Some(ty))
        @Expect(second, Some(ty))
        @Expect(calls[0], 1)
    }
}
