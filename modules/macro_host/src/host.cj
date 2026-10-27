package macro_host

import std.collection.*
import std.sync.*
import std.time.MonoTime
import stdx.log.Logger
import calca.CancelledException
import jsonrpc.ErrorLogValue
import loupe.db.*
import loupe.hir.{MacroPackage, MacroRequest, macroCallKeyOf, pendingMacroRequests}
import macro_server.*

/**
 * A macro package's library, built: its path and the stamp of what it was built of (`Package.macroLibrary`).
 */
public struct MacroLibrary {
    public MacroLibrary(public let path: String, public let stamp: Int64) {}
}

/**
 * The requests of `files` to send: those not answered yet whose macro has a library (D87: a call whose library is not
 * there is never sent), each with it: a macro package of the workspace one built at the stamp the analysis has for
 * it in `libraries`, by the package, not its name, which two projects may share; a package of std the one
 * `stdLibrary` finds of its name in the SDK; those of the files `isOpen` says the editor shows first, then the
 * others, each in their order.
 */
public func sendableRequests(
    db: AnalysisDatabase,
    files: Array<SourceFile>,
    libraries: HashMap<Package, MacroLibrary>,
    stdLibrary!: (String) -> ?String = { _ => None },
    isOpen!: (SourceFile) -> Bool = { _ => false }
): Array<(SourceFile, MacroRequest, MacroLibrary)> {
    let found = ArrayList<(SourceFile, MacroRequest, MacroLibrary)>()
    for (file in files.filter(isOpen).concat(files.filter { file => !isOpen(file) })) {
        for (request in pendingMacroRequests(db, file)) {
            let library =
                match (request.definition.pkg) {
                    case MacroPackage.WorkspacePackage(pkg) =>
                        libraries
                            .get(pkg)
                            .flatMap {
                                one =>
                                if (one.stamp == pkg.macroLibrary(db)) {
                                    one
                                } else {
                                    None<MacroLibrary>
                                }
                            }
                    case MacroPackage.StdPackage(binary) =>
                        stdLibrary(binary.name(db))
                            .map { path => MacroLibrary(path, request.definition.libraryStamp(db)) }
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
public func expandAll(
    db: AnalysisDatabase,
    requests: Array<(SourceFile, MacroRequest, MacroLibrary)>,
    numbers: TokenNumbers,
    expander: Expander,
    stopped!: () -> Bool = { => false }
): Array<(SourceFile, MacroCallKey, MacroOutput)> {
    let calls =
        requests
            .map {
                one =>
                let (file, request, library) = one
                let (call, layout) =
                    callDataOf(request, request.definition.pkgName(db), library.path, numbers)
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
        changed =
            synchronized (lock) {
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
        synchronized (lock) {
            count++
            armed = (count, MonoTime.now() + timeout, fire)
            changed.notifyAll()
            count
        }
    }

    public func disarm(id: Int64): Bool {
        synchronized (lock) {
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
        synchronized (lock) {
            stopped = true
            changed.notifyAll()
        }
    }

    private func run(): Unit {
        synchronized (lock) {
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
        let server =
            match (process) {
                case Some(running) => running
                case None =>
                    try {
                        let started = startMacroServer(paths)
                        process = started
                        started
                    } catch (e: Exception) {
                        return Unanswered("the macro server did not start: ${e.message}")
                    }
            }
        let id = deadlines.arm(timeout) { => killQuietly(server) }
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
                logger
                    .warn(
                        "the macro server exited",
                        [("macro", call.methodName ?? ""), ("cause", e)]
                    )
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
        if (isStdCall(call)) { std.expand(call) } else { workspace.expand(call) }
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
    call.packageName.map { pkg => pkg.startsWith("std.") } ?? false
}

func killQuietly(server: MacroServerProcess): Unit {
    try {
        server.kill()
    } catch (_: Exception) {
        ()
    }
}
