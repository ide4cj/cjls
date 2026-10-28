package cjls.macro_host

import std.collection.*
import std.env.getVariable
import std.fs.*
import std.sync.*
import std.time.MonoTime
import stdx.log.Logger
import calca.CancelledException
import jsonrpc.ErrorLogValue
import loupe.db.*
import loupe.hir.{macroBuildPlan, pendingMacroRequests}
import loupe.vfs.{FileId, VfsPath}
import macro_host.*
import project_model.findCangjieHome
import cjls.server.*

/**
 * Runs the workspace's macros and std's (#176, D104) on a thread of its own, through `macro_host`: once woken, builds
 * the macro packages when the files on disk changed, sets the stamps of their libraries, then asks the server every
 * request that can be sent, those of the open documents first, round after round, each round's answers set in one
 * write, until none is left. An edit ends a round: the answers before it are set, and the next round asks again what
 * it changed.
 */
public class MacroHost <: MacroWork {
    private let lock = Mutex()
    private let woken: Condition
    // guarded by `lock`
    private var work = false
    private var build = false
    private var stopped = false

    // the host's thread alone
    private var servers: ?MacroServers = None
    private var timeout = Duration.Zero
    private var sdk: ?MacroSdk = None
    private var sdkOf = ""
    // by the package, not its name, which two projects may share
    private let libraries = HashMap<Package, MacroLibrary>()
    private let reported = HashSet<String>()

    public MacroHost(private let loop: Loop, private let logger: Logger) {
        // made under `lock`: `condition` throws otherwise
        woken =
            synchronized (lock) {
                lock.condition()
            }
    }

    /**
     * Starts the thread, which builds and expands at once.
     */
    public func start(): Unit {
        wake(true)
        spawn {
            try {
                run()
            } catch (e: Exception) {
                logger.error("the macros stopped", [("cause", e)])
            } catch (e: Error) {
                logger.error("the macros stopped", [("cause", ErrorLogValue(e))])
            }
        }
    }

    public func wake(build: Bool): Unit {
        synchronized (lock) {
            work = true
            this.build = this.build || build
            woken.notifyAll()
        }
    }

    public func stop(): Unit {
        synchronized (lock) {
            stopped = true
            woken.notifyAll()
        }
    }

    private func isStopped(): Bool {
        synchronized (lock) {
            stopped
        }
    }

    private func next(): ?Bool {
        synchronized (lock) {
            while (!work && !stopped) {
                woken.wait()
            }
            if (stopped) {
                return None
            }
            let wanted = build
            work = false
            build = false
            wanted
        }
    }

    private func run(): Unit {
        while (let Some(build) <- next()) {
            try {
                cycle(build)
            } catch (_: CancelledException) {
                // the files changed under the snapshot: the write that did it woke the host already
                ()
            } catch (e: Exception) {
                logger.warn("the macros were not expanded", [("cause", e)])
            }
        }
        servers?.close()
    }

    private func cycle(build: Bool): Unit {
        let (settings, roots, cacheDirs) =
            loop
                .write {
                    state: ServerState =>
                    (state.settings, state.roots.toArray(), state.cacheDirs)
                }
        if (!settings.macroExpansion) {
            servers?.close()
            servers = None
            return
        }
        if (build) {
            buildLibraries(settings, roots, cacheDirs)
        }
        expandPending(settings)
    }

    /**
     * Asks the server every request that can be sent, round after round, each round's answers set in one write, until
     * none is left or the host stops.
     */
    private func expandPending(settings: Settings): Unit {
        let started = MonoTime.now()
        var sent = 0
        var ofStd = 0
        var failed = 0
        while (!isStopped()) {
            let (answered, ofStdAnswered, notExpanded) = round(settings) ?? break
            sent += answered
            ofStd += ofStdAnswered
            failed += notExpanded
        }
        if (sent > 0) {
            logger
                .info(
                    "expanded macro calls",
                    [
                        ("calls", sent),
                        ("std", ofStd),
                        ("failed", failed),
                        ("ms", (MonoTime.now() - started).toMilliseconds())
                    ]
                )
        }
    }

