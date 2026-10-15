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
import loupe.hir.{MacroBuildUnit, MacroPackage, MacroRequest, macroBuildPlan, macroCallKeyOf, pendingMacroRequests}
import loupe.vfs.{FileId, VfsPath}
import macro_server.*
import project_model.{findCangjieHome, hostCfg, sdkTarget}
import cjls.server.*

/**
 * A macro package's library, built: its path and the stamp of what it was built of (`Package.macroLibrary`).
 */
public struct MacroLibrary {
    public MacroLibrary(public let path: String, public let stamp: Int64) {}
}

/**
 * The requests of `files` to send: those not answered yet whose macro has a library (D87: a call whose library is not
 * there is never sent), each with it: a macro package of the workspace one built at the stamp the analysis has for
 * it, a package of std the one `stdLibrary` finds of its name in the SDK; those of the files `isOpen` says the editor
 * shows first, then the others, each in their order.
 */
public func sendableRequests(db: AnalysisDatabase, files: Array<SourceFile>, libraries: HashMap<String, MacroLibrary>,
    stdLibrary!: (String) -> ?String = {_ => None}, isOpen!: (SourceFile) -> Bool = {_ => false}): Array<(SourceFile,
        MacroRequest, MacroLibrary)> {
    let found = ArrayList<(SourceFile, MacroRequest, MacroLibrary)>()
    for (file in files.filter(isOpen).concat(files.filter {file => !isOpen(file)})) {
        for (request in pendingMacroRequests(db, file)) {
            let library = match (request.definition.pkg) {
                case MacroPackage.WorkspacePackage(pkg) => libraries.get(pkg.name(db)).flatMap {
                    one => if (one.stamp == pkg.macroLibrary(db)) {
                        one
                    } else {
                        None<MacroLibrary>
                    }
                }
                case MacroPackage.StdPackage(binary) => stdLibrary(binary.name(db)).map {
                    path => MacroLibrary(path, request.definition.libraryStamp(db))
                }
            }
            if (let Some(one) <- library) {
                found.add((file, request, one))
            }
        }
    }
    found.toArray()
}

/**
 * Sends each of `requests` through `expander`, in their order, until `stopped` or the files change under `db`: what
 * each sent got, keyed by its file and call, which outlive the revision the requests are of (D18). What the calls
 * need of `db` is read before the first is sent, so a change midway loses no answer: each carries its request's
 * fingerprint, and one whose input changed is asked again.
 *
 * @throws CancelledException - if the files change before the first call is sent
 */
public func expandAll(db: AnalysisDatabase, requests: Array<(SourceFile, MacroRequest, MacroLibrary)>,
    numbers: TokenNumbers, expander: Expander, stopped!: () -> Bool = {=> false}): Array<(SourceFile, MacroCallKey,
        MacroOutput)> {
    let calls = requests.map {
        one =>
        let (file, request, library) = one
        let (call, layout) = callDataOf(request, request.definition.pkgName(db), library.path, numbers)
        (file, request, macroCallKeyOf(db, request.call), call, layout)
    }
    let answers = ArrayList<(SourceFile, MacroCallKey, MacroOutput)>()
    for ((file, request, key, call, layout) in calls) {
        if (stopped() || isCancelled(db)) {
            break
        }
        answers.add((file, key, outputOf(request, layout, expander.expand(call), numbers)))
    }
    answers.toArray()
}

/**
 * Whether the files changed under `db`, a snapshot, or a write is waiting for them to.
 */
func isCancelled(db: AnalysisDatabase): Bool {
    try {
        db.unwindIfCancelled()
        false
    } catch (_: CancelledException) {
        true
    }
}

/**
 * What ends a call past its deadline: one at a time, armed before it starts and disarmed when it ends.
 */
interface Deadlines {
    /**
     * Runs `fire` once `timeout` passed, unless disarmed before: the id to disarm it by.
     */
    func arm(timeout: Duration, fire: () -> Unit): Int64

    /**
     * Disarms `id`: `false` if it fired already.
     */
    func disarm(id: Int64): Bool

    func stop(): Unit
}

/**
 * The deadlines of the clock, kept on a thread of its own.
 */
class Watchdog <: Deadlines {
    private let lock = Mutex()
    // made under `lock`: `condition` throws otherwise
    private let changed: Condition
    // guarded by `lock`
    private var armed: ?(Int64, MonoTime, () -> Unit) = None
    private var count = 0
    private var stopped = false

