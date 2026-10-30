package loupe

import std.collection.*
import cjsyntax.ast.PropAccessor
import loupe.db.AnalysisDatabase
import loupe.hir.*

// A lambda's expressions share its declaration's arena. Traversing the whole arena would
// mistake construction of an unused lambda for execution of its body.
class ReachBody {
    let graph: ReachGraph
    let db: AnalysisDatabase
    let owner: ReachCallable
    let def: DefId
    let hir: Body
    let inference: InferenceResult
    let visited = HashSet<ExprId>()
    let locals = HashMap<LocalId, ExprId>()
    let assigned = HashSet<LocalId>()
    let handledCallees = HashSet<ExprId>()
    let writes = HashSet<ExprId>()
    let readWrites = HashSet<ExprId>()

    init(graph: ReachGraph, owner: ReachCallable, def: DefId) {
        this.graph = graph;
        this.db = graph.db;
        this.owner = owner;
        this.def = def
        this.hir = body(db, def);
        this.inference = inferBody(db, def)
    }

    func frontier(reason: String, expr!: ?ExprId = None): Unit {
        graph.boundaries.add(ReachBoundary(owner, reason, expr: expr))
    }

    func localOf(expr: ExprId): ?LocalId {
        match (inference.nameOf(expr)) {
            case Some(Values(values)) where values.size == 1 =>
                match (values[0]) {
                    case LocalOf(local) => local;
                    case _ => None
                }
            case _ => None
        }
    }

    func scan(): Unit {
        if (!inference.diagnostics.isEmpty()) {
            frontier("body inference has diagnostics")
        }
        for (expr in hir.exprs) {
            match (expr) {
                case BlockExpr(stmts) =>
                    for (stmt in stmts) {
                        if (let LetStmt(pat, _, Some(value)) <- stmt) {
                            match (hir[pat]) {
                                case BindPat(local) => locals[local] = value
                                case TypePat(Some(local), _) => locals[local] = value
                                case _ => ()
                            }
                        }
                    }
                case BinaryExpr(op, lhs, _) where reachAssignment(op) =>
                    if (let Some(local) <- localOf(lhs)) {
                        assigned.add(local)
                    }
                case PostfixExpr(inner, _, _) =>
                    if (let Some(local) <- localOf(inner)) {
                        assigned.add(local)
                    }
                case _ => ()
            }
        }
        if (let Some(entry) <- owner.entry) {
            walk(entry)
        } else if (let Some(value) <- hir.value) {
            walk(value)
        } else if (!hir.accessors.isEmpty()) {
            // Accessor selection must depend on the caller's read/write operation.
            frontier("property accessor selection is not closed")
        } else {
            frontier("declaration has no analyzable executable body")
        }
    }

    func resolved(target: DefId, expr: ExprId, kind: String): Unit {
        graph.edge(owner, ReachCallable(target), expr, kind)
        let item = reachItem(db, target)
        if (
            item.map { item => item.kind == ItemKind.Class || item.kind == ItemKind.Struct } ??
                false
        ) {
            frontier("constructor field/default initialization is not closed", expr: expr)
        }
        if (item.map { item => item.has(Modifier.Open) || item.has(Modifier.Abstract) } ?? false) {
            frontier("virtual receiver dispatch is not closed", expr: expr)
        }
        if (
            let Some(parent) <- parentOf(db, target) && parent.item(db).kind == ItemKind.Interface
        ) {
            frontier("interface receiver dispatch is not closed", expr: expr)
        }
    }

    func valueCallable(expr: ExprId, seen: HashSet<ExprId>): ?ReachCallable {
        if (!seen.add(expr)) {
            return None
        }
        match (hir[expr]) {
            case LambdaExpr(_, block) =>
                ReachCallable(def, entry: block, environment: owner.environment)
            case FieldExpr(_, _, _) =>
                let targets = ArrayList<DefId>()
                match (inference.accessOf(expr)) {
                    case Some(PackageMembers(ids)) => targets.add(all: ids)
                    case Some(TypeMembers(members)) =>
                        for (member in members) {
                            if (let MemberDecl(target) <- member) {
                                targets.add(target)
                            }
                        }
                    case _ =>
                        for (member in inference.fieldOf(expr) ?? []) {
                            if (let MemberDecl(target) <- member) {
                                targets.add(target)
                            }
                        }
                }
                if (targets.size == 1 && targets[0].item(db).kind == ItemKind.Func) {
                    ReachCallable(targets[0])
                } else {
                    None
                }
            case _ =>
                if (let Some(local) <- localOf(expr) && !assigned.contains(local)) {
                    for (
                        binding in graph.environments[owner.environment] where binding.local ==
                            local
                    ) {
                        return binding.target
                    }
                    for (fun in hir.funcs where fun.local == local) {
                        if (let Some(block) <- fun.body) {
                            return ReachCallable(def, entry: block, environment: owner.environment)
                        }
                    }
                    if (let Some(value) <- locals.get(local)) {
                        return valueCallable(value, seen)
                    }
                }
                match (inference.nameOf(expr)) {
                    case Some(InFile(Found(targets))) where targets.size == 1 &&
                            targets[0].item(db).kind == ItemKind.Func => ReachCallable(targets[0])
                    case Some(Values(values)) where values.size == 1 =>
                        match (values[0]) {
                            case DeclOf(target) where target.item(db).kind == ItemKind.Func =>
                                ReachCallable(target)
                            case MemberOf(MemberDecl(target)) where target.item(db).kind ==
                                    ItemKind.Func => ReachCallable(target)
                            case _ => None
                        }
                    case _ => None
                }
        }
    }

