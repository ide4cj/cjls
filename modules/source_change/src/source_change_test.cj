package source_change

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange

@Test
class SourceChangeTest {
    @TestCase
    func allFileOperationsReserveTheirPaths(): Unit {
        // arrange
        let change = SourceChange(
            [
                EditFile("a", "old", [TextEdit(TextRange(0, 3), "new")]),
                CreateFile("b", "contents"),
                RenameFile("c", "d", "before"),
                DeleteFile("e", "before")
            ]
        )

        // act
        change.validate()
        let paths = change.files.map { file => file.paths() }

        // assert
        @Expect(paths, [["a"], ["b"], ["c", "d"], ["e"]])
    }

    @TestCase
    func repeatedPathsAndRenameChainsAreRejected(): Unit {
        // arrange
        let duplicate = SourceChange([CreateFile("a", ""), DeleteFile("a", "")])
        let chain = SourceChange([RenameFile("a", "b", ""), RenameFile("b", "c", "")])
        let selfRename = SourceChange([RenameFile("a", "a", "")])
        let empty = SourceChange([CreateFile("", "")])

        // act / assert
        @AssertThrows[IllegalArgumentException](duplicate.validate())
        @AssertThrows[IllegalArgumentException](chain.validate())
        @AssertThrows[IllegalArgumentException](selfRename.validate())
        @AssertThrows[IllegalArgumentException](empty.validate())
    }

    @TestCase
    func invalidTextEditsAreCheckedBeforeAnyConsumerAppliesTheChange(): Unit {
        // arrange
        let change = SourceChange(
            [CreateFile("first", ""), EditFile("second", "ё", [TextEdit(TextRange(1, 2), "x")])]
        )

        // act / assert
        @AssertThrows[IllegalArgumentException](change.validate())
    }
}