    init(logger: Logger) {
        changed = synchronized(lock) {
            lock.condition()
        }
        spawn {
            try {
                run()
            } catch (e: Exception) {
                logger.error("the macro server's watchdog failed", [("cause", e)])
            } catch (e: Error) {
                logger.error("the macro server's watchdog failed", [("cause", ErrorLogValue(e))])
            }
        }
    }

    public func arm(timeout: Duration, fire: () -> Unit): Int64 {
        synchronized(lock) {
            count++
            armed = (count, MonoTime.now() + timeout, fire)
            changed.notifyAll()
            count
        }
    }

    public func disarm(id: Int64): Bool {
        synchronized(lock) {
            match (armed) {
                case Some((one, _, _)) where one == id =>
                    armed = None
                    changed.notifyAll()
                    true
                case _ => false
            }
        }
    }

    public func stop(): Unit {
        synchronized(lock) {
            stopped = true
            changed.notifyAll()
        }
    }

    private func run(): Unit {
        synchronized(lock) {
            while (!stopped) {
                match (armed) {
                    case None => changed.wait()
                    case Some((_, deadline, fire)) =>
                        let left = deadline - MonoTime.now()
                        if (left > Duration.Zero) {
                            changed.wait(timeout: left)
                        } else {
                            armed = None
                            fire()
                        }
                }
            }
        }
    }
}

/**
 * An `LSPMacroServer` guarded as D87 says: started for the first call and again after it exits, which costs only
 * the call in flight; ended once a call runs past `timeout`, that call answered as failed. Its calls are made one at
 * a time.
 */
public class GuardedServer <: Expander {
    private var process: ?MacroServerProcess = None
    private let paths: MacroServerPaths
    private let timeout: Duration
    private let logger: Logger
    private let deadlines: Deadlines

    public init(paths: MacroServerPaths, timeout: Duration, logger: Logger) {
        this(paths, timeout, logger, Watchdog(logger))
    }

    init(paths: MacroServerPaths, timeout: Duration, logger: Logger, deadlines: Deadlines) {
        this.paths = paths
        this.timeout = timeout
        this.logger = logger
        this.deadlines = deadlines
    }

    public func expand(call: MacroCallData): CallOutcome {
        let server = match (process) {
            case Some(running) => running
            case None => try {
                let started = startMacroServer(paths)
                process = started
                started
            } catch (e: Exception) {
                return Unanswered("the macro server did not start: ${e.message}")
            }
        }
        let id = deadlines.arm(timeout) {=> killQuietly(server)}
        try {
            let result = server.connection.expand(call)
            if (deadlines.disarm(id)) {
                return Answered(result)
            }
            process = None
            Unanswered(pastDeadline())
        } catch (e: Exception) {
            let inTime = deadlines.disarm(id)
            process = None
            killQuietly(server)
            if (inTime) {
                logger.warn("the macro server exited", [("macro", call.methodName ?? ""), ("cause", e)])
                Unanswered("the macro server exited")
            } else {
                Unanswered(pastDeadline())
            }
        }
    }

    /**
     * Ends the server, if one runs: the next call starts another, which loads the libraries anew.
     */
    public func restart(): Unit {
        if (let Some(server) <- process) {
            process = None
            try {
                server.close()
            } catch (_: Exception) {
                killQuietly(server)
            }
        }
    }

    /**
     * Ends the server and the deadlines.
     */
    public func close(): Unit {
        restart()
        deadlines.stop()
    }

    private func pastDeadline(): String {
        "it ran longer than ${timeout.toSeconds()} s"
    }
}

/**
 * Two servers, one running std's macros, the other the workspace's (D123): a process that loads std's library of
 * `@Derive` after one of the workspace's libraries ran may abort (SIGABRT in the runtime, 1.3.0-alpha.20261002), and
 * a rebuilt library of the workspace restarts only its own server.
 */
public class MacroServers <: Expander {
    let std: GuardedServer
    let workspace: GuardedServer

    public MacroServers(paths: MacroServerPaths, timeout: Duration, logger: Logger) {
        std = GuardedServer(paths, timeout, logger)
        workspace = GuardedServer(paths, timeout, logger)
    }

    public func expand(call: MacroCallData): CallOutcome {
        if (isStdCall(call)) {
            std.expand(call)
        } else {
            workspace.expand(call)
        }
    }

    /**
     * Ends the server of the workspace's macros, which keeps its libraries loaded.
     */
    public func restartWorkspace(): Unit {
        workspace.restart()
    }

    public func close(): Unit {
        std.close()
        workspace.close()
    }
}

