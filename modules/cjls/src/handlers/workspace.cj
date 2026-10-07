package cjls.handlers

import std.collection.{ArrayList, HashMap}
import std.env.getVariable
import std.runtime.getMaxHeapSize
import std.time.MonoTime
import stdx.log.Logger
import stdxx.Nullable
import fjson.{JsonValue, RawJson}
import rope.Rope
import loupe.workspaceSymbols
import loupe.db.ProjectModel
import loupe.vfs.{CjoFile, FileStamp, isWorkspaceFile, readCjoFiles, readFile, readFiles, VfsPath}
import project_model.{CangjieHome, findCangjieHome, findProjects, hostCfg, PROJECT_JSON, withCangjieHome}
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * How many declarations `workspace/symbol` answers with at most: a query of a letter or two
 * matches most of a workspace, and an editor shows a list to pick from, not thousands.
 */
const WORKSPACE_SYMBOL_LIMIT = 128

/**
 * How much a load reads at most, in bytes, the `.cjo` of the binaries first and the text of the
 * sources then: a sixteenth of the heap. On the runtime's default
 * of 256 MiB, 16 MiB of text was loaded and searched and 32 MiB ran out of memory (D30); a root far
 * wider than a project (a home directory, a test suite of a hundred thousand files) would fill any
 * heap with text alone.
 */
func loadBudget(): Int64 {
    getMaxHeapSize() / 16
}

/**
 * The files of every root are watched, then loaded: a change on disk between the two is reported,
 * rather than lost.
 */
@LspHandler
func handleInitialized(loop: Loop, client: Client, logger: Logger, _: InitializedParams): Unit {
    let state = loop.state
    if (!state.roots.isEmpty() && !state.watchesFiles) {
        logger.info("the client cannot watch files: changes on disk are not seen")
    }
    watch(state, client, logger, state.roots.toArray())
    startLoad(loop, client, logger)
}

/**
 * A file created or changed is read from disk, one deleted is gone, and a directory deleted takes
 * every file under it; a document open in the editor keeps its buffer, whatever the disk says. A
 * file come or gone, or a manifest changed, finds the project again, after.
 */
@LspHandler
func handleDidChangeWatchedFiles(loop: Loop, client: Client, logger: Logger, params: DidChangeWatchedFilesParams): Unit {
    let state = loop.state
    let roots = state.roots.toArray()
    let files = ArrayList<(VfsPath, ?Rope)>()
    for (event in params.changes) {
        let path = VfsPath.fromUri(event.uri)
        match (event.`type`) {
            case FileChangeType.Created | FileChangeType.Changed where isWorkspaceFile(path, roots) ||
                state.inProject(path) =>
                files.add((path, readFile(path)))
            case FileChangeType.Deleted => for (gone in state.filesUnder(path)) {
                files.add((gone, None))
            }
            case _ => ()
        }
    }
    state.setFilesContents(files.filter {file => !state.openDocuments.contains(file[0])}.toArray())
    if (params.changes.iterator().any {event => changesProject(event)}) {
        startLoad(loop, client, logger)
    }
}

/**
 * A folder added is watched and loaded; one removed is no longer watched, and its files are gone
 * but for those open in the editor, and those under another root.
 */
@LspHandler
func handleDidChangeWorkspaceFolders(loop: Loop, client: Client, logger: Logger,
    params: DidChangeWorkspaceFoldersParams): Unit {
    let state = loop.state
    let removed = rootsOf(params.event.removed)
    // after the removal, so a folder both removed and added stays a root
    state.roots.removeIf {root => removed.contains(root)}
    let added = rootsOf(params.event.added).filter {root => !state.roots.contains(root)}
    state.roots.add(all: added)
    unwatch(state, client, logger, removed)
    watch(state, client, logger, added)

    let roots = state.roots.toArray()
    let gone = ArrayList<(VfsPath, ?Rope)>()
    for (root in removed) {
        for (path in state.filesUnder(root) where !state.openDocuments.contains(path) && !isWorkspaceFile(path, roots)) {
            gone.add((path, None))
        }
    }
    state.setFilesContents(gone.toArray())
    startLoad(loop, client, logger)
}

/**
 * The declarations of every file the server knows, open or not, whose names match the query.
 */
@LspHandler[readonly]
func handleWorkspaceSymbol(snap: ServerSnapshot, params: WorkspaceSymbolParams): Nullable<SymbolInformationsOrWorkspaceSymbols> {
    let found = workspaceSymbols(snap.analysis, snap.files, params.query, WORKSPACE_SYMBOL_LIMIT)
    let symbols = found.map {
        found =>
        let text = snap.analysis.sourceFile(found.fileId).getOrThrow().text(snap.analysis)
        workspaceSymbol(text, snap.path(found.fileId).toUri(), found.symbol, snap.encoding)
    }
    Nullable.Value(SymbolInformationsOrWorkspaceSymbols.AsWorkspaceSymbols(symbols))
}

