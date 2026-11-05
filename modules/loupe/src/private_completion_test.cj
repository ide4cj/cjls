package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

@Test
class PrivateCompletionTest {
    @TestCase
    func fileScopeListsOnlyPrivateDeclarationsFromTheCurrentFile(): Unit {
        // arrange
        let parsed = Fixture.parse(
            #"
            //- /other.cj
            private func hidden(): Int64 { 1 }
            private class HiddenType {}
            private enum HiddenEnum { | HiddenCtor }
            func shared(): Int64 { 1 }
            //- /main.cj
            private func own(): Int64 { 1 }
            private class OwnType {}
            private enum OwnEnum { | OwnCtor }
            func useHere(): Unit { $0 }
            "#
        )
        let db = parsed.database()
        let cursor = parsed.cursor.getOrThrow()

        // act
        let items = completionsAt(db, cursor.fileId, cursor.offset).getOrThrow().items
        let labels = items.map { item => item.label }

        // assert
        for (hidden in ["hidden", "HiddenType", "HiddenEnum"]) {
            @Expect(!labels.contains(hidden))
        }
        for (shown in ["own", "OwnType", "OwnEnum", "OwnCtor", "shared", "HiddenCtor"]) {
            @Expect(labels.contains(shown))
        }
    }

    @TestCase
    func aPrivateMemberStillAppearsInsideItsDeclaringType(): Unit {
        checkCompletion(
            #"
            class Own {
                private func mine(): Unit {}
                func useHere(): Unit {
                    this.$0
            //          ^ 080 mine | CompletionKind.FuncItem | private func mine(): Unit
            //          ^ 080 useHere | CompletionKind.FuncItem | func useHere(): Unit
                }
            }
            "#
        )
    }

    @TestCase
    func aPrivateEnumsConstructorReferencesIncludeAnotherFile(): Unit {
        // arrange
        let parsed = Fixture.parse(
            #"
            //- /a.cj
            private enum Secret { | Hid$0den }
            //- /b.cj
            func useOther(): Unit { let value = Hidden }
            "#
        )
        let db = parsed.database()
        let cursor = parsed.cursor.getOrThrow()
        let declarationFile = parsed.file("/a.cj").fileId.index
        let useFile = parsed.file("/b.cj").fileId.index

        // act
        let references = findReferences(db, cursor.fileId, cursor.offset)

        // assert
        @Expect(references.size, 2)
        @Expect(
            references.filter { one => one.isDeclaration }.map { one => one.fileId.index },
            [declarationFile]
        )
        @Expect(
            references.filter { one => !one.isDeclaration }.map { one => one.fileId.index },
            [useFile]
        )
    }
}
