package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import loupe.db.AnalysisDatabase

/**
 * A scope of a body, by its place among the body's scopes.
 */
@Derive[Equatable, Hashable, ToString]
public struct ScopeId {
    public ScopeId(public let index: Int64) {}
}

/**
 * A scope: the one around it, and the locals it adds; a local function's own has its type
 * parameters.
 */
@Derive[Equatable]
public struct ScopeData {
    public ScopeData(
        public let parent: ?ScopeId,
        public let entries: Array<LocalId>,
        /**
         * The local function whose type parameters these are.
         */
        public let genericsOf!: ?Int64 = None,
        public let generics!: Array<String> = []
    ) {}
}

/**
 * The scopes of a body, rust-analyzer's `ExprScopes`: a tree, and where each expression and type is,
 * the scope it sees. A declaration opens a scope for what follows it, its initializer not in it:
 * what comes before a local, and the local's own initializer, see what is around it (N60, N61). A
 * block and the bindings before it are one scope in cjc, which only says so for a redefinition
 * (N59); here they nest, which answers a lookup the same.
 */
@Derive[Equatable]
public struct ExprScopes {
    public ExprScopes(
        public let scopes!: Array<ScopeData> = [],
        public let exprScopes!: Array<?ScopeId> = [],
        public let typeScopes!: Array<?ScopeId> = []
    ) {}

    public operator func [](id: ScopeId): ScopeData {
        scopes[id.index]
    }

    /**
     * The scope `expr` sees, `None` for one of no body.
     */
    public func scopeOf(expr: ExprId): ?ScopeId {
        exprScopes.get(expr.index) ?? None
    }

    public func scopeOfType(ty: TypeRefId): ?ScopeId {
        typeScopes.get(ty.index) ?? None
    }

    /**
     * The scopes from `scope` out, it first.
     */
    public func chain(scope: ?ScopeId): Array<ScopeId> {
        let found = ArrayList<ScopeId>()
        var current = scope
        while (let Some(one) <- current) {
            found.add(one)
            current = this[one].parent
        }
        found.toArray()
    }
}

/**
 * The `ExprScopes` of the body of `def`. An edit that leaves the body equal leaves it alone.
 */
@CalcaTracked
public func exprScopes(db: AnalysisDatabase, def: DefId): ExprScopes {
    ScopesBuilder(body(db, def)).build()
}

/**
 * The scopes of one body as they are built.
 */
class ScopesBuilder {
    private let scopes = ArrayList<ScopeData>()
    private let exprScopes: Array<?ScopeId>
    private let typeScopes: Array<?ScopeId>

    ScopesBuilder(private let body: Body) {
        exprScopes = Array(body.exprs.size, repeat: None)
        typeScopes = Array(body.types.size, repeat: None)
    }

    func build(): ExprScopes {
        let root = add(None, [])
        let inner = params(body.params, root)
        if (let Some(value) <- body.value) {
            walk(value, inner)
        }
        for (accessor in body.accessors) {
            walk(accessor, root)
        }
        // what lowering wrote but no walk reached sees the root
        for (i in 0..exprScopes.size where exprScopes[i].isNone()) {
            exprScopes[i] = root
        }
        for (i in 0..typeScopes.size where typeScopes[i].isNone()) {
            typeScopes[i] = root
        }
        ExprScopes(scopes: scopes.toArray(), exprScopes: exprScopes, typeScopes: typeScopes)
    }

    private func add(parent: ?ScopeId, entries: Array<LocalId>, genericsOf!: ?Int64 = None,
        generics!: Array<String> = []): ScopeId {
        scopes.add(ScopeData(parent, entries, genericsOf: genericsOf, generics: generics))
        ScopeId(scopes.size - 1)
    }

    /**
     * The parameters `params` in `scope`, each in a scope of its own, its default value in the one
     * before (N67); the scope after them.
     */
    private func params(params: Array<BodyParam>, scope: ScopeId): ScopeId {
        var current = scope
        for (param in params) {
            if (let Some(ty) <- param.ty) {
                typeScopes[ty.index] = current
            }
            if (let Some(value) <- param.defaultValue) {
                walk(value, current)
            }
            if (let Some(local) <- param.local) {
                current = add(current, [local])
            }
        }
        current
    }

