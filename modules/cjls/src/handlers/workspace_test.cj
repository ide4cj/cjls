package cjls.handlers

import std.collection.collectArray
import std.collection.concurrent.LinkedBlockingQueue
import std.env.getTempDirectory
import std.fs.*
import std.sync.AtomicBool
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.{Logger, NoopLogger}
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

/**
 * A transport that answers every request written, with `null` or, if `refuses`, an error, read back
 * by the connection's loop; and keeps everything written, so a test can look at it in order.
 */
class AnsweringTransport <: JsonRpcTransport {
    let written = LinkedBlockingQueue<Body>()
    private let inbound = LinkedBlockingQueue<?Body>()
    private let closed = AtomicBool(false)

    AnsweringTransport(private let refuses!: Bool = false) {}

    public func isClosed(): Bool {
        closed.load()
    }

    public func close(): Unit {
        if (!closed.swap(true)) {
            inbound.add(Option<Body>.None)
        }
    }

    public func read(): ?Body {
        inbound.remove()
    }

    public func write(body: Body): Unit {
        written.add(body)
        if (let Request(request) <- body) {
            let answer = if (refuses) {
                ResultOrError.Error(ResponseError(ErrorCode.METHOD_NOT_FOUND, "no such method"))
            } else {
                ResultOrError.Result(RawJson.NULL)
            }
            inbound.add(ResponseBody(Nullable.Value(request.id), answer).enveloped())
        }
    }
}

/**
 * A client whose requests `transport` answers, on a loop of its own until it is closed.
 */
func answeredClientOn(transport: AnsweringTransport): Client {
    let client = Client()
    let connection = Connection(transport, NoHandler(), NoopLogger())
    client.connect(connection)
    spawn {
        try {
            connection.serve()
        } catch (_: Exception) {}
    }
    client
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
func initializedWith(roots: Array<Path>, watches!: Bool = true, relative!: Bool = true): Loop {
    let state = ServerState()
    handleInitialize(state, InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null,
        capabilities: ClientCapabilities(workspace: WorkspaceClientCapabilities(
            didChangeWatchedFiles: DidChangeWatchedFilesClientCapabilities(dynamicRegistration: watches,
                relativePatternSupport: relative))),
        workspaceFolders: Some(Nullable.Value(roots.map {root => WorkspaceFolder(uri: uriOf(root), name: "ws")}))))
    Loop(state)
}

/**
 * `handleInitialized`, and the load it begins, to its end.
 */
func initialized(loop: Loop, client: Client, logger: Logger, params: InitializedParams): Unit {
    handleInitialized(loop, client, logger, params)
    loop.join()
}

/**
 * `handleDidChangeWatchedFiles`, and the load it may begin, to its end.
 */
func watchedFilesChanged(loop: Loop, logger: Logger, params: DidChangeWatchedFilesParams): Unit {
    handleDidChangeWatchedFiles(loop, Client(), logger, params)
    loop.join()
}

/**
 * `handleDidChangeWorkspaceFolders`, and the load it begins, to its end.
 */