    /**
     * One round on a snapshot of now: `None` once nothing is left to send; else how many calls were answered, of std
     * among them, and not expanded.
     */
    private func round(settings: Settings): ?(Int64, Int64, Int64) {
        let (snapshot, open) =
            loop
                .write {
                    state: ServerState =>
                    (state.snapshot(), HashSet<VfsPath>(state.openDocuments.keys()))
                }
        let db = snapshot.analysis
        let files = macroFiles(db, snapshot.files)
        // nothing to ask, nothing to look for: std's macros need no build, but the SDK. A loop, and what is sent in a
        // frame of its own: at -O2 a lambda here, or the references of a send, crashed the GC that scanned this
        // thread while it parsed (SIGSEGV in `VisitStackRoots`, 1.3.0-alpha.20261014)
        var pending = false
        for (file in files where !pending) {
            pending = !pendingMacroRequests(db, file).isEmpty()
        }
        if (!pending) {
            return None
        }
        send(settings, snapshot, open, files)
    }

    /**
     * Sends what `files` of `snapshot` have to send, those `open` first, and sets the answers.
     */
    private func send(
        settings: Settings,
        snapshot: ServerSnapshot,
        open: HashSet<VfsPath>,
        files: Array<SourceFile>
    ): ?(Int64, Int64, Int64) {
        let db = snapshot.analysis
        let sdk = sdkFor(settings) ?? return None
        let expander = serversOf(sdk, Duration.second * settings.macroCallTimeout)
        let requests =
            sendableRequests(
                db,
                files,
                libraries,
                stdLibrary: { pkg => sdk.stdLibrary(pkg) },
                isOpen: { file => open.contains(snapshot.path(file.fileId(db))) }
            )
        if (requests.isEmpty()) {
            return None
        }
        logger.debug("expanding macro calls", [("calls", requests.size)])
        // an edit midway ends the round: what came before it is set, and the next round asks what it changed
        let answers = expandAll(db, requests, sdk.numbers, expander, stopped: { => isStopped() })
        let ofStd =
            requests[..answers.size].iterator().filter { one => one[1].definition.isStd }.count()
        var failed = 0
        for ((file, key, output) in answers where output.expansion.isNone()) {
            failed++
            logger
                .debug(
                    "a macro call was not expanded",
                    [
                        ("file", snapshot.path(file.fileId(db)).toString()),
                        ("call", key.toString()),
                        ("why", output.diagnostics.get(0)?.message ?? "")
                    ]
                )
        }
        if (!answers.isEmpty()) {
            loop.write { state: ServerState => state.setMacroOutputs(answers) }
        }
        (answers.size, ofStd, failed)
    }

    /**
     * The servers of `sdk` whose calls have the deadline `wanted`: those running, else new ones.
     */
    private func serversOf(sdk: MacroSdk, wanted: Duration): MacroServers {
        if (let Some(running) <- servers && timeout == wanted) {
            return running
        }
        servers?.close()
        let started = MacroServers(sdk.paths, wanted, logger)
        servers = started
        timeout = wanted
        started
    }

    /**
     * Builds what the macros need, as the snapshot's project says (D104), each macro package with what it links into
     * `macro-build/<cjc --version>` of the cache directory of its own project (D106), and sets the stamps of the
     * libraries; a new library ends the server, which keeps the old one loaded. Nothing is built in a directory
     * another server builds in.
     */
    private func buildLibraries(
        settings: Settings,
        roots: Array<VfsPath>,
        cacheDirs: CacheDirs
    ): Unit {
        let snapshot = loop.snapshot()
        let db = snapshot.analysis
        let plan = macroBuildPlan(db)
        if (plan.isEmpty()) {
            return
        }
        let sdk = sdkFor(settings) ?? return ()
        let name = dirNameOf(sdk.version)
        let outs = HashMap<String, ?Path>()
        let built =
            buildPlan(
                db,
                plan,
                { pkg => macroBuildOf(snapshot, pkg, roots, cacheDirs, name, outs) },
                sdk.version,
                sdk.toolchain
            )
        for (dir in built.held) {
            logger.info("another server builds the macros", [("directory", dir.toString())])
        }
        var changed = false
        for ((pkg, result) in built.libraries) {
            let pkgName = pkg.name(db)
            let key = pkg.dir(db).toString()
            match (result) {
                case Built(path, stamp) =>
                    if (libraries.get(pkg)?.stamp != Some(stamp)) {
                        changed = true
                        logger
                            .info(
                                "built a macro package",
                                [("package", pkgName), ("library", path.toString())]
                            )
                    }
                    libraries[pkg] = MacroLibrary(path.toString(), stamp)
                    reported.remove(key)
                case NotBuilt(reason) =>
                    if (reported.add(key)) {
                        // the last library stands: cjc wrote nothing
                        logger
                            .warn(
                                "a macro package did not build",
                                [("package", pkgName), ("reason", reason)]
                            )
                    }
            }
        }
        let stamps = ArrayList<(Package, Int64)>()
        for (unit in plan where unit.isMacro) {
            if (let Some(library) <- libraries.get(unit.pkg)) {
                stamps.add((unit.pkg, library.stamp))
            }
        }
        if (changed) {
            servers?.restartWorkspace()
        }
        loop.write { state: ServerState => state.setMacroLibraries(stamps.toArray()) }
    }

