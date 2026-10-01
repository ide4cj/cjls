package cjls.handlers

import std.collection.concurrent.LinkedBlockingQueue
import std.env.getTempDirectory
import std.fs.*
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import stdxx.Nullable
import fjson.{JsonValue, RawJson}
import jsonrpc.*
import rope.{Encoding, Rope}
import loupe.vfs.VfsPath
import cjls.lsp_types.*
import cjls.server.*

/**
 * A transport that keeps the requests written, so a test can look at them; nothing is read, so no
 * request is ever answered.
 */
class RequestsTransport <: JsonRpcTransport {
    private let requests = LinkedBlockingQueue<RequestBody>()
    private let closed = AtomicBool(false)

    /**
     * The next request written, `None` if none was.
     */
    func nextRequest(): ?RequestBody {
        requests.tryRemove()
    }

    public func isClosed(): Bool {
        closed.load()
    }

    public func close(): Unit {
        closed.store(true)
    }

    public func read(): ?Body {
        None
    }

    public func write(body: Body): Unit {
        if (let Request(request) <- body) {
            requests.add(request)
        }
    }
}

class NoHandler <: Handler {
    public func onRequest(_: InboundRequest): Unit {}

    public func onNotification(_: String, _: ?RawJson): Unit {}
}

/**
 * A client whose requests go to `transport`; closed once the test is done, which ends the threads
 * waiting for their answers.
 */
func clientOn(transport: RequestsTransport): Client {
    let client = Client()
    client.connect(Connection(transport, NoHandler(), NoopLogger()))
    client
}

/**
 * A directory of its own under the temporary one, holding `files` (paths relative to it, with `/`
 * between names, and their text).
 */
func workspaceOf(files: Array<(String, String)>): Path {
    let dir = Directory.createTemp(getTempDirectory())
    for ((relative, text) in files) {
        writeFile(dir, relative, text)
    }
    dir
}

func writeFile(dir: Path, relative: String, text: String): Path {
    let path = relative.split("/").fold(dir) {parent, name => parent.join(name)}
    if (!exists(path.parent)) {
        Directory.create(path.parent, recursive: true)
    }
    File.writeTo(path, text.toArray())
    path
}

func uriOf(path: Path): String {
    VfsPath.file(path).toUri()
}

/**
 * A state as `initialize` leaves it for a client with `roots` as its folders, which watches files
 * for the server if `watches`, with relative patterns if `relative`.
 */
func initializedWith(roots: Array<Path>, watches!: Bool = true, relative!: Bool = true): ServerState {
    let state = ServerState()
    handleInitialize(state, InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null,
        capabilities: ClientCapabilities(workspace: WorkspaceClientCapabilities(
            didChangeWatchedFiles: DidChangeWatchedFilesClientCapabilities(dynamicRegistration: watches,
                relativePatternSupport: relative))),
        workspaceFolders: Some(Nullable.Value(roots.map {root => WorkspaceFolder(uri: uriOf(root), name: "ws")}))))
    state
}

func textAt(state: ServerState, path: Path): ?String {
    state.fileContents(VfsPath.file(path))?.toString()
}

func openIn(state: ServerState, path: Path, text: String): Unit {
    handleDidOpen(state, DidOpenTextDocumentParams(
        textDocument: TextDocumentItem(uri: uriOf(path), languageId: LanguageKind("cangjie"), version: 1, text: text)))
}

func fileEvent(path: Path, kind: FileChangeType): FileEvent {
    FileEvent(uri: uriOf(path), `type`: kind)
}

/**
 * The watchers a registration asks for.
 */
func watchersOf(registration: Registration): Array<FileSystemWatcher> {
    RawJson.of(registration.registerOptions.getOrThrow()).read<DidChangeWatchedFilesRegistrationOptions>().watchers
}

func workspaceSymbolsOf(answer: Nullable<SymbolInformationsOrWorkspaceSymbols>): Array<WorkspaceSymbol> {
    match (answer) {
        case Nullable.Value(SymbolInformationsOrWorkspaceSymbols.AsWorkspaceSymbols(symbols)) => symbols
        case _ => throw AssertException("not workspace symbols")
    }
}

