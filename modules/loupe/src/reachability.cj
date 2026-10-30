package loupe

import std.collection.*
import std.deriving.*
import std.sort.sort
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.hir.*

/** A callable in one unchanged database revision; `entry` distinguishes local functions and lambdas. */
@Derive[Equatable, Hashable]
public struct ReachCallable {
    public ReachCallable(
        public let def: DefId,
        public let entry!: ?ExprId = None,
        public let environment!: Int64 = 0,
        public let evaluation!: Bool = false
    ) {}
}

@Derive[Equatable]
struct ReachBinding {
    ReachBinding(let local: LocalId, let target: ReachCallable) {}
}

/** A resolved syntactic call. Ranges belong to the owner's source or expansion, in UTF-8 bytes. */
public struct ReachEdge {
    public ReachEdge(
        public let source: ReachCallable,
        public let target: ReachCallable,
        public let expr: ExprId,
        public let kind: String,
        public let callCost!: Int64 = 1
    ) {}
}

/** An analysis frontier, never evidence that a target is absent. */
@Derive[Equatable, Hashable]
public struct ReachBoundary {
    public ReachBoundary(
        public let owner: ReachCallable,
        public let reason: String,
        public let expr!: ?ExprId = None
    ) {}
}

/** A shortest resolved path to one target family; equal-length ties follow source traversal order. */
public struct ReachWitness {
    public ReachWitness(
        public let family: String,
        public let calls: Array<ReachEdge>,
        public let shortestProven!: Bool = false
    ) {}

    public prop callCount: Int64 {
        get() {
            var count = 0
            for (edge in calls) {
                count += edge.callCost
            }
            count
        }
    }
}

/**
 * A tracked source function's declaration-level reachability. `unknown` means an open frontier;
 * `not_reachable` requires a closed graph. Paths do not prove branch feasibility at runtime.
 */
public struct TrackedReachability {
    public TrackedReachability(
        public let root: DefId,
        public let witnesses: Array<ReachWitness>,
        public let boundaries: Array<ReachBoundary>
    ) {}

    public func status(family: String): String {
        if (witnesses.any { one => one.family == family }) {
            "reachable"
        } else if (boundaries.isEmpty()) {
            "not_reachable"
        } else {
            "unknown"
        }
    }
}

/** The prompt's exact families; DateTime.nowUTC and MonoTime.now are deliberately distinct. */
public let TRACKED_EFFECT_FAMILIES =
    [
        "std.fs.*",
        "std.env.*",
        "std.time.DateTime.now",
        "std.random.*",
        "loupe.vfs.readFile",
        "loupe.vfs.readRoots",
        "loupe.vfs.readCjoFiles"
    ]

/** A binary declaration's checked source counterpart, or the declaration itself when not binary. */
public func reachabilityBodyDefinition(db: AnalysisDatabase, def: DefId): ?DefId {
    match (def.file(db)) {
        case Binary(_, _) => sourceDefOf(db, def)
        case CompilerBuiltIns(_) => None
        case _ => def
    }
}

// itemOf indexes top-level items. Member identities must be looked up in their owning tree,
// otherwise a selected DateTime.now would silently acquire the name "DateTime.?".
func reachItem(db: AnalysisDatabase, def: DefId): ?Item {
    func find(items: Array<Item>): ?Item {
        for (item in items) {
            if (item.id == def.item(db)) {
                return item
            }
            if (let Some(member) <- find(item.members)) {
                return member
            }
        }
        None
    }
    find(itemTreeOf(db, def.file(db)).items)
}

/** The semantic package and nested declaration name, independent of source attachment paths. */
public func reachabilityName(db: AnalysisDatabase, def: DefId): String {
    let pkg =
        match (def.file(db)) {
            case Binary(binary, _) => binary.name(db)
            case CompilerBuiltIns(pkg) => pkg.name(db)
            case file =>
                scopeFileOf(db, file)
                    .flatMap { source => packageOfFile(db, source) }
                    .map { pkg => pkg.name(db) } ??
                    "?"
        }
    let names = ArrayList<String>()
    var current = Some(def)
    while (let Some(one) <- current) {
        names.add((reachItem(db, one)?.names ?? ["?"]).get(0) ?? "?")
        current = parentOf(db, one)
    }
    "${pkg}.${String.join(Array(names.size) { i => names[names.size - 1 - i] }, delimiter: ".")}"
}

func effectFamily(db: AnalysisDatabase, def: DefId): ?String {
    let name = reachabilityName(db, def)
    for (prefix in ["std.fs.", "std.env.", "std.random."]) {
        if (name.startsWith(prefix)) {
            return prefix + "*"
        }
    }
    for (family in TRACKED_EFFECT_FAMILIES[2..] where name == family) {
        return family
    }
    None
}

/**
 * Audits active source functions bearing the macro tag, retaining overload identities. Includes
 * source implementation and served wrapper bodies. SDK source bodies are followed when paired;
 * unresolved dispatch/callbacks, missing bodies and the node budget remain explicit frontiers.
 * The database must not change during the call. No disk or process I/O is performed here.
 */
public func trackedReachability(
    db: AnalysisDatabase,
    files: Array<SourceFile>,
    maxNodes!: Int64 = 100000
): Array<TrackedReachability> {
    if (maxNodes <= 0) {
        throw IllegalArgumentException("maxNodes must be positive")
    }
    let roots = ArrayList<DefId>()
    let seen = HashSet<DefId>()
    for (file in files) {
        func visit(items: Array<Item>): Unit {
            for (item in items) {
                if (item.kind == ItemKind.Func && item.macros.contains("CalcaTracked")) {
                    let def = DefId(db, ItemFile.Source(file), item.id)
                    if (seen.add(def)) {
                        roots.add(def)
                    }
                }
                visit(item.members)
            }
        }
        visit(itemTreeOf(db, ItemFile.Source(file)).items)
    }
    let graph = ReachGraph(db, maxNodes)
    for (root in roots) {
        graph.enqueue(ReachCallable(root))
        if (let Some(wrapper) <- expandedDeclOf(db, root)) {
            graph.enqueue(ReachCallable(wrapper))
        } else {
            graph
                .boundaries
                .add(ReachBoundary(ReachCallable(root), "tracked macro has no served wrapper"))
        }
    }
    graph.build()
    roots.toArray().map { root => graph.answer(root) }
}