/**
 * Whether `event` may change the project: a manifest changed, or a file or a directory come or gone.
 */
func changesProject(event: FileEvent): Bool {
    let name = VfsPath.fromUri(event.uri).name
    name == "cjpm.toml" || name == PROJECT_JSON || event.`type` != FileChangeType.Changed
}

/**
 * A load as the state was when it began (D58): its number, and where it finds the project.
 */
struct LoadRequest {
    LoadRequest(
        let load: Int64,
        let roots: Array<VfsPath>,
        let linkedProjects: Array<VfsPath>,
        let cangjieHome: ?String,
        /**
         * Whether the client is shown its progress.
         */
        let progress: Bool
    ) {}
}

/**
 * Begins a load, which ends the one before, and runs it on a thread of its own; the user is told
 * of the SDK at its end, if anything is to be told. Nothing to load without roots or linked projects.
 */
func startLoad(loop: Loop, client: Client, logger: Logger): Unit {
    let request = loadRequest(loop.state) ?? return ()
    loop.start(logger) {
        if (let Some(warning) <- load(loop, client, logger, request)) {
            try {
                client.notify(ShowMessageNotificationSpec(), ShowMessageParams(`type`: MessageType.Warning, message: warning))
            } catch (e: Exception) {
                logger.debug("the warning was not shown", [("error", e.toString())])
            }
        }
    }
}

/**
 * Begins a load of the roots and the linked projects of `state`; `None` if there are none.
 */
func loadRequest(state: ServerState): ?LoadRequest {
    if (state.roots.isEmpty() && state.linkedProjects.isEmpty()) {
        return None
    }
    LoadRequest(state.beginLoad(), state.roots.toArray(), state.linkedProjects.toArray(), state.cangjieHome,
        state.workDoneProgress)
}

/**
 * Finds the project of every root again, reads the `.cjo` of its binaries and sets them with it,
 * then reads the files of its packages the server does not know yet, and sets them
 * `LOAD_BATCH` at a time, one revision each, reporting how many are done. The disk is read here,
 * on the thread the load runs on; the state is changed through `loop` alone, between the messages,
 * and once a newer load began nothing more is set.
 *
 * @return what the user is to be told of the SDK, `None` if nothing, or if the load was ended by a newer one
 */
func load(loop: Loop, client: Client, logger: Logger, request: LoadRequest): ?String {
    let progress = WorkDoneProgress.begin(client, logger,
        if (request.progress) {
            "cjls/load/${request.load}"
        } else {
            None
        }, "Loading the workspace")
    try {
        loadProject(loop, logger, request, progress)
    } finally {
        progress.end(Option<String>.None)
    }
}

/**
 * How many files a load sets in one revision: the read loop waits while a batch is set, and every
 * revision cancels what the snapshots before it were computing.
 */
const LOAD_BATCH = 1024

func loadProject(loop: Loop, logger: Logger, request: LoadRequest, progress: WorkDoneProgress): ?String {
    let start = MonoTime.now()
    let budget = loadBudget()
    let home = findCangjieHome(request.cangjieHome, env: {name => getVariable(name)})
    if (let Some(home) <- home) {
        logger.info("found the SDK", [("path", home.path), ("source", home.source)])
    }
    let env = withCangjieHome({name => getVariable(name)}, home)
    let loads = findProjects(request.roots, request.linkedProjects, env: env, budget: budget)
    for (load in loads) {
        logger.info("found a project", [("source", load.source.toString()), ("modules", load.model.modules.size)])
        for (problem in load.problems) {
            logger.warn(problem)
        }
    }
    let model = ProjectModel.merge(loads.map {load => load.model}, hostCfg())
    // `std` is what every file resolves against: the binaries go first
    let cjoFiles = model.cjoFiles()
    let stamps = loop.write {
        state: ServerState =>
        let stamps = HashMap<CjoFile, FileStamp>()
        for (file in cjoFiles) {
            if (let Some(stamp) <- state.binaryStamp(file)) {
                stamps[file] = stamp
            }
        }
        stamps
    }
    let binaries = readCjoFiles(cjoFiles, unchanged: {file, stamp => stamps.get(file) == stamp},
        budget: budget)
    for (problem in binaries.problems) {
        logger.warn(problem)
    }
    let wanted = loop.write {
        state: ServerState =>
        if (state.isLoading(request.load)) {
            state.setProject(model, binaries: binaries.files)
            Some(model.files().filter {path => !state.openDocuments.contains(path) && !state.knows(path)})
        } else {
            Option<Array<VfsPath>>.None
        }
    } ?? return None
    var left = budget - binaries.size
    var loaded = 0
    var truncated = false
    for (from in 0..wanted.size : LOAD_BATCH) {
        let to = min(from + LOAD_BATCH, wanted.size)
        let read = readFiles(wanted[from..to], budget: left)
        left -= read.files.iterator().fold(0) {size, file => size + file[1].size}
        truncated = truncated || read.truncated
        if (!loop.write {state: ServerState => state.setLoadedFiles(request.load, read.files)}) {
            return None
        }
        loaded += read.files.size
        progress.report(to, wanted.size, "${to}/${wanted.size} files")
    }
    // `Some(None)`: the load ended, with nothing to tell
    let warning = loop.write {
        state: ServerState =>
        if (state.endLoad(request.load)) {
            Some(sdkWarning(state, home))
        } else {
            Option<?String>.None
        }
    } ?? return None
    logger.info("loaded the workspace", [("roots", request.roots.size), ("files", loaded),
        ("cjo", binaries.files.size), ("took", MonoTime.now() - start)])
    if (binaries.truncated) {
        logger.warn("the binaries hold more than the server loads: the names of those left out do not resolve",
            [("budget", budget)])
    }
    if (truncated) {
        logger.warn("the workspace holds more text than the server loads: the rest is not seen until opened",
            [("budget", budget), ("roots", String.join(request.roots.map {root => root.toString()}, delimiter: ", "))])
    }
    warning
}