    // Bind callable arguments at this call site rather than unioning every caller's callbacks.
    // Otherwise `apply(pure)` would inherit the effect of a separate `apply(readFile)`.
    func call(target: ReachCallable, callee: ExprId, args: Array<CallArg>, kind: String): Unit {
        let bodyDef = reachabilityBodyDefinition(db, target.def)
        if (bodyDef.isNone()) {
            graph.edge(owner, target, callee, kind)
            return
        }
        let targetBody = body(db, bodyDef.getOrThrow())
        var params = targetBody.params
        if (let Some(entry) <- target.entry) {
            for (expr in targetBody.exprs) {
                if (let LambdaExpr(lambdaParams, block) <- expr && block == entry) {
                    params = lambdaParams
                }
            }
            for (fun in targetBody.funcs where fun.body == target.entry) {
                params = fun.params
            }
        }
        let selectedParams = params
        let bindings =
            ArrayList<ReachBinding>(
                graph
                    .environments[target.environment]
                    .filter {
                        binding =>
                        !selectedParams.any { parameter => parameter.local == Some(binding.local) }
                    }
            )
        let paramIndices = inference.paramsOf(callee)
        let supplied = HashSet<Int64>()
        for (i in 0..args.size) {
            let parameter =
                if (let Some(indices) <- paramIndices) {
                    indices.get(i) ?? -1
                } else if (args[i].name.isNone()) {
                    i
                } else {
                    var found = -1
                    for (j in 0..params.size where params[j].passedBy == args[i].name) {
                        found = j
                    }
                    found
                }
            if (parameter < 0 || parameter >= params.size) {
                frontier("argument-to-parameter mapping is unresolved", expr: callee)
                continue
            }
            supplied.add(parameter)
            if (
                let Some(local) <- params[parameter].local &&
                    let Some(value) <- valueCallable(args[i].expr, HashSet<ExprId>())
            ) {
                bindings.add(ReachBinding(local, value))
            }
        }
        let argumentEnvironment = graph.environment(bindings.toArray())
        let defaults =
            ReachBody(
                graph,
                ReachCallable(target.def, environment: argumentEnvironment),
                bodyDef.getOrThrow()
            )
        for (i in 0..params.size where !supplied.contains(i)) {
            if (let Some(value) <- params[i].defaultValue && let Some(local) <- params[i].local) {
                if (let Some(callable) <- defaults.valueCallable(value, HashSet<ExprId>())) {
                    bindings.add(ReachBinding(local, callable))
                }
            }
        }
        let environment = graph.environment(bindings.toArray())
        let called = ReachCallable(target.def, entry: target.entry, environment: environment)
        graph.edge(owner, called, callee, kind)
        for (i in 0..params.size where !supplied.contains(i)) {
            if (let Some(defaultValue) <- params[i].defaultValue) {
                graph
                    .edge(
                        owner,
                        ReachCallable(
                            target.def,
                            entry: defaultValue,
                            environment: environment,
                            evaluation: true
                        ),
                        callee,
                        "default argument evaluation",
                        callCost: 0
                    )
            }
        }
        let item = reachItem(db, target.def)
        if (
            item.map { item => item.kind == ItemKind.Class || item.kind == ItemKind.Struct } ??
                false
        ) {
            frontier("constructor field/default initialization is not closed", expr: callee)
        }
        if (item.map { item => item.has(Modifier.Open) || item.has(Modifier.Abstract) } ?? false) {
            frontier("virtual receiver dispatch is not closed", expr: callee)
        }
        if (
            let Some(parent) <- parentOf(db, target.def) &&
                parent.item(db).kind == ItemKind.Interface
        ) {
            frontier("interface receiver dispatch is not closed", expr: callee)
        }
    }