class ReachGraph {
    let db: AnalysisDatabase
    let limit: Int64
    let queue = ArrayList<ReachCallable>()
    let queued = HashSet<ReachCallable>()
    let edges = HashMap<ReachCallable, ArrayList<ReachEdge>>()
    let boundaries = ArrayList<ReachBoundary>()
    let environments = ArrayList<Array<ReachBinding>>([[]])
    let environmentIds = HashMap<String, Int64>([("", 0)])
    let families = HashMap<DefId, ?String>()

    init(db: AnalysisDatabase, limit: Int64) {
        this.db = db;
        this.limit = limit
    }

    func family(one: ReachCallable): ?String {
        if (one.evaluation) {
            return None
        }
        if (let Some(found) <- families.get(one.def)) {
            return found
        }
        let found = effectFamily(db, one.def)
        families[one.def] = found
        found
    }

    func enqueue(one: ReachCallable): Unit {
        if (queued.add(one)) {
            queue.add(one)
        }
    }

    func environment(bindings: Array<ReachBinding>): Int64 {
        sort(bindings, by: { a, b => a.local.index.compare(b.local.index) })
        let key =
            String
                .join(
                    bindings
                        .map {
                            b =>
                            "${b.local.index}:${b.target.def}:${b.target.entry}:${b.target.environment}"
                        },
                    delimiter: ";"
                )
        if (let Some(id) <- environmentIds.get(key)) {
            return id
        }
        environments.add(bindings)
        let id = environments.size - 1
        environmentIds[key] = id
        id
    }

    func edge(
        from: ReachCallable,
        target: ReachCallable,
        expr: ExprId,
        kind: String,
        callCost!: Int64 = 1
    ): Unit {
        let list = edges.get(from) ?? ArrayList<ReachEdge>()
        list.add(ReachEdge(from, target, expr, kind, callCost: callCost))
        edges[from] = list
        enqueue(target)
    }

    func build(): Unit {
        var index = 0
        while (index < queue.size && index < limit) {
            db.unwindIfCancelled()
            let owner = queue[index]
            index++
            if (family(owner).isSome()) {
                boundaries
                    .add(
                        ReachBoundary(
                            owner,
                            "target family reached; its transitive effects are not expanded"
                        )
                    )
                continue
            }
            let def =
                match (owner.def.file(db)) {
                    case Binary(_, _) =>
                        match (sourceDefOf(db, owner.def)) {
                            case Some(source) => source
                            case None =>
                                boundaries
                                    .add(
                                        ReachBoundary(
                                            owner,
                                            "binary declaration has no paired source body"
                                        )
                                    )
                                continue
                        }
                    case CompilerBuiltIns(_) =>
                        boundaries.add(ReachBoundary(owner, "compiler-owned implementation"))
                        continue
                    case _ => owner.def
                }
            ReachBody(this, owner, def).scan()
        }
        for (one in queue.toArray()[index..]) {
            boundaries.add(ReachBoundary(one, "node budget exhausted"))
        }
    }

    func answer(root: DefId): TrackedReachability {
        let seeds = ArrayList<ReachCallable>([ReachCallable(root)])
        if (let Some(wrapper) <- expandedDeclOf(db, root)) {
            seeds.add(ReachCallable(wrapper))
        }
        let work = ArrayList<ReachCallable>()
        let visited = HashSet<ReachCallable>()
        let previous = HashMap<ReachCallable, ReachEdge>()
        let distances = HashMap<ReachCallable, Int64>()
        for (one in seeds where visited.add(one)) {
            work.add(one);
            distances[one] = 0
        }
        let witnesses = ArrayList<ReachWitness>()
        var index = 0
        while (index < work.size) {
            let one = work[index]
            index++
            for (edge in edges.get(one) ?? ArrayList<ReachEdge>()) {
                let distance = distances[one] + edge.callCost
                if (distance < (distances.get(edge.target) ?? Int64.Max)) {
                    visited.add(edge.target)
                    distances[edge.target] = distance
                    previous[edge.target] = edge
                    work.add(edge.target)
                }
            }
        }
        for (family in TRACKED_EFFECT_FAMILIES) {
            var best: ?ReachCallable = None
            var distance = Int64.Max
            for (one in work where this.family(one) == Some(family)) {
                if (distances[one] < distance) {
                    best = one;
                    distance = distances[one]
                }
            }
            if (let Some(one) <- best) {
                let calls = ArrayList<ReachEdge>()
                var at = one
                while (let Some(edge) <- previous.get(at)) {
                    calls.add(edge);
                    at = edge.source
                }
                let length = distance
                let openShorterPath =
                    boundaries
                        .toArray()
                        .any { b => (distances.get(b.owner) ?? Int64.Max - 1) + 1 < length }
                witnesses
                    .add(
                        ReachWitness(
                            family,
                            Array(calls.size) { i => calls[calls.size - 1 - i] },
                            shortestProven: !openShorterPath
                        )
                    )
            }
        }
        TrackedReachability(
            root,
            witnesses.toArray(),
            boundaries.toArray().filter { b => visited.contains(b.owner) }
        )
    }
}
