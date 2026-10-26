package cjls.handlers

import std.fs.{Path, remove}
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import jsonrpc.RequestBody
import rope.Rope
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange
import cjls.server.*

/**
 * A cjpm module `app`, with the packages `app` and `app.util`.
 */
func appModule(): Path {
    workspaceOf([("cjpm.toml", "[package]\nname = \"app\"\n"), ("src/main.cj", "package app\nmain() {}"),
        ("src/util/u.cj", "package app.util")])
}

/**
 * The state of a client that applies edits, of a version if `versioned`, once the project of `root`
 * is loaded, if `loaded`.
 */
func editableWith(root: Path, versioned!: Bool = false, loaded!: Bool = true): Loop {
    let loop = initializedWith([root], watches: false)
    loop.state.appliesEdits = true
    loop.state.versionedEdits = versioned
    if (loaded) {
        initialized(loop, Client(), NoopLogger(), InitializedParams())
    }
    loop
}

func openBlank(loop: Loop, client: Client, path: Path, text!: String = "\n"): Unit {
    handleDidOpen(loop, client, NoopLogger(), DidOpenTextDocumentParams(
        textDocument: TextDocumentItem(uri: uriOf(path), languageId: LanguageKind("cangjie"), version: 3, text: text)))
}

/**
 * The edit of `workspace/applyEdit` `request` asks for.
 */
func editOf(request: RequestBody): ApplyWorkspaceEditParams {
    @Expect(request.method, ApplyWorkspaceEditRequestSpec.METHOD)
    request.params.getOrThrow().read<ApplyWorkspaceEditParams>()
}

/**
 * The text edits of `edit`, which has them under `changes`, of the document at `uri`.
 */
func changesOf(edit: ApplyWorkspaceEditParams, uri: String): Array<TextEdit> {
    let changes = edit.edit.changes.getOrThrow()
    @Expect(changes.size, 1)
    changes[uri]
}

func spanOf(range: LspRange): String {
    "${range.start.line}:${range.start.character}-${range.end.line}:${range.end.character}"
}

@Test
class NewFilePackageTest {
    @TestCase
    func aDocumentOpenedBlankInADirectoryOfTheModuleIsGivenItsPackageLine() {
        // arrange
        let root = appModule()
        let loop = editableWith(root)
        let transport = RequestsTransport()
        let client = clientOn(transport)
        let path = root.join("src").join("net").join("new.cj")

        // act: Neovim's `:e new.cj`, a file not on disk yet
        openBlank(loop, client, path)
        client.close()
        remove(root, recursive: true)

        // assert
        let edit = editOf(transport.nextRequest().getOrThrow())
        @Expect(edit.label, Some("package app.net"))
        let edits = changesOf(edit, uriOf(path))
        @Expect(edits.size, 1)
        @Expect(spanOf(edits[0].range), "0:0-0:0")
        @Expect(edits[0].newText, "package app.net\n")
        @Expect(transport.nextRequest().isNone())
    }

    @TestCase[loaded in [true, false]]
    func aNewFileInAMacroPackageGetsAMacroHeader(loaded: Bool) {
        let root = workspaceOf([("cjpm.toml", "[package]\nname = \"app\"\n"),
            ("src/ms/m.cj", "macro package app.ms")])
        let loop = editableWith(root, loaded: loaded)
        let transport = RequestsTransport()
        let client = clientOn(transport)
        let path = root.join("src").join("ms").join("new.cj")

        let request: ?LoadRequest = if (loaded) {None} else {loadRequest(loop.state)}
        openBlank(loop, client, path)
        if (let Some(pending) <- request) {
            load(loop, client, NoopLogger(), pending)
        }
        client.close()
        remove(root, recursive: true)

        let edit = editOf(transport.nextRequest().getOrThrow())
        @Expect(edit.label, Some("macro package app.ms"))
        @Expect(changesOf(edit, uriOf(path))[0].newText, "macro package app.ms\n")
    }

    @TestCase
    func aClientTakingVersionsIsGivenTheLineOfTheVersionOpened() {
        // arrange
        let root = appModule()
        let loop = editableWith(root, versioned: true)
        let transport = RequestsTransport()
        let client = clientOn(transport)
        let path = root.join("src").join("util").join("new.cj")

        // act
        openBlank(loop, client, path, text: "")
        client.close()
        remove(root, recursive: true)

        // assert
        let edit = editOf(transport.nextRequest().getOrThrow())
        @Expect(edit.edit.changes.isNone())
        let changes = edit.edit.documentChanges.getOrThrow()
        @Expect(changes.size, 1)
        match (changes[0]) {
            case AsTextDocumentEdit(document) =>
                @Expect(document.textDocument.uri, uriOf(path))
                @Expect(document.textDocument.version.getOrThrow(), 3)
                @Expect(document.edits.size, 1)
                match (document.edits[0]) {
                    case AsTextEdit(text) =>
                        @Expect(spanOf(text.range), "0:0-0:0")
                        @Expect(text.newText, "package app.util\n")
                    case _ => @Fail("not a text edit")
                }
            case _ => @Fail("not an edit of a document")
        }
    }