    func property(target: DefId, id: ExprId, setter: Bool): Unit {
        if (
            reachItem(db, target)
                .map { item => item.has(Modifier.Open) || item.has(Modifier.Abstract) } ??
                false
        ) {
            frontier("virtual receiver dispatch is not closed", expr: id)
        }
        if (
            let Some(parent) <- parentOf(db, target) && parent.item(db).kind == ItemKind.Interface
        ) {
            frontier("interface receiver dispatch is not closed", expr: id)
        }
        if (effectFamily(db, target).isSome()) {
            graph.edge(owner, ReachCallable(target), id, "property access")
            return
        }
        let source =
            match (reachabilityBodyDefinition(db, target)) {
                case Some(source) => source
                case None =>
                    frontier("property has no paired source", expr: id);
                    return
            }
        let lowered = bodyWithSourceMap(db, source)
        let wanted = if (setter) { "set" } else { "get" }
        for (accessor in lowered.body.accessors) {
            if (
                let WrittenSource(origin) <- lowered.sourceMap.exprs[accessor.index] &&
                    let Some(node) <- origin.node(db, source.file(db)) &&
                    PropAccessor
                        .cast(node)
                        .flatMap { it => it.identToken() }
                        .map { token => token.text() } ==
                        Some(wanted) &&
                    let LambdaExpr(_, block) <- lowered.body[accessor]
            ) {
                graph.edge(owner, ReachCallable(source, entry: block), id, "property ${wanted}")
                return
            }
        }
        frontier("property ${wanted} accessor is unavailable", expr: id)
    }

    func accessProperty(target: DefId, id: ExprId): Unit {
        if (!writes.contains(id) || readWrites.contains(id)) {
            property(target, id, false)
        }
        if (writes.contains(id)) {
            property(target, id, true)
        }
    }

