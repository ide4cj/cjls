package tracked_audit

import std.collection.*
import std.convert.Parsable
import std.env.{getStdErr, getVariable, getWorkingDirectory}
import std.fs.*
import stdx.log.NoopLogger
import fjson.JsonValue
import loupe.*
import loupe.db.*
import loupe.hir.*
import loupe.syntax.parse
import loupe.vfs.*
import macro_host.*
import project_model.*

const USAGE = "Usage: tracked_audit [--dir PATH] [--output FILE] [--max-nodes N] [--no-macros]\n"

main(args: Array<String>): Int64 {
    try {
        var root = getWorkingDirectory().toString()
        var output: ?String = None
        var maxNodes = 100000
        var macros = true
        var i = 0
        while (i < args.size) {
            let option = args[i]
            i++
            match (option) {
                case "--help" =>
                    print(USAGE);
                    return 0
                case "--no-macros" => macros = false
                case "--dir" | "--output" | "--max-nodes" =>
                    if (i == args.size) {
                        throw IllegalArgumentException("${option} requires a value")
                    }
                    let value = args[i]
                    i++
                    match (option) {
                        case "--dir" => root = value
                        case "--output" => output = value
                        case _ => maxNodes = Int64.parse(value)
                    }
                case _ => throw IllegalArgumentException("unknown option: ${option}")
            }
        }
        if (maxNodes <= 0) {
            throw IllegalArgumentException("--max-nodes must be positive")
        }
        let rootPath = Path(root)
        let absoluteRoot =
            if (rootPath.isAbsolute()) { rootPath } else { getWorkingDirectory().join(rootPath) }
        let report = audit(VfsPath.file(absoluteRoot), macros, maxNodes).toPrettyString() + "\n"
        if (let Some(path) <- output) {
            File.writeTo(path, report.toArray())
        } else {
            print(report)
        }
        0
    } catch (e: Exception) {
        getStdErr().write("tracked_audit: ${e.message}\n")
        1
    } catch (e: Error) {
        getStdErr().write("tracked_audit: ${e.message}\n")
        1
    }
}

func audit(root: VfsPath, macros: Bool, maxNodes: Int64): JsonValue {
    let env = { name: String => getVariable(name) }
    let home = findCangjieHome(None, env: env)
    let withHome = withCangjieHome(env, home)
    let sdkSource = findCangjieSrc(None, env: withHome)
    let load = findProject(root, env: withCangjieSrc(withHome, sdkSource))
    let problems = ArrayList<String>(load.problems)
    if (load.partial) {
        problems.add("project discovery was partial")
    }
    let db = AnalysisDatabase()
    let vfs = Vfs()
    let binaries = readCjoFiles(load.model.cjoFiles())
    problems.add(all: binaries.problems)
    if (binaries.truncated) {
        problems.add("binary loading was truncated")
    }
    db.setProject(load.model, vfs.paths, binaries: binaries.files)
    let paths = load.model.files().concat(load.model.binarySourceFiles())
    let texts = readFiles(paths)
    let loaded = HashSet<VfsPath>()
    for ((path, text) in texts.files) {
        vfs.setFileContents(path, text);
        loaded.add(path)
    }
    for (path in paths where !loaded.contains(path)) {
        problems.add("source not loaded: ${path}")
    }
    db.applyChanges(vfs, vfs.takeChanges())
    let files = ArrayList<SourceFile>()
    let rootFiles = ArrayList<SourceFile>()
    let seenFiles = HashSet<SourceFile>()
    for (module in db.project().getOrThrow().modules(db)) {
        for (pkg in module.packages(db)) {
            for (id in pkg.files(db)) {
                if (let Some(file) <- db.sourceFile(id, context: pkg) && seenFiles.add(file)) {
                    files.add(file)
                    if (module.member(db)) {
                        rootFiles.add(file)
                    }
                }
            }
        }
    }
    if (macros) {
        if (let Some(home) <- home) {
            expandWorkspace(db, files.toArray(), Path(home.path), root, problems)
        } else {
            problems.add("no SDK found; macros were not expanded")
        }
    } else {
        problems.add("macro expansion was disabled")
    }
    for (file in files where !parse(db, file).errors.isEmpty()) {
        problems.add("source has syntax errors: ${vfs.paths.path(file.fileId(db))}")
    }
    getStdErr().write("tracked_audit: analyzing ${files.size} source contexts\n")
    let answers = trackedReachability(db, rootFiles.toArray(), maxNodes: maxNodes)
    let boundaryIds = HashMap<ReachBoundary, Int64>()
    let boundaries = ArrayList<ReachBoundary>()
    for (answer in answers) {
        for (boundary in answer.boundaries where !boundaryIds.contains(boundary)) {
            boundaryIds[boundary] = boundaries.size
            boundaries.add(boundary)
        }
    }
    JsonValue
        .JsonObject(
            [
                ("schema_version", JsonValue.JsonInteger(1)),
                ("root", text(root.toString())),
                ("sdk", text(home?.path ?? "")),
                ("sdk_source", text(sdkSource?.path ?? "")),
                (
                    "configuration",
                    JsonValue
                        .JsonObject(
                            load
                                .model
                                .cfg
                                .options
                                .map { option => (option.key, text(option.value)) }
                        )
                ),
                (
                    "semantics",
                    text(
                        "declaration-level syntactic call reachability; branch feasibility is not proved"
                    )
                ),
                ("max_nodes", JsonValue.JsonInteger(maxNodes)),
                ("problems", strings(problems.toArray())),
                (
                    "boundaries",
                    JsonValue
                        .JsonArray(
                            boundaries.toArray().map { boundary => boundaryJson(db, vfs, boundary) }
                        )
                ),
                (
                    "tracked_roots",
                    JsonValue
                        .JsonArray(
                            answers
                                .map {
                                    answer =>
                                    answerJson(db, vfs, answer, !problems.isEmpty(), boundaryIds)
                                }
                        )
                )
            ]
        )
}

