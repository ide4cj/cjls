package cjls.handlers

import std.collection.{ArrayList, collectArray, HashMap, HashSet}
import std.env.getVariable
import std.fs.{FileInfo, FSException}
import std.time.MonoTime
import stdx.log.Logger
import stdxx.Nullable
import rope.Rope
import loupe.workspaceSymbols
import loupe.db.ProjectModel
import loupe.vfs.{CjoFile, FileStamp, isCangjieFile, isWorkspaceDirectory, isWorkspaceFile, readCjoFiles, readFile,
    readFiles, VfsPath}
import project_model.{CangjieHome, findCangjieHome, findCangjieSrc, findProjects, hostCfg, PROJECT_JSON, ProjectLoad,
    ProjectSource, withCangjieHome, withCangjieSrc}
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * How many declarations `workspace/symbol` answers with at most: a query of a letter or two
 * matches most of a workspace, and an editor shows a list to pick from, not thousands.
 */
const WORKSPACE_SYMBOL_LIMIT = 128

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
 * file or a directory come or gone, a manifest changed, or a `.cjo` of the binaries, finds the
 * project again, after, which reads the files of a directory come (an editor may report the
 * directory alone) and the `.cjo` whose stamps moved.
 */
@LspHandler
func handleDidChangeWatchedFiles(loop: Loop, client: Client, logger: Logger, params: DidChangeWatchedFilesParams): Unit {
    let state = loop.state
    let roots = state.roots.toArray()
    // before the files are dropped: a directory gone changes the project if it held a file known
    let reload = params.changes.iterator().any {event => changesProject(state, event, roots)}
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
    if (reload) {
        startLoad(loop, client, logger)
    }
}

/**
 * A folder added is watched and loaded; one removed is no longer watched, and its files are gone
 * but for those open in the editor, and those under another root: with the project the load sets,
 * in its revision (S12), so no snapshot sees the old project without them.
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

    for (root in removed) {
        state.dropWithProject(state.filesUnder(root).filter {path => !state.openDocuments.contains(path)})
    }
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
 * Whether `event` may change the project: a manifest changed, a `.cjo` of the binaries or a
 * directory of theirs, a Cangjie file come or gone, a directory of the workspace come, or one gone
 * with files the server knows. Whatever else comes or goes under a root is reported too, cjpm's
 * output among it, and finds no project again.
 */
func changesProject(state: ServerState, event: FileEvent, roots: Array<VfsPath>): Bool {
    let path = VfsPath.fromUri(event.uri)
    match (event.`type`) {
        case _ where state.binaryWatch?.covers(path) ?? false => true
        case _ where path.name == "cjpm.toml" || path.name == PROJECT_JSON => true
        case FileChangeType.Changed => false
        case _ where isCangjieFile(path.name) => true
        // what is gone cannot be told a directory or a file, but one holding no file known leaves none to drop
        case FileChangeType.Deleted => isWorkspaceDirectory(path, roots) && !state.filesUnder(path).isEmpty()
        case _ => isWorkspaceDirectory(path, roots) && isDirectory(path)
    }
}

/**
 * Whether a directory is at `path`; a link to one is not (`FileInfo` does not follow it), as the
 * walk does not follow it either.
 */
func isDirectory(path: VfsPath): Bool {
    let filePath = path.filePath ?? return false
    try {
        FileInfo(filePath).isDirectory()
    } catch (_: FSException) {
        false
    }
}

/**
 * A load as the state was when it began (D61): its number, and where it finds the project.
 */
struct LoadRequest {
    LoadRequest(
        let load: Int64,
        let roots: Array<VfsPath>,
        let linkedProjects: Array<VfsPath>,
        let cangjieHome: ?String,
        let cangjieSrc: ?String,
        /**
         * Whether the client is shown its progress.
         */
        let progress: Bool,
        /**
         * How much it reads at most, in bytes.
         */
        let budget: Int64,
        /**
         * The documents open: loose files take them, and their directories, first (D80).
         */
        let open: Array<VfsPath>
    ) {}
}

/**
 * Begins a load, which ends the one before, and runs it on a thread of its own; the user is told
 * of the SDK at its end, if anything is to be told. Nothing to load without roots or linked
 * projects: the files of the folders removed go at once.
 */
func startLoad(loop: Loop, client: Client, logger: Logger): Unit {
    let request = match (loadRequest(loop.state)) {
        case Some(request) => request
        case None =>
            loop.state.dropGone()
            return
    }
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
        state.cangjieSrc, state.workDoneProgress, state.loadBudget, collectArray(state.openDocuments.keys()))
}