    func walk(id: ExprId): Unit {
        if (!visited.add(id)) {
            return
        }
        // Operators, indexers and compound assignments also appear in these inference tables.
        for (callee in inference.callees where callee.expr == id && !handledCallees.contains(id)) {
            resolved(callee.decl, id, "resolved call")
        }
        for (callee in inference.setters where callee.expr == id) {
            resolved(callee.decl, id, "index assignment")
        }
        match (hir[id]) {
            case LambdaExpr(_, _) => ()
            case CallExpr(callee, args) =>
                handledCallees.add(callee)
                if (let Some(target) <- inference.calleeOf(callee)) {
                    call(ReachCallable(target), callee, args, "resolved call")
                    if (let Some(initializer) <- inference.initializerOf(callee)) {
                        call(ReachCallable(initializer), callee, args, "explicit initializer")
                    }
                } else if (let Some(target) <- valueCallable(callee, HashSet<ExprId>())) {
                    call(target, callee, args, "callback invocation")
                } else {
                    frontier("unresolved call or callback binding", expr: callee)
                }
                walk(callee)
                for (arg in args) {
                    walk(arg.expr)
                }
            case BlockExpr(stmts) =>
                for (stmt in stmts) {
                    match (stmt) {
                        case LetStmt(_, _, value) => walkOption(value)
                        case ExprStmt(expr) => walk(expr)
                        case FuncStmt(_) => ()
                    }
                }
            case StrExpr(parts) =>
                walkAll(parts)
                if (!parts.isEmpty()) {
                    frontier("implicit interpolation conversion is not closed", expr: id)
                }
            case QuoteExpr(parts) => walkAll(parts)
            case FieldExpr(receiver, _, _) =>
                walk(receiver)
                let properties = HashSet<DefId>()
                var targets = inference.fieldOf(id) ?? []
                match (inference.accessOf(id)) {
                    case Some(TypeMembers(members)) => targets = targets.concat(members)
                    case Some(PackageMembers(decls)) =>
                        for (decl in decls where decl.item(db).kind == ItemKind.Prop) {
                            properties.add(decl)
                        }
                    case _ => ()
                }
                for (target in targets) {
                    if (
                        let MemberDecl(property) <- target &&
                            property.item(db).kind == ItemKind.Prop
                    ) {
                        properties.add(property)
                    }
                }
                for (property in properties) {
                    accessProperty(property, id)
                }
            case PathExpr(_, _) =>
                match (inference.nameOf(id)) {
                    case Some(InFile(Found(targets))) where targets.size == 1 &&
                            targets[0].item(db).kind == ItemKind.Prop =>
                        accessProperty(targets[0], id)
                    case Some(InFile(Found(targets))) where targets.size == 1 &&
                            targets[0].item(db).kind == ItemKind.Var =>
                        frontier("global initialization order is not closed", expr: id)
                    case Some(Values(values)) =>
                        for (value in values) {
                            if (
                                let MemberOf(MemberDecl(property)) <- value &&
                                    property.item(db).kind == ItemKind.Prop
                            ) {
                                accessProperty(property, id)
                            }
                        }
                    case _ => ()
                }
            case IndexExpr(base, indices) =>
                walk(base);
                walkAll(indices)
                if (inference.calleeOf(id).isNone()) {
                    frontier("index implementation is unresolved", expr: id)
                }
            case UnaryExpr(_, operand) =>
                walk(operand)
                if (inference.calleeOf(id).isNone() && !primitive(operand)) {
                    frontier("operator implementation is unresolved", expr: id)
                }
            case BinaryExpr(op, lhs, rhs) =>
                if (reachAssignment(op)) {
                    writes.add(lhs)
                    if (op != "=") {
                        readWrites.add(lhs)
                    }
                }
                walk(lhs);
                walk(rhs)
                if (
                    op != "=" && op != "??" && inference.calleeOf(id).isNone() &&
                        (!primitive(lhs) || !primitive(rhs))
                ) {
                    frontier("operator implementation is unresolved", expr: id)
                }
            case IsExpr(inner, _) => walk(inner)
            case AsExpr(inner, _) => walk(inner)
            case RangeExpr(start, end, step, _) =>
                walkOption(start);
                walkOption(end);
                walkOption(step)
            case PostfixExpr(inner, _, value) =>
                writes.add(inner)
                readWrites.add(inner)
                walk(inner);
                walkOption(value)
            case AssignedExpr(_, _, operand) => walk(operand)
            case TupleExpr(elements) => walkAll(elements)
            case ArrayExpr(elements) => walkAll(elements)
            case IfExpr(condition, then, otherwise) =>
                walk(condition);
                walk(then);
                walkOption(otherwise)
            case LetExpr(_, value) => walk(value)
            case MatchExpr(scrutinee, arms) =>
                walkOption(scrutinee);
                walkArms(arms)
            case QuestMatchExpr(selector, arms) =>
                walk(selector);
                walkArms(arms)
            case TryExpr(resources, tried, catches, cleanup) =>
                for (one in resources) {
                    walk(one.value)
                }
                walk(tried)
                for (one in catches) {
                    walk(one.body)
                }
                walkOption(cleanup)
                if (!resources.isEmpty()) {
                    frontier("resource cleanup dispatch is not closed", expr: id)
                }
            case ForExpr(_, iterated, guard, block) =>
                walk(iterated);
                walkOption(guard);
                walk(block)
                frontier("implicit iterator calls are not closed", expr: id)
            case WhileExpr(condition, block) =>
                walk(condition);
                walk(block)
            case DoWhileExpr(block, condition) =>
                walk(block);
                walk(condition)
            case SynchronizedExpr(lock, block) =>
                walk(lock);
                walk(block)
                frontier("synchronization dispatch is not closed", expr: id)
            case ThrowExpr(inner) => walk(inner)
            case UnsafeExpr(inner) => walk(inner)
            case ConvExpr(_, inner) => walk(inner)
            case ReturnExpr(value) => walkOption(value)
            case SpawnExpr(context, lambda) =>
                walkOption(context)
                if (let Some(target) <- valueCallable(lambda, HashSet<ExprId>())) {
                    graph.edge(owner, target, id, "spawn invocation")
                } else {
                    frontier("spawn target is unresolved", expr: id)
                }
            case MacroExpr(call) => frontier("body macro has no readable expansion", expr: id)
            case MissingExpr => frontier("missing expression", expr: id)
            case _ => ()
        }
    }

    func walkOption(id: ?ExprId): Unit {
        if (let Some(one) <- id) {
            walk(one)
        }
    }
    func primitive(id: ExprId): Bool {
        if (let Some(ty) <- inference[id] && let PrimTy(_) <- ty.kind(db)) { true } else { false }
    }
    func walkAll(ids: Array<ExprId>): Unit {
        for (id in ids) {
            walk(id)
        }
    }
    func walkArms(arms: Array<MatchArm>): Unit {
        for (arm in arms) {
            walkOption(arm.guard);
            walkOption(arm.condition);
            walk(arm.body)
        }
    }
}

func reachAssignment(op: String): Bool {
    ["=", "+=", "-=", "*=", "/=", "%=", "**=", "&=", "|=", "^=", "<<=", ">>=", "&&=", "||="]
        .contains(op)
}