func foldersChanged(loop: Loop, client: Client, logger: Logger, params: DidChangeWorkspaceFoldersParams): Unit {
    handleDidChangeWorkspaceFolders(loop, client, logger, params)
    loop.join()
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
        let folders = initializedWith([a, b]).state.roots.toArray()
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
        let loop = initializedWith([dir], watches: false)
        let state = loop.state
        openIn(state, dir.join("a.cj"), "edited")

        // act
        initialized(loop, Client(), NoopLogger(), InitializedParams())
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
        let loop = initializedWith([a, b])
        let state = loop.state
        let transport = RequestsTransport()
        let client = clientOn(transport)

        // act
        initialized(loop, client, NoopLogger(), InitializedParams())
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
                @Expect(relative.pattern, "**/*")
            case _ => @Fail("not a relative pattern")
        }
        @Expect(state.watchers.get(VfsPath.file(b)), Some(registrations[1].id))
    }

    @TestCase
    func aClientWithoutRelativePatternsGetsAGlobOfTheRootsPath() {
        // arrange
        let root = getTempDirectory().join("cjls-a")
        let loop = initializedWith([root], relative: false)
        let state = loop.state
        let transport = RequestsTransport()
        let client = clientOn(transport)

        // act
        initialized(loop, client, NoopLogger(), InitializedParams())
        client.close()

        // assert
        let request = transport.nextRequest().getOrThrow()
        let registration = request.params.getOrThrow().read<RegistrationParams>().registrations[0]
        match (watchersOf(registration)[0].globPattern) {
            case GlobPattern.AsPattern(glob) => @Expect(glob, VfsPath.file(root).toString().replace("\\", "/") + "/**/*")
            case _ => @Fail("not a glob")
        }
    }

    @TestCase
    func nothingIsRegisteredWithAClientThatCannotWatch() {
        // arrange
        let loop = initializedWith([getTempDirectory().join("cjls-a")], watches: false)
        let state = loop.state
        let transport = RequestsTransport()
        let client = clientOn(transport)

        // act
        initialized(loop, client, NoopLogger(), InitializedParams())
        client.close()

        // assert
        @Expect(transport.nextRequest().isNone())
        @Expect(state.watchers.isEmpty())
    }
}

@Test
class ProjectLoadTest {
    @TestCase
    func aCjpmProjectLoadsTheFilesOfItsPackagesAndItsBuildScriptAndIsWhatTheAnalysisSees() {
        // arrange
        let dir = workspaceOf([("cjpm.toml", "[package]\nname = \"app\"\n"), ("src/main.cj", "main() {}"),
            ("src/util/u.cj", "package app.util"), ("build.cj", "b")])
        let loop = initializedWith([dir], watches: false)
        let state = loop.state


        // act
        initialized(loop, Client(), NoopLogger(), InitializedParams())
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, dir.join("src").join("util").join("u.cj")), Some("package app.util"))
        @Expect(textAt(state, dir.join("build.cj")), Some("b"))
        let modules = state.analysis.project().getOrThrow().modules(state.analysis)
        @Expect(modules.map {module => module.name(state.analysis)}, ["app", "default"])
        @Expect(modules[0].packages(state.analysis).map {pkg => pkg.name(state.analysis)}, ["app", "app.util"])
        @Expect(modules[1].root(state.analysis), VfsPath.file(dir))
    }

    @TestCase
    func aDirectoryOfFilesCreatedIsAPackageOfItsOwn() {
        // arrange
        let dir = workspaceOf([("cjpm.toml", "[package]\nname = \"app\"\n"), ("src/main.cj", "main() {}")])
        let loop = initializedWith([dir], watches: false)
        let state = loop.state
        initialized(loop, Client(), NoopLogger(), InitializedParams())
        let created = writeFile(dir, "src/net/http.cj", "package app.net")

        // act
        watchedFilesChanged(loop, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(created, FileChangeType.Created)]))
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, created), Some("package app.net"))
        let module = state.analysis.project().getOrThrow().modules(state.analysis)[0]
        @Expect(module.packages(state.analysis).map {pkg => pkg.name(state.analysis)}, ["app", "app.net"])
    }

    @TestCase
    func aRootIsWatchedForWhatComesOrGoesAndForItsFilesAndManifestsChanged() {
        // act
        let registration = watcherRegistration("1", VfsPath.file(getTempDirectory().join("ws")), true)

        // assert
        let watched = watchersOf(registration).map {
            watcher => match (watcher.globPattern) {
                case GlobPattern.AsRelativePattern(relative) => "${relative.pattern} ${watcher.kind?.value ?? 0}"
                case _ => ""
            }
        }
        @Expect(watched, ["**/* 5", "**/*.cj 2", "**/cjpm.toml 2", "**/cj-project.json 2"])
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

    @TestCase
    func theSdkOptionIsAPathOrAFileUri() {
        // arrange
        let sdk = getTempDirectory().join("sdk")
        let optionOf = {value: JsonValue => JsonValue.JsonObject([("cangjieHome", value)])}

        // act, assert
        @Expect(cangjieHome(optionOf(JsonValue.JsonString(sdk.toString()))), Some(sdk.toString()))
        @Expect(cangjieHome(optionOf(JsonValue.JsonString(uriOf(sdk)))), VfsPath.file(sdk).filePath.map {it => it.toString()})
        @Expect(cangjieHome(optionOf(JsonValue.JsonString("relative"))), None<String>)
        @Expect(cangjieHome(Option<JsonValue>.None), None<String>)
    }

    @TestCase
    func aProjectWithTheStdOfTheSdkReadHasNothingToTellOfIt() {
        // arrange - std from the SDK the tests run with
        let dir = workspaceOf([("cjpm.toml", "[package]\nname = \"app\"\n"), ("src/main.cj", "main() {}")])
        let loop = initializedWith([dir], watches: false)
        let state = loop.state


        // act
        let warning = load(loop, Client(), NoopLogger(), loadRequest(state).getOrThrow())
        remove(dir, recursive: true)

        // assert
        @Expect(warning, None<String>)
    }
}