func expandWorkspace(
    db: AnalysisDatabase,
    files: Array<SourceFile>,
    home: Path,
    root: VfsPath,
    problems: ArrayList<String>
): Unit {
    let sdk =
        match (macroSdkIn(home)) {
            case Usable(sdk) => sdk
            case Unusable(reason) =>
                problems.add(reason);
                return
        }
    let out = root.filePath.getOrThrow().join("target").join("tracked-audit").join("macros")
    let scopes = HashMap<Package, String>()
    for (module in db.project().getOrThrow().modules(db)) {
        for (pkg in module.packages(db)) {
            scopes[pkg] = module.resolutionScope(db)
        }
    }
    let built =
        buildPlan(
            db,
            macroBuildPlan(db),
            { pkg => out.join(scopes.get(pkg) ?? "") },
            sdk.version,
            sdk.toolchain
        )
    let libraries = HashMap<Package, MacroLibrary>()
    for ((pkg, result) in built.libraries) {
        match (result) {
            case Built(path, stamp) => libraries[pkg] = MacroLibrary(path.toString(), stamp)
            case NotBuilt(reason) =>
                problems.add("${pkg.name(db)}: macro package not built: ${reason}")
        }
    }
    db
        .batch {
            for ((pkg, library) in libraries) {
                pkg.setMacroLibrary(db).to(library.stamp)
            }
        }
    let servers = MacroServers(sdk.paths, Duration.minute, NoopLogger())
    try {
        while (true) {
            let requests =
                sendableRequests(db, files, libraries, stdLibrary: { pkg => sdk.stdLibrary(pkg) })
            if (requests.isEmpty()) {
                break
            }
            setMacroOutputsByKey(db, expandAll(db, requests, sdk.numbers, servers))
        }
    } finally {
        servers.close()
    }
    for (file in files) {
        for (call in serverCalls(db, file)) {
            if (macroOutputOf(db, call.call).isNone()) {
                problems.add("@${call.definition.name}: macro has no output")
            } else if (let Some(output) <- macroOutputOf(db, call.call)) {
                for (
                    diagnostic in output.diagnostics where diagnostic.severity ==
                        MacroSeverity.MacroError
                ) {
                    problems.add("@${call.definition.name}: ${diagnostic.message}")
                }
                if (output.expansion.isNone()) {
                    problems.add("@${call.definition.name}: macro has no expansion")
                }
            }
        }
    }
}

func text(value: String): JsonValue {
    JsonValue.JsonString(value)
}
func strings(values: Array<String>): JsonValue {
    JsonValue.JsonArray(values.map { value => text(value) })
}

func callableJson(db: AnalysisDatabase, vfs: Vfs, callable: ReachCallable): JsonValue {
    let def = reachabilityBodyDefinition(db, callable.def) ?? callable.def
    let members =
        ArrayList<(String, JsonValue)>([("name", text(reachabilityName(db, callable.def)))])
    if (let Some(file) <- scopeFileOf(db, def.file(db))) {
        members.add(("path", text(vfs.paths.path(file.fileId(db)).toString())))
    }
    if (
        let Some((root, ids)) <- syntaxOf(db, def.file(db)) &&
            let Some(node) <- ids.node(def.item(db), root)
    ) {
        members.add(("start", JsonValue.JsonInteger(node.textRange.start)))
        members.add(("end", JsonValue.JsonInteger(node.textRange.end)))
        members
            .add(
                ("line", JsonValue.JsonInteger(root.text()[..node.textRange.start].count("\n") + 1))
            )
    }
    members
        .add(
            (
                "in_expansion",
                JsonValue.JsonBool(if (let Expansion(_) <- def.file(db)) { true } else { false })
            )
        )
    if (let Some(entry) <- callable.entry) {
        members.add(("body_expression", JsonValue.JsonInteger(entry.index)))
    }
    members.add(("context", JsonValue.JsonInteger(callable.environment)))
    members.add(("evaluation", JsonValue.JsonBool(callable.evaluation)))
    JsonValue.JsonObject(members.toArray())
}

