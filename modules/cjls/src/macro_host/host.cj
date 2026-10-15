package cjls.macro_host

import std.collection.*
import std.env.getVariable
import std.fs.*
import std.sync.*
import stdx.log.Logger
import calca.CancelledException
import jsonrpc.ErrorLogValue
import loupe.db.*
import loupe.hir.macroBuildPlan
import loupe.vfs.{FileId, VfsPath}
import macro_host.*
import project_model.findCangjieHome
import cjls.server.*

/**
 * Runs the workspace's macros (#176, D104) on a thread of its own, through `macro_host`: once woken, builds the macro packages when the
 * files on disk changed, sets the stamps of their libraries, then asks the server every request that can be sent,
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
    private var server: ?GuardedServer = None
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
            buildLibraries(settings, roots, cacheDirs)
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
            let (snapshot, open) = loop.write {
                state: ServerState => (state.snapshot(), HashSet<VfsPath>(state.openDocuments.keys()))
            }
            let files = snapshot.files |> filterMap {id: FileId => snapshot.analysis.sourceFile(id)} |>
                collectArray
            let requests = sendableRequests(snapshot.analysis, files, libraries,
                isOpen: {file => open.contains(snapshot.path(file.fileId(snapshot.analysis)))})
            if (requests.isEmpty()) {
                return
            }
            logger.debug("expanding macro calls", [("calls", requests.size)])
            // an edit midway ends the round: what came before it is set, and the next round asks what it changed
            let answers = expandAll(snapshot.analysis, requests, sdk.numbers, expander, stopped: {=> isStopped()})
            if (!answers.isEmpty()) {
                loop.write {state: ServerState => state.setMacroOutputs(answers)}
            }
        }
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
            server?.restart()
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
        let found = match (macroSdkIn(Path(home.path))) {
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
