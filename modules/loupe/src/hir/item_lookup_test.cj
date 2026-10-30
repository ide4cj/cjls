package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.Fixture
import rope.Rope

@Test
class ItemLookupTest {
    @TestCase
    func nestedDeclarationsResolveByTheirOwnIdentity() {
        // arrange
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
        let expected = items.flatMap { item => [item].concat(item.members) }

        // act
        let found = expected.map { item => itemOf(db, DefId(db, file, item.id)) }

        // assert
        @Expect(items.size, 3)
        @Expect(items.map { item => item.members.size }, [2, 2, 2])
        @Expect(found, expected.map { item => Some(item) })
    }

    @TestCase
    func removingAMemberInvalidatesItsCachedLookupWhileTheOwnerSurvives() {
        // arrange
        let parsed = Fixture.parse("class First { var value: Int64 = 1 }")
        let db = parsed.database()
        let file = ItemFile.Source(db.sourceFile(parsed.files[0].fileId).getOrThrow())
        let item = itemTreeOf(db, file).items[0]
        let owner = DefId(db, file, item.id)
        let removed = DefId(db, file, item.members[0].id)
        let before = itemOf(db, removed)

        // act
        db.setFileText(parsed.files[0].fileId, Rope("class First {}"))
        let after = itemOf(db, removed)
        let retained = itemOf(db, owner)

        // assert
        @Expect(before, Some(item.members[0]))
        @Expect(after, None)
        @Expect(retained.isSome())
    }
}