    @TestCase
    func aDocumentOpenedBlankWhileALoadRunsIsGivenItsLineWhenTheLoadEnds() {
        // arrange
        let root = appModule()
        let loop = editableWith(root, loaded: false)
        let transport = RequestsTransport()
        let client = clientOn(transport)
        let request = loadRequest(loop.state).getOrThrow()
        let path = root.join("src").join("new.cj")

        // act
        openBlank(loop, client, path)
        let beforeTheEnd = transport.nextRequest()
        load(loop, client, NoopLogger(), request)
        client.close()
        remove(root, recursive: true)

        // assert
        @Expect(beforeTheEnd.isNone())
        @Expect(changesOf(editOf(transport.nextRequest().getOrThrow()), uriOf(path))[0].newText, "package app\n")
    }

    @TestCase
    func aDocumentTypedInWhileALoadRunsIsLeftAlone() {
        // arrange
        let root = appModule()
        let loop = editableWith(root, loaded: false)
        let transport = RequestsTransport()
        let client = clientOn(transport)
        let request = loadRequest(loop.state).getOrThrow()
        let path = root.join("src").join("new.cj")
        openBlank(loop, client, path)

        // act
        handleDidChange(loop.state, NoopLogger(), DidChangeTextDocumentParams(
            textDocument: VersionedTextDocumentIdentifier(uri: uriOf(path), version: 4),
            contentChanges: [TextDocumentContentChangeEvent.AsTextDocumentContentChangeWholeDocument(
                TextDocumentContentChangeWholeDocument(text: "class A {}"))]))
        load(loop, client, NoopLogger(), request)
        client.close()
        remove(root, recursive: true)

        // assert
        @Expect(transport.nextRequest().isNone())
    }

    @TestCase
    func aDocumentChangedWhileALoadRunsIsLeftAloneThoughStillBlank() {
        // arrange
        let root = appModule()
        let loop = editableWith(root, loaded: false)
        let transport = RequestsTransport()
        let client = clientOn(transport)
        let request = loadRequest(loop.state).getOrThrow()
        let path = root.join("src").join("new.cj")
        openBlank(loop, client, path)

        // act: a line typed and taken back, or Neovim's change of a line it is about to type on
        handleDidChange(loop.state, NoopLogger(), DidChangeTextDocumentParams(
            textDocument: VersionedTextDocumentIdentifier(uri: uriOf(path), version: 4),
            contentChanges: [TextDocumentContentChangeEvent.AsTextDocumentContentChangeWholeDocument(
                TextDocumentContentChangeWholeDocument(text: "\n\n"))]))
        load(loop, client, NoopLogger(), request)
        client.close()
        remove(root, recursive: true)

        // assert
        @Expect(transport.nextRequest().isNone())
    }

    @TestCase
    func noLineIsGivenToADocumentWithTextOrOfNoPackageOrWhenTurnedOffOrToAClientApplyingNoEdits() {
        // arrange
        let root = appModule()
        let loose = workspaceOf([("one/a.cj", "package x")])
        let loop = editableWith(root)
        let looseLoop = editableWith(loose)
        let off = editableWith(root)
        off.state.settings = Settings(newFilePackage: false)
        let applying = editableWith(root)
        applying.state.appliesEdits = false
        let transport = RequestsTransport()
        let client = clientOn(transport)

        // act
        openBlank(loop, client, root.join("src").join("typed.cj"), text: "class A {}")
        openBlank(loop, client, root.join("new.cj"))
        openBlank(loop, client, root.join("src").join("my-dir").join("new.cj"))
        openBlank(looseLoop, client, loose.join("two").join("new.cj"))
        openBlank(off, client, root.join("src").join("new.cj"))
        openBlank(applying, client, root.join("src").join("new.cj"))
        client.close()
        remove(root, recursive: true)
        remove(loose, recursive: true)

        // assert
        @Expect(transport.nextRequest().isNone())
    }

    @TestCase
    func aTextIsBlankWhenItIsWhitespaceAlone() {
        @Expect(isBlank(Rope("")))
        @Expect(isBlank(Rope(" \t\r\n\n")))
        @Expect(!isBlank(Rope("\n\nx")))
    }
}