@Test
class InitializedTest {
    @TestCase
    func theRootsAreTheFoldersOrElseTheRootUri() {
        // arrange
        let a = getTempDirectory().join("a")
        let b = getTempDirectory().join("b")

        // act
        let folders = initializedWith([a, b]).roots.toArray()
        let state = ServerState()
        handleInitialize(state, InitializeParams(processId: Nullable.Null, rootUri: Nullable.Value(uriOf(a)),
            capabilities: ClientCapabilities(), workspaceFolders: Some(Nullable.Value(Array<WorkspaceFolder>()))))

        // assert
        @Expect(folders, [VfsPath.file(a), VfsPath.file(b)])
        @Expect(state.roots.toArray(), [VfsPath.file(a)])
    }

    @TestCase
    func theServerAdvertisesWorkspaceFoldersAndSymbols() {
        // act
        let capabilities = capabilities(Encoding.Utf16)

        // assert
        let folders = capabilities.workspace.getOrThrow().workspaceFolders.getOrThrow()
        @Expect(folders.supported, Some(true))
        @Expect(match (folders.changeNotifications) {
            case Some(StringOrBoolean.AsBoolean(true)) => true
            case _ => false
        })
        @Expect(match (capabilities.workspaceSymbolProvider) {
            case Some(BooleanOrWorkspaceSymbolOptions.AsBoolean(true)) => true
            case _ => false
        })
    }

    @TestCase
    func theFilesOfEveryRootAreLoadedAndAnOpenOneKeepsTheEditorsText() {
        // arrange
        let dir = workspaceOf([("a.cj", "a"), ("src/b.cj", "b"), ("target/c.cj", "c")])
        let state = initializedWith([dir], watches: false)
        openIn(state, dir.join("a.cj"), "edited")

        // act
        handleInitialized(state, Client(), NoopLogger(), InitializedParams())
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, dir.join("a.cj")), Some("edited"))
        @Expect(textAt(state, dir.join("src").join("b.cj")), Some("b"))
        @Expect(textAt(state, dir.join("target").join("c.cj")), None<String>)
    }

    @TestCase
    func eachRootIsWatchedByARegistrationOfItsOwn() {
        // arrange
        let a = getTempDirectory().join("cjls-a")
        let b = getTempDirectory().join("cjls-b")
        let state = initializedWith([a, b])
        let transport = RequestsTransport()
        let client = clientOn(transport)

        // act
        handleInitialized(state, client, NoopLogger(), InitializedParams())
        client.close()

        // assert
        let request = transport.nextRequest().getOrThrow()
        @Expect(request.method, "client/registerCapability")
        let registrations = request.params.getOrThrow().read<RegistrationParams>().registrations
        @Expect(registrations.map {registration => registration.method},
            ["workspace/didChangeWatchedFiles", "workspace/didChangeWatchedFiles"])
        @Expect(registrations[0].id != registrations[1].id)
        match (watchersOf(registrations[1])[0].globPattern) {
            case GlobPattern.AsRelativePattern(relative) =>
                @Expect(match (relative.baseUri) {
                    case WorkspaceFolderOrURI.AsURI(uri) => uri
                    case _ => ""
                }, uriOf(b))
                @Expect(relative.pattern, "**/*.cj")
            case _ => @Fail("not a relative pattern")
        }
        @Expect(state.watchers.get(VfsPath.file(b)), Some(registrations[1].id))
    }

    @TestCase
    func aClientWithoutRelativePatternsGetsAGlobOfTheRootsPath() {
        // arrange
        let root = getTempDirectory().join("cjls-a")
        let state = initializedWith([root], relative: false)
        let transport = RequestsTransport()
        let client = clientOn(transport)

        // act
        handleInitialized(state, client, NoopLogger(), InitializedParams())
        client.close()

        // assert
        let request = transport.nextRequest().getOrThrow()
        let registration = request.params.getOrThrow().read<RegistrationParams>().registrations[0]
        match (watchersOf(registration)[0].globPattern) {
            case GlobPattern.AsPattern(glob) => @Expect(glob, VfsPath.file(root).toString().replace("\\", "/") + "/**/*.cj")
            case _ => @Fail("not a glob")
        }
    }

    @TestCase
    func nothingIsRegisteredWithAClientThatCannotWatch() {
        // arrange
        let state = initializedWith([getTempDirectory().join("cjls-a")], watches: false)
        let transport = RequestsTransport()
        let client = clientOn(transport)

        // act
        handleInitialized(state, client, NoopLogger(), InitializedParams())
        client.close()

        // assert
        @Expect(transport.nextRequest().isNone())
        @Expect(state.watchers.isEmpty())
    }
}