/**
 * What the user is to be told of the SDK, once: none found, or none of its `std` read (another
 * version, the budget); `None` if `std` is there, or the project has a `std` of its own.
 */
func sdkWarning(state: ServerState, home: ?CangjieHome): ?String {
    let project = state.analysis.project() ?? return None
    let db = state.analysis
    if (!project.binaries(db).iterator().any {binary => binary.name == "std"}) {
        return match (home) {
            case None where !project.modules(db).iterator().any {module => module.name(db) == "std"} =>
                "No Cangjie SDK is found: nothing from std resolves. Set `CANGJIE_HOME`, or the SDK in the editor's settings."
            case _ => None
        }
    }
    if (project.binaryPackages(db).iterator().any {pkg => pkg.binary(db) == "std"}) {
        return None
    }
    "No package of std is read from the Cangjie SDK at ${home?.path ?? "the project's std"}: nothing from std resolves. The server's log says why."
}

/**
 * Asks the client to watch the Cangjie files of each root, one registration each, so a root
 * removed is unregistered alone. Nothing, if the client cannot register a watcher at run time.
 */
func watch(state: ServerState, client: Client, logger: Logger, roots: Array<VfsPath>): Unit {
    if (!state.watchesFiles || roots.isEmpty()) {
        return
    }
    let registrations = roots.map {
        root =>
        let id = state.registrationId()
        state.watchers.add(root, id)
        watcherRegistration(id, root, state.relativePatterns)
    }
    client.request(RegistrationRequestSpec(), RegistrationParams(registrations: registrations), logger)
}

/**
 * Asks the client to stop watching the files of each root it watches them for.
 */
func unwatch(state: ServerState, client: Client, logger: Logger, roots: Array<VfsPath>): Unit {
    let unregistrations = ArrayList<Unregistration>()
    for (root in roots) {
        if (let Some(id) <- state.watchers.remove(root)) {
            unregistrations.add(Unregistration(id: id, method: DidChangeWatchedFilesNotificationSpec.METHOD))
        }
    }
    if (!unregistrations.isEmpty()) {
        client.request(UnregistrationRequestSpec(), UnregistrationParams(unregisterations: unregistrations.toArray()),
            logger)
    }
}

/**
 * Watchers of every Cangjie file under `root`, and of the manifests that say how they are built:
 * patterns relative to it if the client takes them, globs of its path otherwise.
 */
func watcherRegistration(id: String, root: VfsPath, relative: Bool): Registration {
    let watchers = ["**/*.cj", "**/cjpm.toml", "**/${PROJECT_JSON}"].map {
        glob =>
        let pattern = if (relative) {
            GlobPattern.AsRelativePattern(RelativePattern(baseUri: WorkspaceFolderOrURI.AsURI(root.toUri()), pattern: glob))
        } else {
            GlobPattern.AsPattern(root.toString().replace("\\", "/").removeSuffix("/") + "/" + glob)
        }
        FileSystemWatcher(globPattern: pattern)
    }
    let options = DidChangeWatchedFilesRegistrationOptions(watchers: watchers)
    Registration(id: id, method: DidChangeWatchedFilesNotificationSpec.METHOD,
        registerOptions: RawJson.of(options).read<JsonValue>())
}

/**
 * The roots `folders` are, those on disk.
 */
func rootsOf(folders: Array<WorkspaceFolder>): Array<VfsPath> {
    folders.map {folder => VfsPath.fromUri(folder.uri)}.filter {path => path.filePath.isSome()}
}
