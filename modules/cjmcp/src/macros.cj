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
    MacroSdkLookup,
    MacroServers,
    buildPlan,
    expandAll,
    macroSdkIn,
    sendableRequests
}

/**
 * Finish expansion before publishing a disk revision. Each load owns fresh build artifacts and SDK processes,
 * so reloading cannot reuse loaded macro code or mutate a retained AnalysisRevision.
 */
func expandWorkspaceMacros(
    db: AnalysisDatabase,
    vfs: Vfs,
    home: ?Path,
    issues: ArrayList<String>
): Bool {
    let plan = macroBuildPlan(db)
    let files = workspaceMacroFiles(db)
    var pending = false
    for (file in files where !pending) {
        pending = !pendingMacroRequests(db, file).isEmpty()
    }
    if (plan.isEmpty() && !pending) {
        return true
    }
    let sdkHome =
        match (home) {
            case Some(path) => path
            case None =>
                issues.add("no SDK: macros are not expanded")
                return false
        }
    let sdk =
        match (macroSdkIn(sdkHome)) {
            case Usable(found) => found
            case Unusable(reason) =>
                issues.add(reason)
                return false
        }
    let before = issues.size
    let temporary = Directory.createTemp(getTempDirectory())
    let servers = MacroServers(sdk.paths, Duration.minute, NoopLogger())
    try {
        let outs = HashMap<Package, Path>()
        for (index in 0..plan.size where plan[index].isMacro) {
            // Separate outputs also isolate same-named packages from independent dependency selections.
            outs[plan[index].pkg] = temporary.join("${index}")
        }
        let built = buildPlan(db, plan, { pkg => outs.get(pkg) }, sdk.version, sdk.toolchain)
        let libraries = HashMap<Package, MacroLibrary>()
        for ((pkg, result) in built.libraries) {
            match (result) {
                case Built(path, stamp) => libraries[pkg] = MacroLibrary(path.toString(), stamp)
                case NotBuilt(reason) =>
                    issues.add("${pkg.name(db)}: macro library not built: ${reason}")
            }
        }
        db
            .batch {
                for ((pkg, library) in libraries) {
                    pkg.setMacroLibrary(db).to(library.stamp)
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
        for (file in files) {
            for (call in serverCalls(db, file)) {
                let name = "${vfs.paths.path(file.fileId(db))}: @${call.definition.name}"
                match (macroOutputOf(db, call.call)) {
                    case None => issues.add("${name}: macro call was not sent")
                    case Some(output) =>
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
    } finally {
        servers.close()
        remove(temporary, recursive: true)
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