@Test
class ProjectLoadTest {
    @TestCase
    func aCjpmProjectLoadsTheFilesOfItsPackagesAndIsWhatTheAnalysisSees() {
        // arrange
        let dir = workspaceOf([("cjpm.toml", "[package]\nname = \"app\"\n"), ("src/main.cj", "main() {}"),
            ("src/util/u.cj", "package app.util"), ("build.cj", "b")])
        let state = initializedWith([dir], watches: false)

        // act
        handleInitialized(state, Client(), NoopLogger(), InitializedParams())
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, dir.join("src").join("util").join("u.cj")), Some("package app.util"))
        @Expect(textAt(state, dir.join("build.cj")), None<String>)
        let project = state.analysis.project().getOrThrow()
        let module = project.modules(state.analysis)[0]
        @Expect(module.name(state.analysis), "app")
        @Expect(module.packages(state.analysis).map {pkg => pkg.name(state.analysis)}, ["app", "app.util"])
    }

    @TestCase
    func aDirectoryOfFilesCreatedIsAPackageOfItsOwn() {
        // arrange
        let dir = workspaceOf([("cjpm.toml", "[package]\nname = \"app\"\n"), ("src/main.cj", "main() {}")])
        let state = initializedWith([dir], watches: false)
        handleInitialized(state, Client(), NoopLogger(), InitializedParams())
        let created = writeFile(dir, "src/net/http.cj", "package app.net")

        // act
        handleDidChangeWatchedFiles(state, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(created, FileChangeType.Created)]))
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, created), Some("package app.net"))
        let module = state.analysis.project().getOrThrow().modules(state.analysis)[0]
        @Expect(module.packages(state.analysis).map {pkg => pkg.name(state.analysis)}, ["app", "app.net"])
    }

    @TestCase
    func aRootIsWatchedForItsManifestsToo() {
        // act
        let registration = watcherRegistration("1", VfsPath.file(getTempDirectory().join("ws")), true)

        // assert
        let patterns = watchersOf(registration).map {
            watcher => match (watcher.globPattern) {
                case GlobPattern.AsRelativePattern(relative) => relative.pattern
                case _ => ""
            }
        }
        @Expect(patterns, ["**/*.cj", "**/cjpm.toml", "**/cj-project.json"])
    }

    @TestCase
    func linkedProjectsArePathsOrFileUris() {
        // arrange
        let a = getTempDirectory().join("a")
        let b = getTempDirectory().join("b").join("cj-project.json")
        let options = JsonValue.JsonObject([("linkedProjects", JsonValue.JsonArray([
            JsonValue.JsonString(a.toString()), JsonValue.JsonString(uriOf(b)), JsonValue.JsonString("relative"),
            JsonValue.JsonInteger(1)]))])

        // act
        let linked = linkedProjects(options)

        // assert
        @Expect(linked, [VfsPath.file(a), VfsPath.file(b)])
        @Expect(linkedProjects(Option<JsonValue>.None).size, 0)
    }
}

