package cjmcp

import std.collection.{ArrayList, HashMap, HashSet}
import std.env.getTempDirectory
import std.fs.{Directory, Path, remove}
import stdx.log.NoopLogger
import loupe.Severity
import loupe.db.{AnalysisDatabase, MacroSeverity, Package, SourceFile}
import loupe.hir.{
    macroBuildPlan,
    macroDiagnostics,
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

    func expand(
        db: AnalysisDatabase,
        vfs: Vfs,
        home: ?Path,
        issues: ArrayList<WorkspaceDiagnostic>
    ): Unit {
        let plan = macroBuildPlan(db)
        let files = workspaceMacroFiles(db)
        var pending = false
        for (file in files where !pending) {
            pending = !pendingMacroRequests(db, file).isEmpty()
        }
        if (plan.isEmpty() && !pending) {
            return recordMacroDiagnostics(db, vfs, files, issues)
        }
        let sdkHome =
            match (home) {
                case Some(path) => path
                case None =>
                    issues.add(
                        WorkspaceDiagnostic(
                            "macro",
                            Severity.Error,
                            "no SDK: macros are not expanded",
                            code: Some("macro_sdk")
                        )
                    )
                    return
            }
        if (this.sdkHome != Some(sdkHome)) {
            close()
            this.sdkHome = sdkHome
        }
        if (sdk.isNone()) {
            match (macroSdkIn(sdkHome)) {
                case Usable(found) => sdk = found
                case Unusable(reason) =>
                    issues.add(
                        WorkspaceDiagnostic(
                            "macro",
                            Severity.Error,
                            reason,
                            code: Some("macro_sdk")
                        )
                    )
                    return
            }
        }
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
                    issues.add(
                        WorkspaceDiagnostic(
                            "macro",
                            Severity.Error,
                            "${pkg.name(db)}: macro library not built: ${reason}",
                            code: Some("macro_build")
                        )
                    )
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
            let requests = sendableRequests(
                db,
                files,
                libraries,
                stdLibrary: { pkg => sdk.stdLibrary(pkg) }
            )
            if (requests.isEmpty()) {
                break
            }
            setMacroOutputsByKey(db, expandAll(db, requests, sdk.numbers, servers))
        }
        recordMacroDiagnostics(db, vfs, files, issues)
    }
}

/**
 * A cached failed expansion remains a preparation problem even when there is nothing left to send.
 */
func recordMacroDiagnostics(
    db: AnalysisDatabase,
    vfs: Vfs,
    files: Array<SourceFile>,
    issues: ArrayList<WorkspaceDiagnostic>
): Unit {
    for (file in files) {
        let path = vfs.paths.path(file.fileId(db)).toString()
        let pending = pendingMacroRequests(db, file).map { request => request.call }
        for (call in serverCalls(db, file)) {
            if (macroOutputOf(db, call.call).isNone() || pending.contains(call.call)) {
                issues.add(
                    WorkspaceDiagnostic(
                        "macro",
                        Severity.Error,
                        "@${call.definition.name}: macro call was not sent",
                        code: Some("macro_not_sent"),
                        path: Some(path)
                    )
                )
            }
        }
        // Loupe supplies mapped source ranges and renders hints without parsing stderr locations.
        let text = file.text(db)
        for (diagnostic in macroDiagnostics(db, file)) {
            let line = text.lineOf(diagnostic.range.start)
            let column = diagnostic.range.start - text.lineStart(line)
            let severity =
                if (diagnostic.severity == MacroSeverity.MacroError) {
                    Severity.Error
                } else {
                    Severity.Warning
                }
            issues.add(
                WorkspaceDiagnostic(
                    "macro",
                    severity,
                    diagnostic.message,
                    code: Some("macro_expansion"),
                    path: Some(path),
                    range: Some(diagnostic.range),
                    line: Some(line + 1),
                    column: Some(column + 1)
                )
            )
        }
    }
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
