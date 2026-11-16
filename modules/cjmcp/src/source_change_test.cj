package cjmcp

import std.collection.ArrayList
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import loupe.vfs.VfsPath
import source_change.{FileChange, SourceChange, TextEdit}

@When[os == "Linux"]
@Test
class ApplySourceChangeTest {
    @TestCase
    func createsEditsRenamesAndDeletesFilesWithoutChangingTheAnalysisRevision(): Unit {
        // arrange
        let root = workspaceFixture()
        let state = WorkspaceState(VfsPath.file(root))
        let before = String.fromUtf8(File.readFrom(root.join("src/main.cj")))
        let change = SourceChange(
            [
                FileChange.EditFile(
                    "src/main.cj",
                    before,
                    [TextEdit(TextRange(before.size, before.size), "// ё😀\n")]
                ),
                FileChange.CreateFile("src/nested/created.cj", "package sample\n"),
                FileChange.CreateFile("empty", "")
            ]
        )
        try {
            // act
            let first = applySourceChange(state, change, 0)
            let second = applySourceChange(
                state,
                SourceChange(
                    [
                        FileChange.RenameFile(
                            "src/nested/created.cj",
                            "src/renamed.cj",
                            "package sample\n"
                        ),
                        FileChange.DeleteFile("empty", "")
                    ]
                ),
                0
            )

            // assert
            @Expect(first.isSuccess)
            @Expect(first.applied, [0, 1, 2])
            @Expect(second.isSuccess)
            @Expect(second.applied, [0, 1])
            @Expect(state.revision, 0)
            @Expect(String.fromUtf8(File.readFrom(root.join("src/main.cj"))), "${before}// ё😀\n")
            @Expect(exists(root.join("src/renamed.cj")))
            @Expect(!exists(root.join("empty")))
            @Expect(!exists(root.join("src/nested/created.cj")))
        } finally {
            state.close()
            remove(root, recursive: true)
        }
    }

    @TestCase
    func conflictsInLaterOperationsPreventEarlierWrites(): Unit {
        // arrange
        let root = workspaceFixture()
        let state = WorkspaceState(VfsPath.file(root))
        let change = SourceChange(
            [
                FileChange.CreateFile("new.cj", "new"),
                FileChange.DeleteFile("src/main.cj", "outdated")
            ]
        )
        try {
            // act
            let result = applySourceChange(state, change, 0)

            // assert
            @Expect(!result.isSuccess)
            @Expect(result.applied.isEmpty())
            @Expect(result.failed.isNone())
            @Expect(!exists(root.join("new.cj")))
            @Expect(result.error.getOrThrow().contains("ContentModified"))
        } finally {
            state.close()
            remove(root, recursive: true)
        }
    }

    @TestCase
    func pathAliasesParentConflictsAndOutsidePathsAreRejectedBeforeWriting(): Unit {
        // arrange
        let root = workspaceFixture()
        let state = WorkspaceState(VfsPath.file(root))
        let changes =
            [
                SourceChange(
                    [FileChange.CreateFile("new", ""), FileChange.CreateFile("src/../new", "")]
                ),
                SourceChange(
                    [FileChange.CreateFile("new", ""), FileChange.CreateFile("new/child", "")]
                ),
                SourceChange([FileChange.CreateFile("../outside", "")]),
                SourceChange([FileChange.CreateFile("src/main.cj/child", "")])
            ]
        try {
            // act
            let reports = changes.map { change => applySourceChange(state, change, 0) }

            // assert
            @Expect(reports.filter { report => report.isSuccess || !report.applied.isEmpty() }.isEmpty())
            @Expect(!exists(root.join("new")))
        } finally {
            state.close()
            remove(root, recursive: true)
        }
    }

    @TestCase
    func existingDestinationsAndSymlinksAreNeverOverwritten(): Unit {
        // arrange
        let root = workspaceFixture()
        let state = WorkspaceState(VfsPath.file(root))
        let before = String.fromUtf8(File.readFrom(root.join("src/main.cj")))
        SymbolicLink.create(root.join("linked"), to: root.join("src"))
        try {
            // act
            let existing = applySourceChange(
                state,
                SourceChange([FileChange.CreateFile("src/main.cj", "bad")]),
                0
            )
            let renamed = applySourceChange(
                state,
                SourceChange([FileChange.RenameFile("src/main.cj", "src/main.cj", before)]),
                0
            )
            let linked = applySourceChange(
                state,
                SourceChange([FileChange.CreateFile("linked/new.cj", "bad")]),
                0
            )

            // assert
            @Expect(!existing.isSuccess)
            @Expect(!renamed.isSuccess)
            @Expect(!linked.isSuccess)
            @Expect(File.readFrom(root.join("src/main.cj")), before.toArray())
            @Expect(!exists(root.join("src/new.cj")))
        } finally {
            state.close()
            remove(root, recursive: true)
        }
    }

    @TestCase
    func aStaleRevisionCannotStartApplication(): Unit {
        // arrange
        let root = workspaceFixture()
        let state = WorkspaceState(VfsPath.file(root))
        let change = SourceChange([FileChange.CreateFile("new", "")])
        try {
            // act / assert
            @AssertThrows[IllegalStateException](applySourceChange(state, change, 1))
            @Expect(!exists(root.join("new")))
        } finally {
            state.close()
            remove(root, recursive: true)
        }
    }

    @TestCase
    func partialFailureReportsCompletedAndFailedOperationsAndStops(): Unit {
        // arrange
        let files =
            [
                FileChange.CreateFile("first", ""),
                FileChange.CreateFile("second", ""),
                FileChange.CreateFile("third", "")
            ]
        let attempted = ArrayList<FileChange>()

        // act
        let report = applyPreparedSourceChange(
            files,
            7,
            {
                file =>
                attempted.add(file)
                if (attempted.size == 2) {
                    throw FSException("injected write failure")
                }
            }
        )

        // assert
        @Expect(report.revision, 7)
        @Expect(report.applied, [0])
        @Expect(report.failed, Some(1))
        @Expect(report.error, Some("injected write failure"))
        @Expect(attempted.size, 2)
    }
}