@Test
class DidChangeWatchedFilesTest {
    @TestCase
    func aFileCreatedOrChangedIsReadAndOneDeletedIsGone() {
        // arrange
        let dir = workspaceOf([("a.cj", "a"), ("b.cj", "b")])
        let state = initializedWith([dir], watches: false)
        handleInitialized(state, Client(), NoopLogger(), InitializedParams())
        let created = writeFile(dir, "src/c.cj", "c")
        writeFile(dir, "a.cj", "changed")
        remove(dir.join("b.cj"))

        // act
        handleDidChangeWatchedFiles(state, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(created, FileChangeType.Created), fileEvent(dir.join("a.cj"), FileChangeType.Changed),
            fileEvent(dir.join("b.cj"), FileChangeType.Deleted)]))
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, created), Some("c"))
        @Expect(textAt(state, dir.join("a.cj")), Some("changed"))
        @Expect(textAt(state, dir.join("b.cj")), None<String>)
    }

    @TestCase
    func anOpenDocumentKeepsTheEditorsText() {
        // arrange
        let dir = workspaceOf([("a.cj", "a")])
        let state = initializedWith([dir], watches: false)
        openIn(state, dir.join("a.cj"), "edited")
        writeFile(dir, "a.cj", "on disk")

        // act
        handleDidChangeWatchedFiles(state, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(dir.join("a.cj"), FileChangeType.Changed)]))
        handleDidChangeWatchedFiles(state, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(dir.join("a.cj"), FileChangeType.Deleted)]))
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, dir.join("a.cj")), Some("edited"))
    }

    @TestCase
    func aDirectoryDeletedTakesEveryFileUnderIt() {
        // arrange
        let dir = workspaceOf([("a.cj", "a"), ("src/b.cj", "b"), ("src/deep/c.cj", "c")])
        let state = initializedWith([dir], watches: false)
        handleInitialized(state, Client(), NoopLogger(), InitializedParams())
        remove(dir.join("src"), recursive: true)

        // act
        handleDidChangeWatchedFiles(state, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(dir.join("src"), FileChangeType.Deleted)]))
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, dir.join("a.cj")), Some("a"))
        @Expect(textAt(state, dir.join("src").join("b.cj")), None<String>)
        @Expect(textAt(state, dir.join("src").join("deep").join("c.cj")), None<String>)
    }

    @TestCase
    func aFileTheWalkWouldNotReadIsLeftAlone() {
        // arrange
        let dir = workspaceOf([("target/out.cj", "t"), ("notes.md", "n")])
        let state = initializedWith([dir], watches: false)

        // act
        handleDidChangeWatchedFiles(state, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(dir.join("target").join("out.cj"), FileChangeType.Created),
            fileEvent(dir.join("notes.md"), FileChangeType.Created)]))
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, dir.join("target").join("out.cj")), None<String>)
        @Expect(textAt(state, dir.join("notes.md")), None<String>)
    }
}

@Test
class DidChangeWorkspaceFoldersTest {
    @TestCase
    func aFolderAddedIsLoadedAndWatched() {
        // arrange
        let first = workspaceOf([("a.cj", "a")])
        let added = workspaceOf([("b.cj", "b")])
        let state = initializedWith([first])
        let transport = RequestsTransport()
        let client = clientOn(transport)

        // act
        handleDidChangeWorkspaceFolders(state, client, NoopLogger(), DidChangeWorkspaceFoldersParams(
            event: WorkspaceFoldersChangeEvent(added: [WorkspaceFolder(uri: uriOf(added), name: "b")], removed: [])))
        client.close()
        remove(first, recursive: true)
        remove(added, recursive: true)

        // assert
        @Expect(textAt(state, added.join("b.cj")), Some("b"))
        @Expect(state.roots.toArray(), [VfsPath.file(first), VfsPath.file(added)])
        let request = transport.nextRequest().getOrThrow()
        @Expect(request.method, "client/registerCapability")
        @Expect(state.watchers.contains(VfsPath.file(added)))
    }

