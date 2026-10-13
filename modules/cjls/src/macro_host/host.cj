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
import loupe.hir.{MacroBuildUnit, MacroRequest, macroBuildPlan, macroCallKeyOf, pendingMacroRequests}
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
 * The requests of `files` to send: those not answered yet whose macro package has a library built at the stamp the
 * analysis has for it (D87: a call whose library is not there is never sent), each with that library.
 */
public func sendableRequests(db: AnalysisDatabase, files: Array<SourceFile>, libraries: HashMap<String, MacroLibrary>): Array<(
    SourceFile, MacroRequest, MacroLibrary)> {
    let found = ArrayList<(SourceFile, MacroRequest, MacroLibrary)>()
    for (file in files) {
        for (request in pendingMacroRequests(db, file)) {
            let pkg = request.definition.pkg
            if (let Some(library) <- libraries.get(pkg.name(db)) && library.stamp == pkg.macroLibrary(db)) {
                found.add((file, request, library))
            }
        }
    }
    found.toArray()
}

/**
 * Sends each of `requests` through `expander`, in their order, until `stopped`: what each got, keyed by its file
 * and call, which outlive the revision the requests are of (D18).
 */
public func expandAll(db: AnalysisDatabase, requests: Array<(SourceFile, MacroRequest, MacroLibrary)>,
    numbers: TokenNumbers, expander: Expander, stopped!: () -> Bool = {=> false}): Array<(SourceFile, MacroCallKey,
    MacroOutput)> {
    let answers = ArrayList<(SourceFile, MacroCallKey, MacroOutput)>()
    for ((file, request, library) in requests) {
        if (stopped()) {
            break
        }
        let (call, layout) = callDataOf(request, request.definition.pkg.name(db), library.path, numbers)
        let output = outputOf(request, layout, expander.expand(call), numbers)
        answers.add((file, macroCallKeyOf(db, request.call), output))
    }
    answers.toArray()
}

/**
 * Ends what runs past its deadline: one thing at a time, armed before it starts and disarmed when it ends, on a
 * thread of its own.
 */
class Watchdog {
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

    /**
     * Runs `fire` once `timeout` passed, unless disarmed before: the id to disarm it by.
     */
    func arm(timeout: Duration, fire: () -> Unit): Int64 {
        synchronized(lock) {
            count++
            armed = (count, MonoTime.now() + timeout, fire)
            changed.notifyAll()
            count
        }
    }