func expressionJson(db: AnalysisDatabase, expr: ExprId, owner: ReachCallable): JsonValue {
    let def = reachabilityBodyDefinition(db, owner.def) ?? owner.def
    if (
        let Some(WrittenSource(source)) <- bodyWithSourceMap(db, def)
            .sourceMap
            .exprs
            .get(expr.index)
    ) {
        if (let Some(node) <- source.node(db, def.file(db))) {
            return JsonValue
                .JsonObject(
                    [
                        ("start", JsonValue.JsonInteger(node.textRange.start)),
                        ("end", JsonValue.JsonInteger(node.textRange.end)),
                        ("text", text(node.text())),
                        (
                            "in_expansion",
                            JsonValue
                                .JsonBool(
                                    if (let Expansion(_) <- source.inFile(def.file(db))) {
                                        true
                                    } else {
                                        false
                                    }
                                )
                        )
                    ]
                )
        }
    }
    JsonValue.JsonObject([("expression", JsonValue.JsonInteger(expr.index))])
}

func answerJson(
    db: AnalysisDatabase,
    vfs: Vfs,
    answer: TrackedReachability,
    incomplete: Bool,
    boundaryIds: HashMap<ReachBoundary, Int64>
): JsonValue {
    let witnesses =
        answer
            .witnesses
            .map {
                witness =>
                JsonValue
                    .JsonObject(
                        [
                            ("family", text(witness.family)),
                            ("call_count", JsonValue.JsonInteger(witness.callCount)),
                            (
                                "shortest_proven",
                                JsonValue
                                    .JsonBool(
                                        witness.shortestProven &&
                                            (!incomplete || witness.callCount <= 1)
                                    )
                            ),
                            (
                                "chain",
                                JsonValue
                                    .JsonArray(
                                        witness
                                            .calls
                                            .map {
                                                edge =>
                                                JsonValue
                                                    .JsonObject(
                                                        [
                                                            (
                                                                "caller",
                                                                callableJson(db, vfs, edge.source)
                                                            ),
                                                            (
                                                                "callee",
                                                                callableJson(db, vfs, edge.target)
                                                            ),
                                                            ("kind", text(edge.kind)),
                                                            (
                                                                "call_cost",
                                                                JsonValue.JsonInteger(edge.callCost)
                                                            ),
                                                            (
                                                                "site",
                                                                expressionJson(
                                                                    db,
                                                                    edge.expr,
                                                                    edge.source
                                                                )
                                                            )
                                                        ]
                                                    )
                                            }
                                    )
                            )
                        ]
                    )
            }
    let statuses =
        TRACKED_EFFECT_FAMILIES
            .map {
                family =>
                let status = answer.status(family)
                (
                    family,
                    text(if (incomplete && status == "not_reachable") { "unknown" } else { status })
                )
            }
    var shortest = -1
    var distance = Int64.Max
    for (i in 0..answer.witnesses.size where answer.witnesses[i].callCount < distance) {
        shortest = i;
        distance = answer.witnesses[i].callCount
    }
    let status =
        if (shortest >= 0) {
            "reachable"
        } else if (incomplete || !answer.boundaries.isEmpty()) {
            "unknown"
        } else {
            "not_reachable"
        }
    JsonValue
        .JsonObject(
            [
                ("root", callableJson(db, vfs, ReachCallable(answer.root))),
                ("status", text(status)),
                (
                    "shortest_chain",
                    if (shortest >= 0) { witnesses[shortest] } else { JsonValue.JsonNull }
                ),
                ("family_status", JsonValue.JsonObject(statuses)),
                ("shortest_chains", JsonValue.JsonArray(witnesses)),
                (
                    "boundary_ids",
                    JsonValue
                        .JsonArray(
                            answer
                                .boundaries
                                .map { boundary => JsonValue.JsonInteger(boundaryIds[boundary]) }
                        )
                )
            ]
        )
}

func boundaryJson(db: AnalysisDatabase, vfs: Vfs, boundary: ReachBoundary): JsonValue {
    let fields =
        ArrayList<(String, JsonValue)>(
            [("owner", callableJson(db, vfs, boundary.owner)), ("reason", text(boundary.reason))]
        )
    if (let Some(expr) <- boundary.expr) {
        fields.add(("site", expressionJson(db, expr, boundary.owner)))
    }
    JsonValue.JsonObject(fields.toArray())
}