/**
 * Whether `call` runs a macro of std: one of a package of std (`ServerMacro.isStd`), which a workspace cannot name.
 */
func isStdCall(call: MacroCallData): Bool {
    call.packageName.map {pkg => pkg.startsWith("std.")} ?? false
}

func killQuietly(server: MacroServerProcess): Unit {
    try {
        server.kill()
    } catch (_: Exception) {
        ()
    }
}

/**
 * What the host needs of the SDK: where its server is, how it numbers tokens, its `cjc` and its version.
 */
class MacroSdk {
    MacroSdk(
        let paths: MacroServerPaths,
        let numbers: TokenNumbers,
        let toolchain: SdkToolchain,
        let version: String
    ) {}

    // the library of each package of std asked for, `None` for one the SDK has none of
    private let stdLibraries = HashMap<String, ?String>()

    /**
     * The library of the macros of std's package `pkg` the SDK ships, if it does.
     */
    func stdLibrary(pkg: String): ?String {
        if (let Some(found) <- stdLibraries.get(pkg)) {
            return found
        }
        let found = paths.stdMacroLibrary(pkg).map {path => path.toString()}
        stdLibraries[pkg] = found
        found
    }
}

/**
 * Runs the workspace's macros and std's (#176, D104) on a thread of its own: once woken, builds the macro packages
 * when the files on disk changed, sets the stamps of their libraries, then asks the server every request that can be
 * sent,
 * those of the open documents first, round after round, each round's answers set in one write, until none is left. An
 * edit ends a round: the answers before it are set, and the next round asks again what it changed.
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
    private let libraries = HashMap<String, MacroLibrary>()
    private let reported = HashSet<String>()

    public MacroHost(private let loop: Loop, private let logger: Logger) {
        // made under `lock`: `condition` throws otherwise
        woken = synchronized(lock) {
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
        synchronized(lock) {
            work = true
            this.build = this.build || build
            woken.notifyAll()
        }
    }

    public func stop(): Unit {
        synchronized(lock) {
            stopped = true
            woken.notifyAll()
        }
    }

    private func isStopped(): Bool {
        synchronized(lock) {
            stopped
        }
    }

    private func next(): ?Bool {
        synchronized(lock) {
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
        let (settings, roots, cacheDirs) = loop.write {
            state: ServerState => (state.settings, state.roots.toArray(), state.cacheDirs)
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
            logger.info("expanded macro calls", [("calls", sent), ("std", ofStd), ("failed", failed),
                ("ms", (MonoTime.now() - started).toMilliseconds())])
        }
    }

    /**
     * One round on a snapshot of now: `None` once nothing is left to send; else how many calls were answered, of std
     * among them, and not expanded.
     */
    private func round(settings: Settings): ?(Int64, Int64, Int64) {
        let (snapshot, open) = loop.write {
            state: ServerState => (state.snapshot(), HashSet<VfsPath>(state.openDocuments.keys()))
        }
        let db = snapshot.analysis
        let files = snapshot.files |> filterMap {id: FileId => db.sourceFile(id)} |> collectArray
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
    private func send(settings: Settings, snapshot: ServerSnapshot, open: HashSet<VfsPath>, files: Array<SourceFile>):
        ?(Int64, Int64, Int64) {
        let db = snapshot.analysis
        let sdk = sdkFor(settings) ?? return None
        let expander = serversOf(sdk, Duration.second * settings.macroCallTimeout)
        let requests = sendableRequests(db, files, libraries, stdLibrary: {pkg => sdk.stdLibrary(pkg)},
            isOpen: {file => open.contains(snapshot.path(file.fileId(db)))})
        if (requests.isEmpty()) {
            return None
        }
        logger.debug("expanding macro calls", [("calls", requests.size)])
        // an edit midway ends the round: what came before it is set, and the next round asks what it changed
        let answers = expandAll(db, requests, sdk.numbers, expander, stopped: {=> isStopped()})
        let ofStd = requests[..answers.size].iterator().filter {one => one[1].definition.isStd}.count()
        var failed = 0
        for ((file, key, output) in answers where output.expansion.isNone()) {
            failed++
            logger.debug("a macro call was not expanded", [("file", snapshot.path(file.fileId(db)).toString()),
                ("call", key.toString()), ("why", output.diagnostics.get(0)?.message ?? "")])
        }
        if (!answers.isEmpty()) {
            loop.write {state: ServerState => state.setMacroOutputs(answers)}
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
     * Builds what the macros need, as the snapshot's project says (D104), into `macro-build/<cjc --version>` of the
     * cache directory of its first macro package's project (D106), and sets the stamps of the libraries; a new
     * library ends the server, which keeps the old one loaded. Nothing is built while another server builds there.
     */
    private func buildLibraries(settings: Settings, roots: Array<VfsPath>, cacheDirs: CacheDirs): Unit {
        let snapshot = loop.snapshot()
        let db = snapshot.analysis
        let plan = macroBuildPlan(db)
        if (plan.isEmpty()) {
            return
        }
        let sdk = sdkFor(settings) ?? return ()
        let file = plan.iterator().filter {unit => unit.isMacro}.map {unit => unit.pkg.files(db)}.filter {
            files => !files.isEmpty()
        }.next().flatMap {files => files.get(0)}
        let cacheDir = file.flatMap {id => cacheDirs.of(snapshot.path(id), roots)} ?? return report(
            "no directory the macros can be built in: they are not expanded")
        let out = try {
            cacheDir.macroBuild(dirNameOf(sdk.version))
        } catch (e: FSException) {
            return report("${cacheDir.path} cannot be written: ${e.message}")
        }
        let modules = HashMap<Package, String>()
        for (unit in plan) {
            modules[unit.pkg] = unit.module
        }
        let units = ArrayList<BuildUnit>()
        for (unit in plan) {
            let dir = unit.pkg.dir(db).filePath ?? continue
            units.add(BuildUnit(unit.pkg.name(db), unit.module, dir, unit.isMacro,
                unit.deps.map {dep => (modules.get(dep) ?? unit.module, dep.name(db))},
                unit.binaries |> filterMap {cjo: VfsPath => cjo.filePath} |> collectArray))
        }
        let built = MacroBuilder(out, sdk.version, sdk.toolchain).build(units.toArray()) ?? return logger.info(
            "another server builds the macros", [("directory", out.toString())])
        var changed = false
        for ((name, result) in built) {
            match (result) {
                case Built(path, stamp) =>
                    if (libraries.get(name)?.stamp != Some(stamp)) {
                        changed = true
                        logger.info("built a macro package", [("package", name), ("library", path.toString())])
                    }
                    libraries[name] = MacroLibrary(path.toString(), stamp)
                    reported.remove(name)
                case NotBuilt(reason) => if (reported.add(name)) {
                    // the last library stands: cjc wrote nothing
                    logger.warn("a macro package did not build", [("package", name), ("reason", reason)])
                }
            }
        }
        let stamps = ArrayList<(Package, Int64)>()
        for (unit in plan where unit.isMacro) {
            if (let Some(library) <- libraries.get(unit.pkg.name(db))) {
                stamps.add((unit.pkg, library.stamp))
            }
        }
        if (changed) {
            servers?.restartWorkspace()
        }
        loop.write {state: ServerState => state.setMacroLibraries(stamps.toArray())}
    }

    /**
     * The SDK the settings name, else the one the environment does, as the load finds it (D40); `None`, logged
     * once, if there is none or it cannot number tokens.
     */
    private func sdkFor(settings: Settings): ?MacroSdk {
        let home = findCangjieHome(settings.cangjieHome, env: {name => getVariable(name)}) ?? return none(
            "no SDK: the workspace's macros are not expanded")
        let key = home.path.toString()
        if (sdkOf == key) {
            return sdk
        }
        sdkOf = key
        sdk = None
        let target = sdkTarget(hostCfg()) ?? return none("no SDK target for this host")
        let paths = MacroServerPaths.inSdk(Path(home.path), target)
        let toolchain = SdkToolchain(paths)
        let version = toolchain.version() ?? return none("the SDK's cjc does not run: macros are not expanded")
        let numbers = tokenNumbersOf(paths, version) ?? return none(
            "the SDK numbers its token kinds in a way cjls does not know: macros are not expanded")
        let found = MacroSdk(paths, numbers, toolchain, version)
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
 * A directory's name for the compiler `version` prints: its first line's version, `1.3.0-alpha.20261002001050`,
 * with its backend.
 */
func dirNameOf(version: String): String {
    let first = version.lines().next() ?? version
    let text = match (first.indexOf(": ")) {
        case Some(at) => first[at + 2..]
        case None => first
    }
    let name = StringBuilder()
    for (r in text.runes()) {
        if ((r >= r'a' && r <= r'z') || (r >= r'A' && r <= r'Z') || (r >= r'0' && r <= r'9') || r == r'.' || r == r'-') {
            name.append(r)
        } else if (r == r' ') {
            name.append(r'-')
        }
    }
    name.toString()
}
