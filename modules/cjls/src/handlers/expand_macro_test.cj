package cjls.handlers

import std.collection.ArrayList
import std.fs.{exists, File, FileInfo, Path, remove}
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import stdxx.Nullable
import fjson.{JsonValue, RawJson}
import jsonrpc.{Body, RpcException}
import rope.Rope
import loupe.TextRange
import loupe.db.{MacroOutput, MappedSpan, MappedText, SpanOrigin}
import loupe.hir.{macroRequests, setMacroOutputs}
import loupe.vfs.VfsPath
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange
import cjls.lsp_ext.{EXPAND_MACRO_COMMAND, MacroExpansion}
import cjls.server.*

let MACRO_MAIN = "package app\nimport app.ms.*\n@M[x]\nclass C {}\nfunc use(c: C) {}\n"

/**
 * What the macro server answers for `@M[x]`: `class C {}` copied, a class `Gen` and a function `make` written.
 */
let MACRO_OUTPUT = "class C {}\nclass Gen {}\nfunc make<T>(g: Gen, t: T): C { C() }"

/**
 * A cjpm module `app` whose `src/main.cj` calls the workspace's macro `M` of `app.ms`, loaded, the call answered with
 * `MACRO_OUTPUT`; by a client that shows documents and takes code actions if `shows`. The directory stays: the test
 * removes it.
 */
func macroWorkspace(shows!: Bool = true): (ServerState, Path) {
    let dir = workspaceOf([("cjpm.toml", "[package]\nname = \"app\"\n"), ("src/main.cj", MACRO_MAIN),
        ("src/ms/ms.cj", "macro package app.ms\nimport std.ast.*\npublic macro M(attrs: Tokens, input: Tokens): Tokens { input }\n")])
    let loop = initializedWith([dir], watches: false)
    let state = loop.state
    state.showsDocuments = shows
    state.codeActionLiterals = true
    state.locationLinks = true
    initialized(loop, Client(), NoopLogger(), InitializedParams())
    let file = state.snapshot().sourceFile(VfsPath.file(dir.join("src").join("main.cj"))).getOrThrow()
    let request = macroRequests(state.analysis, file).filter {one => one.definition.name == "M"}[0]
    setMacroOutputs(state.analysis, [(request.call, MacroOutput(request.fingerprint, MappedText(MACRO_OUTPUT, [
        MappedSpan(TextRange(0, 10), SpanOrigin.FromSource(TextRange(6, 16))),
        MappedSpan(TextRange(11, MACRO_OUTPUT.size), SpanOrigin.FromCall)
    ]), [], []))])
    (state, dir)
}

func mainOf(dir: Path): Path {
    dir.join("src").join("main.cj")
}

func expandedOf(dir: Path): Path {
    dir.join(".cache").join("cjls").join("expanded").join("src").join("main.cj.macrocall")
}

/**
 * Removes the workspace at `dir`, its read-only expanded file made writable first: Windows removes no read-only file.
 */
func removeWorkspace(dir: Path): Unit {
    if (exists(expandedOf(dir))) {
        setWritable(expandedOf(dir), true)
    }
    remove(dir, recursive: true)
}

func positionIn(path: Path, line: UInt32, character: UInt32): TextDocumentPositionParams {
    TextDocumentPositionParams(textDocument: TextDocumentIdentifier(uri: uriOf(path)),
        position: Position(line: line, character: character))
}

func codeActionsAt(state: ServerState, path: Path, line: UInt32, character: UInt32, only!: ?Array<CodeActionKind> = None): Nullable<Array<CommandOrCodeAction>> {
    let position = Position(line: line, character: character)
    handleCodeAction(state.snapshot(), CodeActionParams(textDocument: TextDocumentIdentifier(uri: uriOf(path)),
        range: LspRange(start: position, end: position), context: CodeActionContext(diagnostics: [], only: only)))
}