    /**
     * Where the macro package `pkg` is built by the compiler `name`: `macro-build/<name>` of its project's cache
     * directory, each directory's taken once a build, in `outs`, since taking it marks it used; `None`, logged once,
     * if there is none.
     */
    private func macroBuildOf(
        snapshot: ServerSnapshot,
        pkg: Package,
        roots: Array<VfsPath>,
        cacheDirs: CacheDirs,
        name: String,
        outs: HashMap<String, ?Path>
    ): ?Path {
        let db = snapshot.analysis
        let file = pkg.files(db).get(0) ?? return None
        let cacheDir =
            match (cacheDirs.of(snapshot.path(file), roots)) {
                case Some(dir) => dir
                case None =>
                    report(
                        "no directory ${pkg.name(db)} can be built in: its macros are not expanded"
                    )
                    return None
            }
        let buildName = macroBuildName(db, pkg, name)
        let key = "${cacheDir.path}#${buildName}"
        if (let Some(out) <- outs.get(key)) {
            return out
        }
        let out =
            try {
                cacheDir.macroBuild(buildName)
            } catch (e: FSException) {
                report("${cacheDir.path} cannot be written: ${e.message}")
                None<Path>
            }
        outs[key] = out
        out
    }

    /**
     * The SDK the settings name, else the one the environment does, as the load finds it (D40); `None`, logged
     * once, if there is none or it cannot number tokens.
     */
    private func sdkFor(settings: Settings): ?MacroSdk {
        let home =
            findCangjieHome(settings.cangjieHome, env: { name => getVariable(name) }) ??
                return none("no SDK: the workspace's macros are not expanded")
        let key = home.path.toString()
        if (sdkOf == key) {
            return sdk
        }
        sdkOf = key
        sdk = None
        let found =
            match (macroSdkIn(Path(home.path))) {
                case Usable(found) => found
                case Unusable(reason) => return none(reason)
            }
        sdk = found
        found
    }

    private func none(message: String): ?MacroSdk {
        report(message)
        None
    }

    private func report(message: String): Unit {
        if (reported.add(message)) {
            logger.warn(message)
        }
    }
}

/**
 * Every active analysis context of the loaded files needs its own expansion: the same source
 * can resolve a macro against different dependencies in the ordinary and build-script graphs.
 */
func macroFiles(db: AnalysisDatabase, loaded: Array<FileId>): Array<SourceFile> {
    let found = ArrayList<SourceFile>()
    let seen = HashSet<SourceFile>()
    func add(file: ?SourceFile): Unit {
        if (let Some(one) <- file && seen.add(one)) {
            found.add(one)
        }
    }
    for (id in loaded) {
        add(db.sourceFile(id))
    }
    let allowed = HashSet<FileId>(loaded)
    if (let Some(project) <- db.project()) {
        for (module in project.modules(db)) {
            for (pkg in module.packages(db)) {
                for (id in pkg.files(db) where allowed.contains(id)) {
                    add(db.sourceFile(id, context: pkg))
                }
            }
        }
    }
    found.toArray()
}

/** Keep same-named packages from independent dependency selections out of one compiler cache. */
func macroBuildName(db: AnalysisDatabase, pkg: Package, version: String): String {
    if (let Some(project) <- db.project()) {
        for (module in project.modules(db) where module.packages(db).contains(pkg)) {
            let scope = module.resolutionScope(db)
            return if (scope.isEmpty()) { version } else { "${version}-scope-${scope.hashCode()}" }
        }
    }
    version
}