    @TestCase
    func aFolderRemovedIsUnwatchedAndItsFilesGoButForTheOpenOnes() {
        // arrange
        let dir = workspaceOf([("a.cj", "a"), ("b.cj", "b")])
        let state = initializedWith([dir])
        let transport = RequestsTransport()
        let client = clientOn(transport)
        handleInitialized(state, client, NoopLogger(), InitializedParams())
        let registered = transport.nextRequest().getOrThrow().params.getOrThrow().read<RegistrationParams>()
        openIn(state, dir.join("a.cj"), "edited")

        // act
        handleDidChangeWorkspaceFolders(state, client, NoopLogger(), DidChangeWorkspaceFoldersParams(
            event: WorkspaceFoldersChangeEvent(added: [], removed: [WorkspaceFolder(uri: uriOf(dir), name: "ws")])))
        client.close()
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, dir.join("a.cj")), Some("edited"))
        @Expect(textAt(state, dir.join("b.cj")), None<String>)
        @Expect(state.roots.isEmpty())
        let request = transport.nextRequest().getOrThrow()
        @Expect(request.method, "client/unregisterCapability")
        let unregistration = request.params.getOrThrow().read<UnregistrationParams>().unregisterations[0]
        @Expect(unregistration.id, registered.registrations[0].id)
        @Expect(unregistration.method, "workspace/didChangeWatchedFiles")
    }

    @TestCase
    func aFileUnderAnotherRootStaysWhenAFolderIsRemoved() {
        // arrange - `inner` is a root of its own, inside `outer`
        let outer = workspaceOf([("a.cj", "a"), ("inner/b.cj", "b")])
        let inner = outer.join("inner")
        let state = initializedWith([outer, inner], watches: false)
        handleInitialized(state, Client(), NoopLogger(), InitializedParams())

        // act
        handleDidChangeWorkspaceFolders(state, Client(), NoopLogger(), DidChangeWorkspaceFoldersParams(
            event: WorkspaceFoldersChangeEvent(added: [], removed: [WorkspaceFolder(uri: uriOf(outer), name: "outer")])))
        remove(outer, recursive: true)

        // assert
        @Expect(textAt(state, outer.join("a.cj")), None<String>)
        @Expect(textAt(state, inner.join("b.cj")), Some("b"))
    }

    @TestCase
    func aFolderRemovedAndAddedAtOnceStaysARoot() {
        // arrange
        let dir = workspaceOf([("a.cj", "a")])
        let state = initializedWith([dir], watches: false)
        handleInitialized(state, Client(), NoopLogger(), InitializedParams())
        let folder = WorkspaceFolder(uri: uriOf(dir), name: "ws")

        // act
        handleDidChangeWorkspaceFolders(state, Client(), NoopLogger(), DidChangeWorkspaceFoldersParams(
            event: WorkspaceFoldersChangeEvent(added: [folder], removed: [folder])))
        remove(dir, recursive: true)

        // assert
        @Expect(state.roots.toArray(), [VfsPath.file(dir)])
        @Expect(textAt(state, dir.join("a.cj")), Some("a"))
    }
}

@Test
class WorkspaceSymbolTest {
    @TestCase
    func aDeclarationOfAFileNotOpenIsFoundAtItsName() {
        // arrange
        let dir = workspaceOf([("a.cj", "class Outer {\n    func target() {}\n}\n")])
        let state = initializedWith([dir], watches: false)
        handleInitialized(state, Client(), NoopLogger(), InitializedParams())
        remove(dir, recursive: true)

        // act
        let answer = handleWorkspaceSymbol(state.snapshot(), WorkspaceSymbolParams(query: "targ"))

        // assert
        let symbols = workspaceSymbolsOf(answer)
        @Expect(symbols.size, 1)
        @Expect(symbols[0].name, "target")
        @Expect(symbols[0].containerName, Some("Outer"))
        @Expect(symbols[0].kind, SymbolKind.Method)
        let location = match (symbols[0].location) {
            case LocationOrLocationUriOnly.AsLocation(location) => location
            case _ => throw AssertException("not a location")
        }
        @Expect(location.uri, uriOf(dir.join("a.cj")))
        @Expect(location.range.start.line, 1u32)
        @Expect(location.range.start.character, 9u32)
        @Expect(location.range.end.character, 15u32)
    }

    @TestCase
    func aFileGoneIsSearchedNoMore() {
        // arrange
        let dir = workspaceOf([("a.cj", "func f() {}\n"), ("b.cj", "func g() {}\n")])
        let state = initializedWith([dir], watches: false)
        handleInitialized(state, Client(), NoopLogger(), InitializedParams())
        remove(dir.join("a.cj"))
        handleDidChangeWatchedFiles(state, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(dir.join("a.cj"), FileChangeType.Deleted)]))
        remove(dir, recursive: true)

        // act
        let answer = handleWorkspaceSymbol(state.snapshot(), WorkspaceSymbolParams(query: ""))

        // assert
        let names = workspaceSymbolsOf(answer).map {symbol => symbol.name}
        @Expect(names, ["g"])
    }
}