func expandCommand(path: Path, line: UInt32, character: UInt32): ExecuteCommandParams {
    ExecuteCommandParams(command: EXPAND_MACRO_COMMAND,
        arguments: [RawJson.of(positionIn(path, line, character)).read<JsonValue>()])
}

/**
 * The `window/showDocument` requests `transport` was written, by now.
 */
func shownDocuments(transport: AnsweringTransport): Array<ShowDocumentParams> {
    let shown = ArrayList<ShowDocumentParams>()
    while (let Some(body) <- transport.written.tryRemove()) {
        if (let Request(request) <- body && request.method == ShowDocumentRequestSpec.METHOD) {
            shown.add(request.params.getOrThrow().read<ShowDocumentParams>())
        }
    }
    shown.toArray()
}

/**
 * Runs `cjls.expandMacro` at the call of `MACRO_MAIN` and opens the file it wrote, as the editor would.
 */
func expandAndOpen(state: ServerState, dir: Path): Unit {
    handleExecuteCommand(state.snapshot(), Client(), NoopLogger(), expandCommand(mainOf(dir), 2, 1))
    let expanded = VfsPath.file(expandedOf(dir))
    state.openDocuments.add(expanded, 1)
    state.setFileContents(expanded, Rope(String.fromUtf8(File.readFrom(expandedOf(dir)))))
}

@Test
class ExpandMacroTest {
    @TestCase
    func aCallAnswersItsExpansionFormatted() {
        // arrange
        let (state, dir) = macroWorkspace()

        // act
        let answer = handleExpandMacro(state.snapshot(), positionIn(mainOf(dir), 2, 1))

        // assert
        removeWorkspace(dir)
        match (answer) {
            case Nullable.Value(expansion) =>
                @Expect(expansion.name, "@M")
                @Expect(expansion.kind, "server")
                @Expect(expansion.expansion, MACRO_OUTPUT)
            case _ => @Fail("no expansion")
        }
    }

    @TestCase
    func offACallIsNull() {
        // arrange
        let (state, dir) = macroWorkspace()

        // act
        let answer = handleExpandMacro(state.snapshot(), positionIn(mainOf(dir), 4, 6))

        // assert
        removeWorkspace(dir)
        @Expect(answer.isNull())
    }

    @TestCase
    func theCallOffersExpandMacroWithItsPosition() {
        // arrange
        let (state, dir) = macroWorkspace()

        // act
        let actions = codeActionsAt(state, mainOf(dir), 2, 1)

        // assert
        removeWorkspace(dir)
        match (actions) {
            case Nullable.Value(found) where found.size == 1 => match (found[0]) {
                case AsCodeAction(action) =>
                    @Expect(action.title, "Expand macro @M")
                    @Expect(action.kind.isNone())
                    let command = action.command.getOrThrow()
                    @Expect(command.command, EXPAND_MACRO_COMMAND)
                    let argument = RawJson.of(command.arguments.getOrThrow()[0]).read<TextDocumentPositionParams>()
                    @Expect(argument.textDocument.uri, uriOf(mainOf(dir)))
                    @Expect(at(argument.position), "2:1")
                case _ => @Fail("not a code action")
            }
            case _ => @Fail("not one action")
        }
    }

    @TestCase
    func noExpandMacroOffACallToAClientThatShowsNoDocumentOrForAKindAskedFor() {
        // arrange
        let (state, dir) = macroWorkspace()
        let (blind, blindDir) = macroWorkspace(shows: false)

        // act
        let offTheCall = codeActionsAt(state, mainOf(dir), 4, 6)
        let quickfix = codeActionsAt(state, mainOf(dir), 2, 1, only: [CodeActionKind.QUICK_FIX])
        let notShown = codeActionsAt(blind, mainOf(blindDir), 2, 1)

        // assert
        removeWorkspace(dir)
        removeWorkspace(blindDir)
        @Expect(offTheCall.isNull())
        @Expect(quickfix.isNull())
        @Expect(notShown.isNull())
    }