    private func walkAll(exprs: Array<ExprId>, scope: ScopeId): Unit {
        for (expr in exprs) {
            walk(expr, scope)
        }
    }

    private func walkOpt(expr: ?ExprId, scope: ScopeId): Unit {
        if (let Some(one) <- expr) {
            walk(one, scope)
        }
    }

    private func typeIn(ty: ?TypeRefId, scope: ScopeId): Unit {
        if (let Some(one) <- ty) {
            typeScopes[one.index] = scope
            // the types inside it: a signature's come before the one holding them
            for (inner in innerTypes(one)) {
                typeIn(inner, scope)
            }
        }
    }

    private func innerTypes(ty: TypeRefId): Array<TypeRefId> {
        match (body.types[ty.index]) {
            case PathRef(segments) => segments |> flatMap {segment: TypeSegment => segment.args} |> collectArray
            case TupleRef(elements) => elements
            case FuncRef(params, ret) => params.concat([ret])
            case OptionRef(inner) => [inner]
            case VArrayRef(element, _) => [element]
            case _ => []
        }
    }

    /**
     * A `match`: its scrutinee in `scope`, each arm in a scope of what its patterns bind.
     */
    private func walkMatch(scrutinee: ?ExprId, arms: Array<MatchArm>, scope: ScopeId): Unit {
        walkOpt(scrutinee, scope)
        for (arm in arms) {
            patTypes(arm.pats, scope)
            let inner = add(scope, bindings(arm.pats))
            walkOpt(arm.guard, inner)
            walkOpt(arm.condition, inner)
            walk(arm.body, inner)
        }
    }

    private func walk(expr: ExprId, scope: ScopeId): Unit {
        exprScopes[expr.index] = scope
        match (body[expr]) {
            case BlockExpr(stmts) => block(stmts, scope)
            case StrExpr(parts) => walkAll(parts, scope)
            case PathExpr(_, args) => for (arg in args) {
                typeIn(arg, scope)
            }
            case FieldExpr(receiver, _, args) =>
                walk(receiver, scope)
                for (arg in args) {
                    typeIn(arg, scope)
                }
            case CallExpr(callee, args) =>
                walk(callee, scope)
                walkAll(args.map {arg => arg.expr}, scope)
            case IndexExpr(base, indices) =>
                walk(base, scope)
                walkAll(indices, scope)
            case UnaryExpr(_, inner) => walk(inner, scope)
            case BinaryExpr(_, lhs, rhs) =>
                walk(lhs, scope)
                walk(rhs, scope)
            case IsExpr(inner, ty) =>
                walk(inner, scope)
                typeIn(ty, scope)
            case AsExpr(inner, ty) =>
                walk(inner, scope)
                typeIn(ty, scope)
            case RangeExpr(start, end, step, _) =>
                walkOpt(start, scope)
                walkOpt(end, scope)
                walkOpt(step, scope)
            case PostfixExpr(inner, _) => walk(inner, scope)
            case TupleExpr(elements) => walkAll(elements, scope)
            case ArrayExpr(elements) => walkAll(elements, scope)
            case IfExpr(condition, then, otherwise) =>
                walk(then, walkCondition(condition, scope))
                walkOpt(otherwise, scope)
            case LetExpr(pats, value) =>
                walk(value, scope)
                patTypes(pats, scope)
            case MatchExpr(scrutinee, arms) => walkMatch(scrutinee, arms, scope)
            case QuestMatchExpr(selector, arms) => walkMatch(selector, arms, scope)
            case TryExpr(resources, tried, catches, finallyBlock) =>
                var current = scope
                for (resource in resources) {
                    walk(resource.value, current)
                    typeIn(resource.ty, current)
                    if (let Some(local) <- resource.local) {
                        current = add(current, [local])
                    }
                }
                walk(tried, current)
                for (arm in catches) {
                    for (ty in arm.types) {
                        typeIn(ty, scope)
                    }
                    let inner = match (arm.local) {
                        case Some(local) => add(scope, [local])
                        case None => scope
                    }
                    walk(arm.body, inner)
                }
                walkOpt(finallyBlock, scope)
            case ForExpr(pat, iterated, guard, loopBody) =>
                walk(iterated, scope)
                patTypes([pat], scope)
                let inner = add(scope, bindings([pat]))
                walkOpt(guard, inner)
                walk(loopBody, inner)
            case WhileExpr(condition, loopBody) => walk(loopBody, walkCondition(condition, scope))
            case DoWhileExpr(loopBody, condition) =>
                walk(loopBody, scope)
                walk(condition, scope)
            case ThrowExpr(inner) => walk(inner, scope)
            case ReturnExpr(inner) => walkOpt(inner, scope)
            case SpawnExpr(context, lambda) =>
                walkOpt(context, scope)
                walk(lambda, scope)
            case SynchronizedExpr(lock, block) =>
                walk(lock, scope)
                walk(block, scope)
            case UnsafeExpr(block) => walk(block, scope)
            case LambdaExpr(params, lambdaBody) =>
                for (param in params) {
                    typeIn(param.ty, scope)
                }
                let locals = params |> filterMap {param: BodyParam => param.local} |> collectArray
                walk(lambdaBody, add(scope, locals))
            case ConvExpr(_, inner) => walk(inner, scope)
            case VArrayExpr(ty, args) =>
                typeIn(ty, scope)
                walkAll(args.map {arg => arg.expr}, scope)
            case MacroExpr(args) => walkAll(args.map {arg => arg.expr}, scope)
            case _ => ()
        }
    }