/**
 * Finds the project of every root again, reads the `.cjo` of its binaries and sets them with it,
 * the files of the folders removed gone in the same revision, then reads the files of its
 * packages and of its binaries' sources the server does not know yet, and sets them `LOAD_BATCH`
 * at a time, one revision each, reporting how many are done. The disk is read here, on the thread
 * the load runs on; the state is changed through `loop` alone, between the messages, and once a
 * newer load began nothing more is set.
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
        loadProject(loop, client, logger, request, progress)
    } finally {
        // a load ended by a newer one ends its token too: the newer one began a token of its own
        progress.end(Option<String>.None)
    }
}

/**
 * How many files a load sets in one revision: the read loop waits while a batch is set, and every
 * revision cancels what the snapshots before it were computing.
 */
const LOAD_BATCH = 1024

func loadProject(loop: Loop, client: Client, logger: Logger, request: LoadRequest, progress: WorkDoneProgress): ?String {
    let start = MonoTime.now()
    let budget = request.budget
    let home = findCangjieHome(request.cangjieHome, env: {name => getVariable(name)})
    if (let Some(home) <- home) {
        logger.info("found the SDK", [("path", home.path), ("source", home.source)])
    }
    let withHome = withCangjieHome({name => getVariable(name)}, home)
    let src = findCangjieSrc(request.cangjieSrc, env: withHome)
    if (let Some(src) <- src) {
        logger.info("found the sources of std", [("path", src.path), ("source", src.source)])
    }
    let env = withCangjieSrc(withHome, src)
    let loads = findProjects(request.roots, request.linkedProjects, env: env, budget: budget, open: request.open)
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
            state.partialRoots = partialRootsOf(loads)
            watchBinaries(state, client, logger, model)
            Some(openFirst(model.files().concat(model.binarySourceFiles()).filter {
                path => !state.openDocuments.contains(path) && !state.knows(path)
            }, request.open))
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
            // a document opened since the project was found, among the files it left out
            let opened = state.openDocuments.keys().iterator().filter {path => !request.open.contains(path)}
            if (opened.any {path => state.leftOut(path)}) {
                startLoad(loop, client, logger)
            }
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
 * The roots of loose files `loads` left files out of.
 */
func partialRootsOf(loads: Array<ProjectLoad>): Array<VfsPath> {
    let roots = ArrayList<VfsPath>()
    for (load in loads where load.partial) {
        if (let LooseFiles(root) <- load.source) {
            roots.add(root)
        }
    }
    roots.toArray()
}

/**
 * `paths`, those in a directory of a document of `open` first, as they come otherwise: the
 * packages of what the editor shows are read before the budget runs out (D80).
 */
func openFirst(paths: Array<VfsPath>, open: Array<VfsPath>): Array<VfsPath> {
    if (open.isEmpty()) {
        return paths
    }
    let dirs = HashSet<VfsPath>()
    for (path in open) {
        if (let Some(dir) <- path.parent) {
            dirs.add(dir)
        }
    }
    let near = {path: VfsPath => path.parent.map {dir => dirs.contains(dir)} ?? false}
    paths.filter(near).concat(paths.filter {path => !near(path)})
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
 * Keeps the `.cjo` of the binaries of `model`, which an event reloads the project for, and, if they
 * are not those the client watches already, asks it to watch them by a registration of their own,
 * the one before unregistered after: they are outside the roots, as the SDK is, and change with
 * the project. Nothing is registered if the client cannot register a watcher at run time.
 */
func watchBinaries(state: ServerState, client: Client, logger: Logger, model: ProjectModel): Unit {
    let (dirs, files) = binaryPaths(model)
    let before = state.binaryWatch
    if (let Some(before) <- before && before.dirs == dirs && before.files == files) {
        return
    }
    let id: ?String = if (state.watchesFiles && (!dirs.isEmpty() || !files.isEmpty())) {
        state.registrationId()
    } else {
        Option<String>.None
    }
    let watch = BinaryWatch(id, dirs, files)
    state.binaryWatch = watch
    if (let Some(id) <- id) {
        client.request(RegistrationRequestSpec(),
            RegistrationParams(registrations: [binaryRegistration(id, watch, state.relativePatterns)]), logger)
    }
    if (let Some(id) <- before.flatMap {before => before.id}) {
        client.request(UnregistrationRequestSpec(),
            UnregistrationParams(unregisterations: [DidChangeWatchedFilesNotificationSpec().unregistration(id)]),
            logger)
    }
}

/**
 * The directories of the binaries of `model`, and the `.cjo` it names one by one, each once, in
 * the order the model gives them.
 */
func binaryPaths(model: ProjectModel): (Array<VfsPath>, Array<VfsPath>) {
    let seen = HashSet<VfsPath>()
    let dirs = ArrayList<VfsPath>()
    let files = ArrayList<VfsPath>()
    for (binary in model.binaries) {
        dirs.add(all: binary.paths.filter {dir => seen.add(dir)})
        files.add(all: binary.packages.map {pkg => pkg.path}.filter {file => seen.add(file)})
    }
    (dirs.toArray(), files.toArray())
}

/**
 * Watchers of the `.cjo` of `watch`: of every one in a directory, and of a `.cjo` named, created,
 * changed or deleted; and of a directory itself come or gone, as a client reports a directory
 * replaced as a whole (D58), so each is watched from the directory it is in. Patterns relative to
 * that directory if the client takes them, globs of their paths otherwise, which a client that
 * matches a glob only under its workspace folders (Neovim) matches for a binary under one alone.
 */
func binaryRegistration(id: String, watch: BinaryWatch, relative: Bool): Registration {
    let comeOrGone = WatchKind(WatchKind.CREATE.value | WatchKind.DELETE.value)
    let any = WatchKind(WatchKind.CREATE.value | WatchKind.CHANGE.value | WatchKind.DELETE.value)
    let watchers = ArrayList<FileSystemWatcher>()
    for (dir in watch.dirs) {
        match (dir.parent) {
            case Some(parent) =>
                watchers.add(FileSystemWatcher(globPattern: globPattern(parent, dir.name, relative), kind: comeOrGone))
                watchers.add(FileSystemWatcher(globPattern: globPattern(parent, "${dir.name}/*.cjo", relative), kind: any))
            case None => watchers.add(FileSystemWatcher(globPattern: globPattern(dir, "*.cjo", relative), kind: any))
        }
    }
    for (file in watch.files) {
        let parent = file.parent ?? continue
        watchers.add(FileSystemWatcher(globPattern: globPattern(parent, file.name, relative), kind: any))
    }
    DidChangeWatchedFilesNotificationSpec().registration(id,
        DidChangeWatchedFilesRegistrationOptions(watchers: watchers.toArray()))
}

/**
 * The pattern `glob` relative to the directory `base`, or, for a client that takes no relative
 * pattern, a glob of `base`'s path followed by `glob`.
 */
func globPattern(base: VfsPath, glob: String, relative: Bool): GlobPattern {
    if (relative) {
        return GlobPattern.AsRelativePattern(RelativePattern(baseUri: WorkspaceFolderOrURI.AsURI(base.toUri()),
            pattern: glob))
    }
    GlobPattern.AsPattern(base.toString().replace("\\", "/").removeSuffix("/") + "/" + glob)
}

/**
 * Asks the client to stop watching the files of each root it watches them for.
 */
func unwatch(state: ServerState, client: Client, logger: Logger, roots: Array<VfsPath>): Unit {
    let unregistrations = ArrayList<Unregistration>()
    for (root in roots) {
        if (let Some(id) <- state.watchers.remove(root)) {
            unregistrations.add(DidChangeWatchedFilesNotificationSpec().unregistration(id))
        }
    }
    if (!unregistrations.isEmpty()) {
        client.request(UnregistrationRequestSpec(), UnregistrationParams(unregisterations: unregistrations.toArray()),
            logger)
    }
}

/**
 * Watchers of everything come or gone under `root`, since VS Code reports a directory come or gone
 * as one event for it, not one per file under it; and of every Cangjie file and every manifest
 * saying how they are built changed. Patterns relative to `root` if the client takes them, globs of
 * its path otherwise. One kind of event is watched for a path once, so a client sending an event
 * per watcher it matches (VS Code) sends it once.
 */
func watcherRegistration(id: String, root: VfsPath, relative: Bool): Registration {
    let comeOrGone = WatchKind(WatchKind.CREATE.value | WatchKind.DELETE.value)
    let watched = [("**/*", comeOrGone), ("**/*.cj", WatchKind.CHANGE), ("**/cjpm.toml", WatchKind.CHANGE),
        ("**/${PROJECT_JSON}", WatchKind.CHANGE)]
    let watchers = watched.map {
        globAndKind =>
        let (glob, kind) = globAndKind
        FileSystemWatcher(globPattern: globPattern(root, glob, relative), kind: kind)
    }
    DidChangeWatchedFilesNotificationSpec().registration(id, DidChangeWatchedFilesRegistrationOptions(watchers: watchers))
}

/**
 * The roots `folders` are, those on disk.
 */
func rootsOf(folders: Array<WorkspaceFolder>): Array<VfsPath> {
    folders.map {folder => VfsPath.fromUri(folder.uri)}.filter {path => path.filePath.isSome()}
}