    @TestCase
    func theCommandWritesTheExpandedFileReadOnlyAndAsksToShowItsExpansion() {
        // arrange
        let (state, dir) = macroWorkspace()
        let transport = AnsweringTransport(result: {_ => RawJson.of(ShowDocumentResult(success: true))})
        let client = answeredClientOn(transport)

        // act
        let answer = handleExecuteCommand(state.snapshot(), client, NoopLogger(), expandCommand(mainOf(dir), 2, 1))

        // assert
        let path = expandedOf(dir)
        let text = String.fromUtf8(File.readFrom(path))
        let readOnly = !FileInfo(path).canWrite()
        let ignore = String.fromUtf8(File.readFrom(dir.join(".cache").join("cjls").join(".gitignore")))
        let shown = shownDocuments(transport)
        client.close()
        removeWorkspace(dir)
        @Expect(answer, JsonValue.JsonNull)
        @Expect(text, "// generated by cjls from src/main.cj: read-only, regenerated by \"Expand macro\"\n" +
            "package app\nimport app.ms.*\n// @M[x] expanded by cjls\n${MACRO_OUTPUT}\nfunc use(c: C) {}\n")
        @Expect(readOnly)
        @Expect(ignore, "*\n")
        @Expect(shown.size, 1)
        @Expect(shown[0].uri, uriOf(path))
        @Expect(shown[0].takeFocus, Some(true))
        @Expect(shown[0].selection.map {range => "${at(range.start)}-${at(range.end)}"}, Some("4:0-6:37"))
    }

    @TestCase
    func theCommandWritesTheFileAgainOverItsReadOnlyCopy() {
        // arrange
        let (state, dir) = macroWorkspace()
        handleExecuteCommand(state.snapshot(), Client(), NoopLogger(), expandCommand(mainOf(dir), 2, 1))
        state.setFileContents(VfsPath.file(mainOf(dir)), Rope(MACRO_MAIN + "func more() {}\n"))

        // act
        handleExecuteCommand(state.snapshot(), Client(), NoopLogger(), expandCommand(mainOf(dir), 2, 1))

        // assert
        let text = String.fromUtf8(File.readFrom(expandedOf(dir)))
        removeWorkspace(dir)
        @Expect(text.endsWith("func more() {}\n"))
    }

    @TestCase
    func theCommandFailsForAClientThatShowsNoDocument() {
        // arrange
        let (state, dir) = macroWorkspace(shows: false)

        // act
        let failed = try {
            handleExecuteCommand(state.snapshot(), Client(), NoopLogger(), expandCommand(mainOf(dir), 2, 1))
            false
        } catch (_: RpcException) {
            true
        }

        // assert
        let written = exists(expandedOf(dir))
        removeWorkspace(dir)
        @Expect(failed)
        @Expect(!written)
    }
}

@Test
class ExpandedFileNavigationTest {
    @TestCase
    func aNameCopiedFromTheSourceIsHoveredThereOverItsRangeHere() {
        // arrange
        let (state, dir) = macroWorkspace()
        expandAndOpen(state, dir)

        // act
        let (_, range) = markupOf(hoverOf(state, expandedOf(dir), 7, 6))

        // assert
        removeWorkspace(dir)
        @Expect(range, "7:5-7:8")
    }

    @TestCase
    func aNameOfAnExpansionIsHoveredInIt() {
        // arrange
        let (state, dir) = macroWorkspace()
        expandAndOpen(state, dir)

        // act
        let (content, range) = markupOf(hoverOf(state, expandedOf(dir), 6, 6))

        // assert
        removeWorkspace(dir)
        @Expect(content.value.contains("func make<T>(g: Gen, t: T): C"))
        @Expect(range, "6:5-6:9")
    }