@Test
class DidChangeWatchedFilesTest {
    @TestCase
    func aFileCreatedOrChangedIsReadAndOneDeletedIsGone() {
        // arrange
        let dir = workspaceOf([("a.cj", "a"), ("b.cj", "b")])
        let loop = initializedWith([dir], watches: false)
        let state = loop.state
        initialized(loop, Client(), NoopLogger(), InitializedParams())
        let created = writeFile(dir, "src/c.cj", "c")
        writeFile(dir, "a.cj", "changed")
        remove(dir.join("b.cj"))

        // act
        watchedFilesChanged(loop, NoopLogger(), DidChangeWatchedFilesParams(changes: [
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
        let loop = initializedWith([dir], watches: false)
        let state = loop.state
        openIn(state, dir.join("a.cj"), "edited")
        writeFile(dir, "a.cj", "on disk")

        // act
        watchedFilesChanged(loop, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(dir.join("a.cj"), FileChangeType.Changed)]))
        watchedFilesChanged(loop, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(dir.join("a.cj"), FileChangeType.Deleted)]))
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, dir.join("a.cj")), Some("edited"))
    }

    @TestCase
    func aDirectoryDeletedTakesEveryFileUnderIt() {
        // arrange
        let dir = workspaceOf([("a.cj", "a"), ("src/b.cj", "b"), ("src/deep/c.cj", "c")])
        let loop = initializedWith([dir], watches: false)
        let state = loop.state
        initialized(loop, Client(), NoopLogger(), InitializedParams())
        remove(dir.join("src"), recursive: true)

        // act
        watchedFilesChanged(loop, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(dir.join("src"), FileChangeType.Deleted)]))
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, dir.join("a.cj")), Some("a"))
        @Expect(textAt(state, dir.join("src").join("b.cj")), None<String>)
        @Expect(textAt(state, dir.join("src").join("deep").join("c.cj")), None<String>)
    }

    @TestCase
    func aDirectoryCreatedIsReadWhenReportedAlone() {
        // arrange
        let dir = workspaceOf([("a.cj", "a")])
        let loop = initializedWith([dir], watches: false)
        let state = loop.state
        initialized(loop, Client(), NoopLogger(), InitializedParams())
        let b = writeFile(dir, "src/net/b.cj", "b")
        let c = writeFile(dir, "src/net/deep/c.cj", "c")

        // act
        watchedFilesChanged(loop, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(dir.join("src").join("net"), FileChangeType.Created)]))
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, b), Some("b"))
        @Expect(textAt(state, c), Some("c"))
    }

    @TestCase
    func aDirectoryRenamedIsGoneAndReadUnderItsNewName() {
        // arrange
        let dir = workspaceOf([("cjpm.toml", "[package]\nname = \"app\"\n"), ("src/main.cj", "main() {}"),
            ("src/old/b.cj", "package app.old")])
        let loop = initializedWith([dir], watches: false)
        let state = loop.state
        initialized(loop, Client(), NoopLogger(), InitializedParams())
        let old = dir.join("src").join("old")
        let new = dir.join("src").join("new")
        rename(old, to: new)

        // act
        watchedFilesChanged(loop, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(old, FileChangeType.Deleted), fileEvent(new, FileChangeType.Created)]))
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, old.join("b.cj")), None<String>)
        @Expect(textAt(state, new.join("b.cj")), Some("package app.old"))
        let module = state.analysis.project().getOrThrow().modules(state.analysis)[0]
        @Expect(module.packages(state.analysis).map {pkg => pkg.name(state.analysis)}, ["app", "app.new"])
    }

    @TestCase
    func whatHoldsNoFileOfTheWorkspaceComingOrGoingFindsNoProjectAgain() {
        // arrange
        let dir = workspaceOf([("a.cj", "a"), ("old.md", "o"), ("docs/guide.md", "g")])
        let loop = initializedWith([dir], watches: false)
        let state = loop.state
        initialized(loop, Client(), NoopLogger(), InitializedParams())
        let unreported = writeFile(dir, "b.cj", "b")
        writeFile(dir, "target/release/out.o", "o")
        writeFile(dir, ".git/HEAD", "h")
        writeFile(dir, "notes.md", "n")
        remove(dir.join("old.md"))
        remove(dir.join("docs"), recursive: true)

        // act
        watchedFilesChanged(loop, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(dir.join("target").join("release"), FileChangeType.Created),
            fileEvent(dir.join(".git"), FileChangeType.Deleted), fileEvent(dir.join("notes.md"), FileChangeType.Created),
            fileEvent(dir.join("old.md"), FileChangeType.Deleted), fileEvent(dir.join("docs"), FileChangeType.Deleted),
            fileEvent(dir.join("a.cj"), FileChangeType.Changed)]))
        remove(dir, recursive: true)

        // assert: had the project been found again, the file not reported would be read
        @Expect(textAt(state, unreported), None<String>)
    }

    @TestCase
    func aFileTheWalkWouldNotReadIsLeftAlone() {
        // arrange
        let dir = workspaceOf([("target/out.cj", "t"), ("notes.md", "n")])
        let loop = initializedWith([dir], watches: false)
        let state = loop.state


        // act
        watchedFilesChanged(loop, NoopLogger(), DidChangeWatchedFilesParams(changes: [
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
        let loop = initializedWith([first])
        let state = loop.state
        let transport = RequestsTransport()
        let client = clientOn(transport)

        // act
        foldersChanged(loop, client, NoopLogger(), DidChangeWorkspaceFoldersParams(
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
        let loop = initializedWith([dir])
        let state = loop.state
        let transport = RequestsTransport()
        let client = clientOn(transport)
        initialized(loop, client, NoopLogger(), InitializedParams())
        let registered = transport.nextRequest().getOrThrow().params.getOrThrow().read<RegistrationParams>()
        openIn(state, dir.join("a.cj"), "edited")

        // act
        foldersChanged(loop, client, NoopLogger(), DidChangeWorkspaceFoldersParams(
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
        let loop = initializedWith([outer, inner], watches: false)
        let state = loop.state
        initialized(loop, Client(), NoopLogger(), InitializedParams())

        // act
        foldersChanged(loop, Client(), NoopLogger(), DidChangeWorkspaceFoldersParams(
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
        let loop = initializedWith([dir], watches: false)
        let state = loop.state
        initialized(loop, Client(), NoopLogger(), InitializedParams())
        let folder = WorkspaceFolder(uri: uriOf(dir), name: "ws")

        // act
        foldersChanged(loop, Client(), NoopLogger(), DidChangeWorkspaceFoldersParams(
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
        let loop = initializedWith([dir], watches: false)
        let state = loop.state
        initialized(loop, Client(), NoopLogger(), InitializedParams())
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
        let loop = initializedWith([dir], watches: false)
        let state = loop.state
        initialized(loop, Client(), NoopLogger(), InitializedParams())
        remove(dir.join("a.cj"))
        watchedFilesChanged(loop, NoopLogger(), DidChangeWatchedFilesParams(changes: [
            fileEvent(dir.join("a.cj"), FileChangeType.Deleted)]))
        remove(dir, recursive: true)

        // act
        let answer = handleWorkspaceSymbol(state.snapshot(), WorkspaceSymbolParams(query: ""))

        // assert
        let names = workspaceSymbolsOf(answer).map {symbol => symbol.name}
        @Expect(names, ["g"])
    }
}

@Test
class LoadOffTheLoopTest {
    @TestCase
    func aLoadEndedByANewerOneSetsNothingMore() {
        // arrange
        let dir = workspaceOf([("a.cj", "a")])
        let loop = initializedWith([dir], watches: false)
        let state = loop.state
        let older = loadRequest(state).getOrThrow()
        let newer = loadRequest(state).getOrThrow()

        // act
        load(loop, Client(), NoopLogger(), older)
        let olderSet = textAt(state, dir.join("a.cj"))
        load(loop, Client(), NoopLogger(), newer)
        remove(dir, recursive: true)

        // assert
        @Expect(olderSet, None<String>)
        @Expect(textAt(state, dir.join("a.cj")), Some("a"))
    }

    @TestCase
    func aDocumentOpenedWhileALoadRunsKeepsTheEditorsText() {
        // arrange
        let dir = workspaceOf([("a.cj", "on disk"), ("b.cj", "b")])
        let loop = initializedWith([dir], watches: false)
        let state = loop.state
        let request = loadRequest(state).getOrThrow()
        openIn(state, dir.join("a.cj"), "edited")

        // act
        load(loop, Client(), NoopLogger(), request)
        remove(dir, recursive: true)

        // assert
        @Expect(textAt(state, dir.join("a.cj")), Some("edited"))
        @Expect(textAt(state, dir.join("b.cj")), Some("b"))
    }

    @TestCase
    func theClientIsShownTheProgressOfTheLoadInFiles() {
        // arrange
        let dir = workspaceOf([("a.cj", "a"), ("b.cj", "b")])
        let loop = initializedWith([dir], watches: false)
        loop.state.workDoneProgress = true
        let transport = AnsweringTransport()
        let client = answeredClientOn(transport)

        // act
        initialized(loop, client, NoopLogger(), InitializedParams())
        client.close()
        remove(dir, recursive: true)

        // assert
        let create = transport.written.remove().getRequestBodyOrThrow()
        @Expect(create.method, "window/workDoneProgress/create")
        let token = create.params.getOrThrow().read<WorkDoneProgressCreateParams>().token
        let progress = (0..3).iterator().map {
            _: Int64 =>
            let notification = transport.written.remove().getNotificationBodyOrThrow()
            @Expect(notification.method, "$/progress")
            let params = notification.params.getOrThrow().read<ProgressParams>()
            @Expect(params.token, token)
            RawJson.of(params.value)
        } |> collectArray
        @Expect(progress[0].read<WorkDoneProgressBegin>().title, "Loading the workspace")
        @Expect(progress[1].read<WorkDoneProgressReport>().message, Some("2/2 files"))
        @Expect(progress[1].read<WorkDoneProgressReport>().percentage, Some(100u32))
        @Expect(progress[2].read<WorkDoneProgressEnd>().message, None<String>)
    }

    @TestCase
    func aClientThatRefusesTheTokenIsShownNoProgress() {
        // arrange
        let dir = workspaceOf([("a.cj", "a")])
        let loop = initializedWith([dir], watches: false)
        loop.state.workDoneProgress = true
        let transport = AnsweringTransport(refuses: true)
        let client = answeredClientOn(transport)

        // act
        initialized(loop, client, NoopLogger(), InitializedParams())
        client.close()
        remove(dir, recursive: true)

        // assert
        @Expect(transport.written.remove().getRequestBodyOrThrow().method, "window/workDoneProgress/create")
        @Expect(transport.written.tryRemove().isNone())
        @Expect(textAt(loop.state, dir.join("a.cj")), Some("a"))
    }
}
