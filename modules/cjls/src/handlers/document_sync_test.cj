package cjls.handlers

import std.env.getTempDirectory
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import rope.{Encoding, Rope}
import loupe.vfs.VfsPath
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange
import cjls.server.*

let URI = "file:///nowhere/a.cj"

func opened(text: String, uri!: String = URI): ServerState {
    let state = ServerState()
    handleDidOpen(state, DidOpenTextDocumentParams(
        textDocument: TextDocumentItem(uri: uri, languageId: LanguageKind("cangjie"), version: 1, text: text)))
    state
}

/**
 * A change replacing `from..to`, each a line and a column, with `text`.
 */
func partial(text: String, from!: (UInt32, UInt32), to!: (UInt32, UInt32)): TextDocumentContentChangeEvent {
    TextDocumentContentChangeEvent.AsTextDocumentContentChangePartial(TextDocumentContentChangePartial(
        range: LspRange(start: Position(line: from[0], character: from[1]), end: Position(line: to[0], character: to[1])),
        text: text))
}

func change(state: ServerState, changes: Array<TextDocumentContentChangeEvent>): Unit {
    handleDidChange(state, NoopLogger(), DidChangeTextDocumentParams(
        textDocument: VersionedTextDocumentIdentifier(uri: URI, version: 2), contentChanges: changes))
}

func textOf(state: ServerState): ?String {
    state.fileContents(VfsPath.fromUri(URI))?.toString()
}

@Test
class DocumentSyncTest {
    @TestCase
    func anOpenedDocumentIsWhatTheAnalysisSees() {
        // act
        let state = opened("func f() {}\n")

        // assert
        let snapshot = state.snapshot()
        let file = snapshot.sourceFile(VfsPath.fromUri(URI)).getOrThrow()
        @Expect(file.text(snapshot.analysis).toString(), "func f() {}\n")
    }

    @TestCase
    func theSnapshotGivesAFilesPathBackFromItsId() {
        // arrange
        let snapshot = opened("func f() {}\n").snapshot()
        let file = snapshot.sourceFile(VfsPath.fromUri(URI)).getOrThrow()

        // act
        let path = snapshot.path(file.fileId(snapshot.analysis))

        // assert
        @Expect(path, VfsPath.fromUri(URI))
    }

    @TestCase
    func changesApplyInOrderEachToWhatTheOneBeforeLeft() {
        // arrange
        let state = opened("let a = 1\nlet b = 2\n")

        // act
        change(state, [
            partial("x", from: (0, 4), to: (0, 5)),
            partial("// b\n", from: (1, 0), to: (1, 0)),
            partial("3", from: (2, 8), to: (2, 9))
        ])

        // assert
        @Expect(textOf(state), Some("let x = 1\n// b\nlet b = 3\n"))
        @Expect(state.openDocuments.get(VfsPath.fromUri(URI)), Some(Int32(2)))
    }

    @TestCase
    func aWholeDocumentChangeReplacesTheText() {
        // arrange
        let state = opened("old")

        // act
        change(state, [TextDocumentContentChangeEvent.AsTextDocumentContentChangeWholeDocument(
            TextDocumentContentChangeWholeDocument(text: "new")), partial("er", from: (0, 3), to: (0, 3))])

        // assert
        @Expect(textOf(state), Some("newer"))
    }

    @TestCase
    func columnsCountTheEncodingAgreedOn() {
        // arrange - "😀" is two UTF-16 units and four bytes
        let utf16 = opened("😀a\n")
        let utf8 = opened("😀a\n")
        utf8.encoding = Encoding.Utf8

        // act
        change(utf16, [partial("b", from: (0, 2), to: (0, 3))])
        change(utf8, [partial("b", from: (0, 4), to: (0, 5))])

        // assert
        @Expect(textOf(utf16), Some("😀b\n"))
        @Expect(textOf(utf8), Some("😀b\n"))
    }

    @TestCase
    func aBatchWithABackwardRangeIsDroppedWhole() {
        // arrange
        let state = opened("abc")

        // act
        change(state, [partial("x", from: (0, 0), to: (0, 1)), partial("y", from: (0, 2), to: (0, 1))])

        // assert
        @Expect(textOf(state), Some("abc"))
        @Expect(state.openDocuments.get(VfsPath.fromUri(URI)), Some(Int32(1)))
    }

    @TestCase
    func aChangeToADocumentNotOpenIsIgnored() {
        // arrange
        let state = ServerState()

        // act
        change(state, [partial("x", from: (0, 0), to: (0, 0))])

        // assert
        @Expect(textOf(state), None<String>)
    }

    @TestCase
    func aClosedDocumentNotOnDiskIsGone() {
        // arrange
        let state = opened("let a = 1\n")
        let file = state.snapshot().sourceFile(VfsPath.fromUri(URI)).getOrThrow()

        // act
        handleDidClose(state, DidCloseTextDocumentParams(textDocument: TextDocumentIdentifier(uri: URI)))

        // assert
        @Expect(textOf(state), None<String>)
        @Expect(state.openDocuments.isEmpty())
        @Expect(file.text(state.analysis).toString(), "")
    }

    @TestCase
    func aClosedDocumentOnDiskIsWhatTheDiskHolds() {
        // arrange
        let dir = Directory.createTemp(getTempDirectory())
        let onDisk = dir.join("b.cj")
        File.writeTo(onDisk, "on disk".toArray())
        let uri = VfsPath.file(onDisk).toUri()
        let state = opened("in the editor", uri: uri)

        // act
        handleDidClose(state, DidCloseTextDocumentParams(textDocument: TextDocumentIdentifier(uri: uri)))
        remove(dir, recursive: true)

        // assert
        @Expect(state.fileContents(VfsPath.fromUri(uri))?.toString(), Some("on disk"))
    }
}
