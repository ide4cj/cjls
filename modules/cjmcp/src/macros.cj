package cjmcp

import std.collection.{ArrayList, HashMap, HashSet}
import std.env.getTempDirectory
import std.fs.{Directory, Path, remove}
import stdx.log.NoopLogger
import loupe.db.{AnalysisDatabase, MacroSeverity, Package, SourceFile}
import loupe.hir.{
    macroBuildPlan,
    macroOutputOf,
    pendingMacroRequests,
    serverCalls,
    setMacroOutputsByKey
}
import loupe.vfs.Vfs
import macro_host.{
    BuiltLibrary,
    MacroLibrary,
    MacroSdk,
    MacroSdkLookup,
    MacroServers,
    buildPlan,
    expandAll,
    macroSdkIn,
    sendableRequests
}

/**
 * Session-owned compiler artifacts and SDK processes; unchanged calls remain database inputs.
 */
class WorkspaceMacros {
    private var temporary: ?Path = None
    private var sdk: ?MacroSdk = None
    private var sdkHome: ?Path = None
    private var servers: ?MacroServers = None
    private var libraries = HashMap<Package, MacroLibrary>()
    private let outs = HashMap<Package, Path>()

    func close(): Unit {
        servers?.close()
        servers = None
        sdk = None
        libraries.clear()
        outs.clear()
        if (let Some(path) <- temporary) {
            remove(path, recursive: true)
            temporary = None
        }
    }

    func expand(db: AnalysisDatabase, vfs: Vfs, home: ?Path, issues: ArrayList<String>): Bool {
        let plan = macroBuildPlan(db)
        let files = workspaceMacroFiles(db)
        var pending = false
        for (file in files where !pending) {
            pending = !pendingMacroRequests(db, file).isEmpty()
        }
        if (plan.isEmpty() && !pending) {
            return recordMacroProblems(db, vfs, files, issues)
        }
        let sdkHome =
            match (home) {
                case Some(path) => path
                case None =>
                    issues.add("no SDK: macros are not expanded")
                    return false
            }
        if (this.sdkHome != Some(sdkHome)) {
            close()
            this.sdkHome = sdkHome
        }
        if (sdk.isNone()) {
            match (macroSdkIn(sdkHome)) {
                case Usable(found) => sdk = found
                case Unusable(reason) =>
                    issues.add(reason)
                    return false
            }
        }
        let before = issues.size
        let sdk = this.sdk.getOrThrow()
        if (temporary.isNone()) {
            temporary = Directory.createTemp(getTempDirectory())
        }
        if (servers.isNone()) {
            servers = MacroServers(sdk.paths, Duration.minute, NoopLogger())
        }
        let servers = this.servers.getOrThrow()
        for (unit in plan where unit.isMacro && !outs.contains(unit.pkg)) {
            outs[unit.pkg] = temporary.getOrThrow().join("${outs.size}")
        }
        let built = buildPlan(db, plan, { pkg => outs.get(pkg) }, sdk.version, sdk.toolchain)
        let next = HashMap<Package, MacroLibrary>()
        var rebuilt = false
        for ((pkg, result) in built.libraries) {
            match (result) {
                case Built(path, stamp) =>
                    next[pkg] = MacroLibrary(path.toString(), stamp)
                    if (libraries.get(pkg)?.stamp != Some(stamp)) {
                        rebuilt = true
                    }
                case NotBuilt(reason) =>
                    issues.add("${pkg.name(db)}: macro library not built: ${reason}")
            }
        }
        if (rebuilt || libraries.size != next.size) {
            servers.restartWorkspace()
        }
        libraries = next
        let stamps = ArrayList<(Package, Int64)>()
        for (unit in plan where unit.isMacro) {
            let stamp = libraries.get(unit.pkg)?.stamp ?? 0
            if (unit.pkg.macroLibrary(db) != stamp) {
                stamps.add((unit.pkg, stamp))
            }
        }
        db
            .batch {
                for ((pkg, stamp) in stamps) {
                    pkg.setMacroLibrary(db).to(stamp)
                }
            }
        while (true) {
            let requests =
                sendableRequests(db, files, libraries, stdLibrary: { pkg => sdk.stdLibrary(pkg) })
            if (requests.isEmpty()) {
                break
            }
            setMacroOutputsByKey(db, expandAll(db, requests, sdk.numbers, servers))
        }
        let complete = recordMacroProblems(db, vfs, files, issues)
        complete && issues.size == before
    }
}

/**
 * A cached failed expansion remains a preparation problem even when there is nothing left to send.
 */
func recordMacroProblems(
    db: AnalysisDatabase,
    vfs: Vfs,
    files: Array<SourceFile>,
    issues: ArrayList<String>
): Bool {
    let before = issues.size
    for (file in files) {
        let pending = pendingMacroRequests(db, file).map { request => request.call }
        for (call in serverCalls(db, file)) {
            let name = "${vfs.paths.path(file.fileId(db))}: @${call.definition.name}"
            match (macroOutputOf(db, call.call)) {
                case None => issues.add("${name}: macro call was not sent")
                case Some(output) =>
                    if (pending.contains(call.call)) {
                        issues.add("${name}: macro call was not sent")
                    }
                    for (
                        diagnostic in output.diagnostics where diagnostic.severity ==
                            MacroSeverity.MacroError
                    ) {
                        issues.add("${name}: ${diagnostic.message}")
                    }
            }
        }
    }
    issues.size == before
}

/**
 * Include every active package context, since a dependency's source can have several resolution scopes.
 */
func workspaceMacroFiles(db: AnalysisDatabase): Array<SourceFile> {
    let files = ArrayList<SourceFile>()
    let seen = HashSet<SourceFile>()
    if (let Some(project) <- db.project()) {
        for (module in project.modules(db)) {
            for (pkg in module.packages(db)) {
                for (id in pkg.files(db)) {
                    if (let Some(file) <- db.sourceFile(id, context: pkg) && seen.add(file)) {
                        files.add(file)
                    }
                }
            }
        }
    }
    files.toArray()
}
