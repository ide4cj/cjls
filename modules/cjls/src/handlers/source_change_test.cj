package cjls.handlers

import std.env.getTempDirectory
import std.unittest.*
import std.unittest.testmacro.*
import cjls.lsp_types.*
import loupe.TextRange
import loupe.vfs.VfsPath
import rope.Encoding
import source_change.{FileChange, SourceChange}
import source_change.TextEdit as SourceTextEdit
import stdxx.Nullable

@Test
class SourceChangeEditTest {
    @TestCase
    func textEditsUseExpectedTextAndOpenDocumentVersions(): Unit {
        // arrange
        let path = getTempDirectory().join("source-change.cj").toString()
        let change = SourceChange(
            [FileChange.EditFile(path, "ё😀x", [SourceTextEdit(TextRange(6, 7), "y")])]
        )

        // act
        let edit = sourceChangeEdit(change, Encoding.Utf16, { _ => Some(7) }, [])
        let documents = edit.documentChanges.getOrThrow()

        // assert
        @Expect(documents.size, 1)
        match (documents[0]) {
            case AsTextDocumentEdit(document) =>
                @Expect(document.textDocument.version.getOrThrow(), 7)
                match (document.edits[0]) {
                    case AsTextEdit(text) =>
                        @Expect(text.range.start.character, 3)
                        @Expect(text.range.end.character, 4)
                        @Expect(text.newText, "y")
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }
    }

    @TestCase
    func creationPrecedesContentsAndFileOperationsNeverOverwrite(): Unit {
        // arrange
        let root = getTempDirectory()
        let created = root.join("created.cj").toString()
        let change = SourceChange(
            [
                FileChange.CreateFile(created, "package sample\n"),
                FileChange.RenameFile(
                    root.join("old.cj").toString(),
                    root.join("new.cj").toString(),
                    "old"
                ),
                FileChange.DeleteFile(root.join("deleted.cj").toString(), "deleted")
            ]
        )

        // act
        let edit = sourceChangeEdit(
            change,
            Encoding.Utf8,
            { _ => None },
            ["create", "rename", "delete"]
        )
        let documents = edit.documentChanges.getOrThrow()

        // assert
        @Expect(documents.size, 4)
        match (documents[0]) {
            case AsCreateFile(file) =>
                @Expect(file.uri, VfsPath.file(created).toUri())
                @Expect(file.options.isNone())
            case _ => @Expect(false)
        }
        match (documents[1]) {
            case AsTextDocumentEdit(document) =>
                @Expect(document.textDocument.version.isNull())
                match (document.edits[0]) {
                    case AsTextEdit(text) => @Expect(text.newText, "package sample\n")
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }
        match (documents[2]) {
            case AsRenameFile(file) => @Expect(file.options.isNone())
            case _ => @Expect(false)
        }
        match (documents[3]) {
            case AsDeleteFile(file) => @Expect(file.options.isNone())
            case _ => @Expect(false)
        }
    }

    @TestCase
    func insertionOrderMatchesTheCheckedTextApplication(): Unit {
        // arrange
        let path = getTempDirectory().join("source-change.cj").toString()
        let change = SourceChange(
            [
                FileChange.EditFile(
                    path,
                    "x",
                    [
                        SourceTextEdit(TextRange(0, 1), "replacement"),
                        SourceTextEdit(TextRange(0, 0), "first"),
                        SourceTextEdit(TextRange(0, 0), "second")
                    ]
                )
            ]
        )

        // act
        let edit = sourceChangeEdit(change, Encoding.Utf8, { _ => None }, [])

        // assert
        match (edit.documentChanges.getOrThrow()[0]) {
            case AsTextDocumentEdit(document) =>
                let texts =
                    document
                        .edits
                        .map {
                            edit =>
                            match (edit) {
                                case AsTextEdit(text) => text.newText
                                case _ => "unexpected edit variant"
                            }
                        }
                @Expect(texts, ["first", "second", "replacement"])
            case _ => @Expect(false)
        }
    }

    @TestCase
    func unsupportedResourceOperationsAreRejected(): Unit {
        // arrange
        let path = getTempDirectory().join("created.cj").toString()
        let change = SourceChange([FileChange.CreateFile(path, "")])

        // act / assert
        @AssertThrows[IllegalArgumentException](sourceChangeEdit(change, Encoding.Utf8, { _ => None }, []))
    }
}