    @TestCase
    func aNameTheMacroWroteGoesToItsDeclarationInTheExpandedFile() {
        // arrange
        let (state, dir) = macroWorkspace()
        expandAndOpen(state, dir)

        // act
        let links = linksOf(definitionOf(state, expandedOf(dir), 6, 16))

        // assert
        removeWorkspace(dir)
        @Expect(links.size, 1)
        @Expect(links[0].targetUri, uriOf(expandedOf(dir)))
        @Expect("${at(links[0].targetSelectionRange.start)}-${at(links[0].targetSelectionRange.end)}", "5:6-5:9")
    }

    @TestCase
    func aNameCopiedFromTheSourceHighlightsItsNamesHere() {
        // arrange
        let (state, dir) = macroWorkspace()
        expandAndOpen(state, dir)

        // act
        let answer = handleDocumentHighlight(state.snapshot(), DocumentHighlightParams(
            textDocument: TextDocumentIdentifier(uri: uriOf(expandedOf(dir))), position: Position(line: 7, character: 9)))

        // assert
        removeWorkspace(dir)
        match (answer) {
            case Nullable.Value(found) => @Expect(found.map {one => "${at(one.range.start)}-${at(one.range.end)}"},
                ["7:9-7:10"])
            case _ => @Fail("no highlights")
        }
    }

    @TestCase
    func afterTheSourceChangedTheFileAnswersNothing() {
        // arrange
        let (state, dir) = macroWorkspace()
        expandAndOpen(state, dir)
        state.setFileContents(VfsPath.file(mainOf(dir)), Rope(MACRO_MAIN + "func more() {}\n"))

        // act
        let hover = hoverOf(state, expandedOf(dir), 7, 6)
        let definition = definitionOf(state, expandedOf(dir), 6, 16)

        // assert
        removeWorkspace(dir)
        @Expect(hover.isNull())
        @Expect(definition.isNull())
    }

    @TestCase
    func theExpandedFileIsNoFileOfTheWorkspace() {
        // arrange
        let (state, dir) = macroWorkspace()
        expandAndOpen(state, dir)
        let path = VfsPath.file(expandedOf(dir))

        // act
        let snap = state.snapshot()
        let diagnostics = documentDiagnostics(snap, path)
        let listed = snap.files.map {id => snap.path(id)}.contains(path)

        // assert
        removeWorkspace(dir)
        @Expect(diagnostics.size, 0)
        @Expect(!listed)
    }

    @TestCase
    func aLoadReadsNothingOfTheCacheDirectory() {
        // arrange
        let (state, dir) = macroWorkspace()
        handleExecuteCommand(state.snapshot(), Client(), NoopLogger(), expandCommand(mainOf(dir), 2, 1))
        writeFile(dir, ".cache/cjls/a.cj", "package app\n")

        // act
        let loop = initializedWith([dir], watches: false)
        initialized(loop, Client(), NoopLogger(), InitializedParams())

        // assert
        let knowsExpanded = loop.state.knows(VfsPath.file(expandedOf(dir)))
        let knowsHidden = loop.state.knows(VfsPath.file(dir.join(".cache").join("cjls").join("a.cj")))
        let knowsMain = loop.state.knows(VfsPath.file(mainOf(dir)))
        removeWorkspace(dir)
        @Expect(!knowsExpanded)
        @Expect(!knowsHidden)
        @Expect(knowsMain)
    }
}

@Test
class ShowsDocumentsTest {
    @TestCase[row in [
        (ClientCapabilities(window: WindowClientCapabilities(showDocument: ShowDocumentClientCapabilities(support: true))),
            true),
        (ClientCapabilities(window: WindowClientCapabilities(showDocument: ShowDocumentClientCapabilities(support: false))),
            false),
        (ClientCapabilities(), false)
    ]]
    func aClientShowsDocumentsOnlyIfItSaysSo(row: (ClientCapabilities, Bool)) {
        // arrange
        let (capabilities, shows) = row
        let state = ServerState()

        // act
        handleInitialize(state, Client(), NoopLogger(),
            InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null, capabilities: capabilities))

        // assert
        @Expect(state.showsDocuments, shows)
    }
}