    /**
     * Disarms `id`: `false` if it fired already.
     */
    func disarm(id: Int64): Bool {
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

    func stop(): Unit {
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
    private let watchdog: Watchdog

    public GuardedServer(private let paths: MacroServerPaths, private let timeout: Duration, private let logger: Logger) {
        watchdog = Watchdog(logger)
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
        let id = watchdog.arm(timeout) {=> killQuietly(server)}
        try {
            let result = server.connection.expand(call)
            if (watchdog.disarm(id)) {
                return Answered(result)
            }
            process = None
            Unanswered(pastDeadline())
        } catch (e: Exception) {
            let inTime = watchdog.disarm(id)
            process = None
            killQuietly(server)
            if (inTime) {
                logger.warn("the macro server exited", [("cause", e)])
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
     * Ends the server and the watchdog.
     */
    public func close(): Unit {
        restart()
        watchdog.stop()
    }

    private func pastDeadline(): String {
        "it ran longer than ${timeout.toSeconds()} s"
    }
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
}

/**
 * Runs the workspace's macros (#176, D104) on a thread of its own: once woken, builds the macro packages when the
 * files on disk changed, or once a build another server held the lock of is due again (`Wakeups`), sets the stamps of
 * their libraries, then asks the server every request that can be sent, round after round, each round's answers set
 * in one write, until none is left.
 */
public class MacroHost <: MacroWork {
    private let wakeups = Wakeups()

    // the host's thread alone
    private var server: ?GuardedServer = None
    private var timeout = Duration.Zero
    private var sdk: ?MacroSdk = None
    private var sdkOf = ""
    private let libraries = HashMap<String, MacroLibrary>()
    private let reported = HashSet<String>()

    public MacroHost(private let loop: Loop, private let logger: Logger) {}

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
        wakeups.wake(build)
    }

    public func stop(): Unit {
        wakeups.stop()
    }

    private func isStopped(): Bool {
        wakeups.isStopped()
    }

    private func run(): Unit {
        while (let Some(build) <- wakeups.next()) {
            try {
                cycle(build)
            } catch (_: CancelledException) {
                // the files changed under the snapshot: the write that did it woke the host already
                ()
            } catch (e: Exception) {
                logger.warn("the macros were not expanded", [("cause", e)])
            }
        }
        server?.close()
    }

    private func cycle(build: Bool): Unit {
        let (settings, roots, cacheDirs) = loop.write {
            state: ServerState => (state.settings, state.roots.toArray(), state.cacheDirs)
        }
        if (!settings.macroExpansion) {
            server?.close()
            server = None
            return
        }
        if (build) {
            let ran = buildLibraries(settings, roots, cacheDirs)
            wakeups.built(ran, MonoTime.now())
        }
        let sdk = this.sdk ?? return ()
        if (libraries.isEmpty()) {
            return
        }
        let wanted = Duration.second * settings.macroCallTimeout
        if (server.isNone() || timeout != wanted) {
            server?.close()
            server = GuardedServer(sdk.paths, wanted, logger)
            timeout = wanted
        }
        let expander = server.getOrThrow()
        while (!isStopped()) {
            let snapshot = loop.snapshot()
            let files = snapshot.files |> filterMap {id: FileId => snapshot.analysis.sourceFile(id)} |>
                collectArray
            let requests = sendableRequests(snapshot.analysis, files, libraries)
            if (requests.isEmpty()) {
                return
            }
            logger.debug("expanding macro calls", [("calls", requests.size)])
            let answers = expandAll(snapshot.analysis, requests, sdk.numbers, expander, stopped: {=> isStopped()})
            loop.write {state: ServerState => state.setMacroOutputs(answers)}
        }
    }

    /**
     * Builds what the macros need, as the snapshot's project says (D104), into `macro-build/<cjc --version>` of the
     * cache directory of its first macro package's project (D106), and sets the stamps of the libraries; a new
     * library ends the server, which keeps the old one loaded. `false`, nothing built, while another server builds
     * there: the host tries again later.
     */
    private func buildLibraries(settings: Settings, roots: Array<VfsPath>, cacheDirs: CacheDirs): Bool {
        let snapshot = loop.snapshot()
        let db = snapshot.analysis
        let plan = macroBuildPlan(db)
        if (plan.isEmpty()) {
            return true
        }
        let sdk = sdkFor(settings) ?? return true
        let file = plan.iterator().filter {unit => unit.isMacro}.map {unit => unit.pkg.files(db)}.filter {
            files => !files.isEmpty()
        }.next().flatMap {files => files.get(0)}
        let cacheDir = match (file.flatMap {id => cacheDirs.of(snapshot.path(id), roots)}) {
            case Some(dir) => dir
            case None =>
                report("no directory the macros can be built in: they are not expanded")
                return true
        }
        let out = try {
            cacheDir.macroBuild(dirNameOf(sdk.version))
        } catch (e: FSException) {
            report("${cacheDir.path} cannot be written: ${e.message}")
            return true
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
        let built = match (MacroBuilder(out, sdk.version, sdk.toolchain).build(units.toArray())) {
            case Some(built) => built
            case None =>
                logger.info("another server builds the macros", [("directory", out.toString())])
                return false
        }
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
            server?.restart()
        }
        loop.write {state: ServerState => state.setMacroLibraries(stamps.toArray())}
        true
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
