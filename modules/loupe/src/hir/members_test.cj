package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.AnalysisDatabase

@Test
class LookupTyTest {
    @TestCase
    func anAbsentReceiverIsComputedOnlyOnceAndOnlyWhenNeeded() {
        let calls = [0]
        let lookup = LookupTy({=>
            calls[0]++
            Option<Ty>.None
        })

        @Expect(calls[0], 0)
        @Expect(lookup.get().isNone())
        @Expect(lookup.get().isNone())
        @Expect(calls[0], 1)
    }

    @TestCase
    func aKnownReceiverIsComputedOnlyOnce() {
        let db = AnalysisDatabase()
        let ty = Ty(db, PrimTy("Int64"))
        let calls = [0]
        let lookup = LookupTy({=>
            calls[0]++
            Some(ty)
        })

        @Expect(calls[0], 0)
        @Expect(lookup.get(), Some(ty))
        @Expect(lookup.get(), Some(ty))
        @Expect(calls[0], 1)
    }
}
