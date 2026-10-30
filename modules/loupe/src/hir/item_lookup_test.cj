package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.Fixture
import rope.Rope

@Test
class ItemLookupTest {
    @TestCase
    func nestedDeclarationsResolveByTheirOwnIdentity() {
        let parsed =
            Fixture
                .parse(
                    #"
            //- /main.cj
            class First {
                var value: Int64 = 1
                func read(): Int64 { value }
            }
            class Second {
                var value: Int64 = 2
                func read(): Int64 { value }
            }
            enum Choice { Left | Right(Int64) }
            "#
                )
        let db = parsed.database()
        let file = ItemFile.Source(db.sourceFile(parsed.files[0].fileId).getOrThrow())
        let items = itemTreeOf(db, file).items
        @Expect(items.size, 3)
        for (item in items) {
            @Expect(itemOf(db, DefId(db, file, item.id)), Some(item))
            @Expect(item.members.size, 2)
            for (member in item.members) {
                @Expect(itemOf(db, DefId(db, file, member.id)), Some(member))
            }
        }

        // A removed member must invalidate its cached lookup even if its owner survives.
        let removed = DefId(db, file, items[0].members[0].id)
        db.setFileText(parsed.files[0].fileId, Rope("class First {}"))
        @Expect(itemOf(db, removed), None)
        @Expect(itemOf(db, DefId(db, file, items[0].id)).isSome())
    }
}
