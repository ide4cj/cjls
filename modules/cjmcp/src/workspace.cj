package cjmcp

import std.collection.{ArrayList, HashMap, HashSet}
import std.env.getVariable
import std.fs.{canonicalize, exists, FileInfo, Path}
import std.sync.{Condition, Mutex}
import stdx.log.{Logger, NoopLogger}
import loupe.db.{AnalysisDatabase, ProjectModel}
import loupe.newFilePackageLine
import loupe.vfs.{ChangedFile, CjoFile, FileStamp, Vfs, VfsPath, readCjoFiles, readFile}
import project_model.{
    findCangjieHome,
    findCangjieSrc,
    findProject,
    withCangjieHome,
    withCangjieSrc,
    withPackageCfgs
}

/**
 * The session's incremental database. Only WorkspaceSession's gate grants access to it.
 */
class WorkspaceState {
    let db = AnalysisDatabase()
    let vfs = Vfs()
    var files: Array<VfsPath> = []
    var problems: Array<String> = []
    var hasExpandedMacros = false
    var revision: Int64 = 0
    var reloadRequested = false
    private var pendingChanges: Array<ChangedFile> = []
    private var model: ?ProjectModel = None
    private var binaryStamps = HashMap<CjoFile, FileStamp>()
    private var loadProblems: Array<String> = []
    private let macros = WorkspaceMacros()

    WorkspaceState(let root: VfsPath) {}

    /**
     * Read disk inputs before changing the database; return whether this opened a workspace revision.
     * Source contents are compared, so same-size edits with preserved mtimes are still observed.
     */
    func synchronize(): Bool {
        if (
            !exists(root.toString()) || !FileInfo(canonicalize(Path(root.toString()))).isDirectory()
        ) {
            throw IllegalArgumentException("workspace directory does not exist: ${root}")
        }
        let found = findCangjieHome(None, env: getVariable)
        let homeEnv = withCangjieHome(getVariable, found)
        let env = withCangjieSrc(homeEnv, findCangjieSrc(None, env: homeEnv))
        let load = findProject(root, env: env)
        let issues = ArrayList<String>(load.problems)
        let next = withPackageCfgs(load.model, issues)
        let binaries =
            readCjoFiles(
                next.cjoFiles(),
                unchanged: { file, stamp => db.binaryStamp(file) == Some(stamp) }
            )
        issues.add(all: binaries.problems)
        let paths = next.files().concat(next.binarySourceFiles())
        let texts = paths.map { path => (path, readFile(path)) }
        for ((path, text) in texts where text.isNone()) {
            issues.add("could not read ${path}")
        }
        let projectChanged = model != Some(next)
        let stamps = binaries.files.map { file => (file.file, file.stamp) }
        let binaryChanged =
            binaryStamps.size != stamps.size ||
                binaries.files.any { file => binaryStamps.get(file.file) != Some(file.stamp) }
        let kept = HashSet<VfsPath>(paths)
        for (id in vfs.files() where !kept.contains(vfs.filePath(id))) {
            vfs.setFileContents(vfs.filePath(id), None)
        }
        for ((path, text) in texts) {
            vfs.setFileContents(path, text)
        }
        pendingChanges = pendingChanges.concat(vfs.takeChanges())
        let changed =
            revision == 0 || projectChanged || binaryChanged || !pendingChanges.isEmpty() ||
                loadProblems != issues.toArray() ||
                reloadRequested
        if (!changed) {
            return false
        }
        // Invalidate retained Python revisions before any input is changed, including on a failed preparation.
        revision++
        hasExpandedMacros = false
        if (projectChanged || binaryChanged) {
            db.setProject(next, vfs.paths, binaries: binaries.files)
        }
        // A failed apply must not lose changes already drained from the VFS.
        db.applyChanges(vfs, pendingChanges)
        pendingChanges = []
        model = next
        binaryStamps = HashMap<CjoFile, FileStamp>(stamps)
        files = next.files()
        loadProblems = issues.toArray()
        reloadRequested = false
        hasExpandedMacros = macros.expand(db, vfs, found.map { home => Path(home.path) }, issues)
        problems = issues.toArray()
        true
    }

    func close(): Unit {
        macros.close()
    }

    func packageLine(path: VfsPath): ?String {
        newFilePackageLine(
            model ?? return None,
            path,
            { file => vfs.fileId(file).flatMap { id => vfs.fileContents(id) } }
        )
    }
}

/**
 * The same gate serializes background preparation, the final disk check, and the entire Python call.
 * Waiting releases the gate; a script owns it until its result has been serialized.
 */
class WorkspaceSession {
    private let gate = Mutex()
    private let changed: Condition
    private let state: WorkspaceState
    private var worker: ?Future<Unit> = None
    private var stopped = false

    WorkspaceSession(root: VfsPath, private let logger!: Logger = NoopLogger()) {
        state = WorkspaceState(root)
        changed =
            synchronized (gate) {
                gate.condition()
            }
    }

    func start(): Unit {
        worker =
            spawn {
                try {
                    poll()
                } catch (e: Exception) {
                    // Structured stdx Logger attributes are an inference gap (#509).
                    logger.error("MCP workspace worker stopped", [("cause", e.message)])
                } catch (e: Error) {
                    logger.error("MCP workspace worker stopped", [("cause", e.toString())]) // #509
                }
            }
        // Yield before the protocol reader blocks in a foreign read (K2).
        sleep(Duration.Zero)
    }

    private func poll(): Unit {
        synchronized (gate) {
            while (!stopped) {
                changed.wait(timeout: 500 * Duration.millisecond)
                if (!stopped) {
                    try {
                        prepare()
                    } catch (e: Exception) {
                        logger
                            .warn(
                                "MCP workspace preparation failed",
                                [("cause", e.message)]
                            ) // #509
                    } catch (e: Error) {
                        logger
                            .warn(
                                "MCP workspace preparation failed",
                                [("cause", e.toString())]
                            ) // #509
                    }
                }
            }
        }
    }

    func withWorkspace<T>(action: (WorkspaceState) -> T): T {
        synchronized (gate) {
            if (stopped) {
                throw IllegalStateException("workspace session is closed")
            }
            prepare()
            action(state)
        }
    }

    private func prepare(): Unit {
        // Edits during a build/expansion must be incorporated before the script starts too.
        try {
            while (state.synchronize()) {}
        } catch (e: Exception) {
            state.reloadRequested = true
            throw e
        } catch (e: Error) {
            state.reloadRequested = true
            throw e
        }
    }

    func close(): Unit {
        synchronized (gate) {
            stopped = true
            changed.notifyAll()
        }
        worker?.get()
        state.close()
    }
}