    /**
     * The condition of an `if` or a `while` in `scope`: what a `let … <-` binds is seen by what
     * follows it by `&&`, and by the block after it (N62); the scope after it.
     */
    private func walkCondition(expr: ExprId, scope: ScopeId): ScopeId {
        match (body[expr]) {
            case LetExpr(pats, value) =>
                exprScopes[expr.index] = scope
                walk(value, scope)
                patTypes(pats, scope)
                add(scope, bindings(pats))
            case BinaryExpr("&&", lhs, rhs) =>
                exprScopes[expr.index] = scope
                walkCondition(rhs, walkCondition(lhs, scope))
            case _ =>
                walk(expr, scope)
                scope
        }
    }

    /**
     * A block's statements in a scope of its own, each declaration opening one for what follows.
     */
    private func block(stmts: Array<Stmt>, scope: ScopeId): Unit {
        var current = add(scope, [])
        for (stmt in stmts) {
            match (stmt) {
                case LetStmt(pat, ty, value) =>
                    walkOpt(value, current)
                    typeIn(ty, current)
                    patTypes([pat], current)
                    current = add(current, bindings([pat]))
                case ExprStmt(expr) => walk(expr, current)
                case FuncStmt(index) =>
                    let localFunc = body.funcs[index]
                    // its name is seen in it: it may call itself, not one after it (N60)
                    current = add(current, [localFunc.local])
                    let own = add(current, [], genericsOf: index, generics: localFunc.generics)
                    let inner = params(localFunc.params, own)
                    typeIn(localFunc.ret, own)
                    for (bound in localFunc.bounds) {
                        typeIn(bound.ty, own)
                        for (one in bound.bounds) {
                            typeIn(one, own)
                        }
                    }
                    walkOpt(localFunc.body, inner)
            }
        }
    }

    private func patTypes(pats: Array<PatId>, scope: ScopeId): Unit {
        for (pat in pats) {
            match (body[pat]) {
                case TypePat(_, ty) => typeIn(ty, scope)
                case TuplePat(inner) => patTypes(inner, scope)
                case EnumPat(_, inner) => patTypes(inner, scope)
                case _ => ()
            }
        }
    }

    /**
     * The locals `pats` bind, in order.
     */
    private func bindings(pats: Array<PatId>): Array<LocalId> {
        let found = ArrayList<LocalId>()
        for (pat in pats) {
            collect(pat, found)
        }
        found.toArray()
    }

    private func collect(pat: PatId, found: ArrayList<LocalId>): Unit {
        match (body[pat]) {
            case BindPat(local) => found.add(local)
            case TypePat(Some(local), _) => found.add(local)
            case TuplePat(inner) => for (one in inner) {
                collect(one, found)
            }
            case EnumPat(_, inner) => for (one in inner) {
                collect(one, found)
            }
            case _ => ()
        }
    }
}
