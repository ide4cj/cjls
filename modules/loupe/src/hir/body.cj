package loupe.hir

import std.collection.*
import std.deriving.*
import ginkgo.SyntaxNodePtr
import cjsyntax.{CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.{Arg, ArgList, Block, CatchClause, Decl, GenericConstraint, Interpolation, LambdaExpr, MacroExpandExpr,
    MatchCase, Name,ParamList, PathSegment, Pattern, ResourceDecl, Type}
import cjsyntax.ast.Expr as AstExpr
import cjsyntax.ast.Stmt as AstStmt
import cjsyntax.ast.Param as AstParam
import calca.*
import calca.macros.*
import loupe.db.AnalysisDatabase
import loupe.syntax.parse

/**
 * An expression of a body, by its place among the body's `exprs`.
 */
@Derive[Equatable, Hashable, ToString]
public struct ExprId {
    public ExprId(public let index: Int64) {}
}

/**
 * A pattern of a body, by its place among the body's `pats`.
 */
@Derive[Equatable, Hashable, ToString]
public struct PatId {
    public PatId(public let index: Int64) {}
}

/**
 * A name a body declares, by its place among the body's `locals`.
 */
@Derive[Equatable, Hashable, ToString]
public struct LocalId {
    public LocalId(public let index: Int64) {}
}

/**
 * What declares a local.
 */
@Derive[Equatable]
public enum LocalKind {
    /**
     * A parameter of the declaration, of a local function or of a property's setter.
     */
    | ParamLocal
    /**
     * A parameter of a lambda.
     */
    | LambdaParamLocal
    /**
     * A name of a `let` or `var`.
     */
    | VarLocal
    | FuncLocal
    /**
     * A name a pattern of a `case`, a `let … <-` or a `for` binds.
     */
    | PatLocal
    | CatchLocal
    | ResourceLocal
}

/**
 * A name a body declares.
 */
@Derive[Equatable]
public struct Local {
    public Local(
        public let name: String,
        public let kind: LocalKind,
        /**
         * Whether it is a pattern's lone name, a constructor if one has the name (N72), and then no
         * local at all.
         */
        public let lone!: Bool = false
    ) {}
}

/**
 * A parameter: its name, `None` for `_`; its type, written in a lambda or a local function's
 * signature; its default value.
 */
@Derive[Equatable]
public struct BodyParam {
    public BodyParam(
        public let local: ?LocalId,
        public let ty!: ?TypeRefId = None,
        public let defaultValue!: ?ExprId = None,
        /**
         * Whether it is a member as well, a `let` or `var` of a primary constructor (N69).
         */
        public let isMember!: Bool = false
    ) {}
}

/**
 * A function declared in a body: its name, a local of the scope after it (N60).
 */
@Derive[Equatable]
public struct LocalFunc {
    public LocalFunc(
        public let local: LocalId,
        public let generics: Array<String>,
        public let params: Array<BodyParam>,
        public let ret: ?TypeRefId,
        public let body: ?ExprId,
        /**
         * Its `where`, as a signature's (N78).
         */
        public let bounds!: Array<TypeBound> = []
    ) {}
}

@Derive[Equatable]
public enum Stmt {
    /**
     * `let`, `var` or `const`: the names its pattern binds, seen after it (N60, N61).
     */
    | LetStmt(PatId, ?TypeRefId, ?ExprId)
    | ExprStmt(ExprId)
    /**
     * A function, by its place among the body's `funcs`.
     */
    | FuncStmt(Int64)
}

@Derive[Equatable]
public struct CallArg {
    public CallArg(public let name: ?String, public let expr: ExprId, public let isInout!: Bool = false) {}
}

/**
 * A `case`: its patterns and guard, or its condition; what it evaluates to.
 */
@Derive[Equatable]
public struct MatchArm {
    public MatchArm(
        public let pats: Array<PatId>,
        public let guard: ?ExprId,
        public let condition: ?ExprId,
        public let body: ExprId
    ) {}
}

@Derive[Equatable]
public struct Resource {
    public Resource(public let local: ?LocalId, public let ty: ?TypeRefId, public let value: ExprId) {}
}

@Derive[Equatable]
public struct CatchArm {
    public CatchArm(public let local: ?LocalId, public let types: Array<TypeRefId>, public let body: ExprId) {}
}

/**
 * An expression as a body writes it, rust-analyzer's `hir::Expr`: what it holds are other
 * expressions, patterns and types of the same body. A name is not resolved yet; an operator is as
 * written.
 */
@Derive[Equatable]
public enum Expr {
    /**
     * An expression the parser did not find.
     */
    | MissingExpr
    | LitExpr(String)
    /**
     * A string, its interpolations each a block.
     */
    | StrExpr(Array<ExprId>)
    /**
     * A name, and the type arguments after it.
     */
    | PathExpr(String, Array<TypeRefId>)
    /**
     * `a.b`: what `b` is, inference's (step 7).
     */
    | FieldExpr(ExprId, String, Array<TypeRefId>)
    /**
     * A call, a trailing lambda its last argument.
     */
    | CallExpr(ExprId, Array<CallArg>)
    | IndexExpr(ExprId, Array<ExprId>)
    | OptionalExpr(ExprId)
    | UnaryExpr(String, ExprId)
    /**
     * An operator between two, assignments included.
     */
    | BinaryExpr(String, ExprId, ExprId)
    | IsExpr(ExprId, TypeRefId)
    | AsExpr(ExprId, TypeRefId)
    /**
     * Its start, end and step, and whether it includes its end.
     */
    | RangeExpr(?ExprId, ?ExprId, ?ExprId, Bool)
    | PostfixExpr(ExprId, String)
    | TupleExpr(Array<ExprId>)
    | ArrayExpr(Array<ExprId>)
    | UnitExpr
    /**
     * Its condition, then, else.
     */
    | IfExpr(ExprId, ExprId, ?ExprId)
    /**
     * `let p <- e` in a condition: its patterns bind for what follows it by `&&`, and the block
     * the condition is of (N62).
     */
    | LetExpr(Array<PatId>, ExprId)
    | MatchExpr(?ExprId, Array<MatchArm>)
    | TryExpr(Array<Resource>, ExprId, Array<CatchArm>, ?ExprId)
    /**
     * Its pattern, what it iterates over, its guard, its body.
     */
    | ForExpr(PatId, ExprId, ?ExprId, ExprId)
    | WhileExpr(ExprId, ExprId)
    | DoWhileExpr(ExprId, ExprId)
    | ThrowExpr(ExprId)
    | ReturnExpr(?ExprId)
    | BreakExpr
    | ContinueExpr
    | SpawnExpr(?ExprId, ExprId)
    | SynchronizedExpr(ExprId, ExprId)
    | UnsafeExpr(ExprId)
    /**
     * Its parameters, and its body, a block.
     */
    | LambdaExpr(Array<BodyParam>, ExprId)
    | ThisExpr
    | SuperExpr
    | WildcardExpr
    /**
     * `Int64(x)`.
     */
    | ConvExpr(String, ExprId)
    /**
     * `Int64` before a `.`.
     */
    | PrimExpr(String)
    | VArrayExpr(TypeRefId, Array<CallArg>)
    | BlockExpr(Array<Stmt>)
    /**
     * A `quote` or a macro call: what it expands to is not known here. A macro call's arguments when they parse as
     * an argument list, lowered so the names in them resolve; the macro sees them as tokens all the same.
     */
    | MacroExpr(Array<CallArg>)
}

/**
 * A pattern as a body writes it.
 */
@Derive[Equatable]
public enum Pat {
    | MissingPat
    | WildcardPat
    | LitPat(String)
    /**
     * A name: a binding, or, a lone one, a constructor (N72).
     */
    | BindPat(LocalId)
    /**
     * `n: T`, `_: T`.
     */
    | TypePat(?LocalId, TypeRefId)
    | TuplePat(Array<PatId>)
    /**
     * `E.A(p)`, `A(p)`: the path to the constructor, and the patterns of its arguments.
     */
    | EnumPat(Array<String>, Array<PatId>)
}

/**
 * What a declaration's body is lowered to, nothing of where it is written: rust-analyzer's `Body`.
 * An edit that does not change its code, a blank line or a comment, an edit elsewhere in the file,
 * leaves it equal.
 */
@Derive[Equatable]
public struct Body {
    public Body(
        public let exprs!: Array<Expr> = [],
        public let pats!: Array<Pat> = [],
        public let locals!: Array<Local> = [],
        public let funcs!: Array<LocalFunc> = [],
        /**
         * The types it writes, as a signature's (D48).
         */
        public let types!: Array<TypeRef> = [],
        /**
         * The declaration's parameters, their default values in the body (N67).
         */
        public let params!: Array<BodyParam> = [],
        /**
         * A function's block, a variable's initializer.
         */
        public let value!: ?ExprId = None,
        /**
         * A property's `get` and `set`, each a lambda.
         */
        public let accessors!: Array<ExprId> = []
    ) {}

    public operator func [](id: ExprId): Expr {
        exprs[id.index]
    }

    public operator func [](id: PatId): Pat {
        pats[id.index]
    }

    public operator func [](id: LocalId): Local {
        locals[id.index]
    }

    /**
     * Its types as a signature, for `Signature.text`.
     */
    public func typesAsSignature(): Signature {
        Signature(types: types)
    }
}

/**
 * Where each expression, pattern, local and type of a body is written: a local by its name.
 */
@Derive[Equatable]
public struct BodySourceMap {
    public BodySourceMap(
        public let exprs!: Array<?SyntaxNodePtr<SyntaxKind>> = [],
        public let pats!: Array<?SyntaxNodePtr<SyntaxKind>> = [],
        public let locals!: Array<?SyntaxNodePtr<SyntaxKind>> = [],
        public let types!: Array<?SyntaxNodePtr<SyntaxKind>> = []
    ) {}

    public func exprAt(ptr: SyntaxNodePtr<SyntaxKind>): ?ExprId {
        indexOf(exprs, ptr).map {i => ExprId(i)}
    }

    public func patAt(ptr: SyntaxNodePtr<SyntaxKind>): ?PatId {
        indexOf(pats, ptr).map {i => PatId(i)}
    }

    /**
     * The local whose name `ptr` points to.
     */
    public func localAt(ptr: SyntaxNodePtr<SyntaxKind>): ?LocalId {
        indexOf(locals, ptr).map {i => LocalId(i)}
    }

    public func typeAt(ptr: SyntaxNodePtr<SyntaxKind>): ?TypeRefId {
        indexOf(types, ptr).map {i => TypeRefId(i)}
    }
}

func indexOf(ptrs: Array<?SyntaxNodePtr<SyntaxKind>>, ptr: SyntaxNodePtr<SyntaxKind>): ?Int64 {
    for (i in 0..ptrs.size where ptrs[i] == ptr) {
        return i
    }
    None
}

@Derive[Equatable]
public struct LoweredBody {
    public LoweredBody(public let body: Body, public let sourceMap: BodySourceMap) {}
}

/**
 * The `LoweredBody` of `def`: of its node in a source file; an empty one for a declaration with no
 * body, of a package compiled already, or no longer there.
 */
@CalcaTracked
public func bodyWithSourceMap(db: AnalysisDatabase, def: DefId): LoweredBody {
    if (let Source(file) <- def.file(db)) {
        let root = parse(db, file).syntaxNode()
        if (let Some(decl) <- itemIdMap(db, file).node(def.item(db), root).flatMap {node => Decl.cast(node)}) {
            return lowerBody(decl)
        }
    }
    LoweredBody(Body(), BodySourceMap())
}

/**
 * The `Body` of `def`. An edit of the file but of its code leaves it equal, and what read it is not
 * run again.
 */
@CalcaTracked
public func body(db: AnalysisDatabase, def: DefId): Body {
    bodyWithSourceMap(db, def).body
}

/**
 * The body of `decl`.
 */
func lowerBody(decl: Decl): LoweredBody {
    let lowering = BodyLowering()
    var params = Array<BodyParam>()
    var value: ?ExprId = None
    var accessors = Array<ExprId>()
    match (decl) {
        case Decl.AsFuncDecl(it) => (params, value) = (lowering.params(it.paramLists()), lowering.blockOf(it.block()))
        case Decl.AsMainDecl(it) => (params, value) = (lowering.params(it.paramLists()), lowering.blockOf(it.block()))
        case Decl.AsMacroDecl(it) => (params, value) = (lowering.params(it.paramLists()), lowering.blockOf(it.block()))
        case Decl.AsInitDecl(it) => (params, value) = (lowering.params(it.paramLists()), lowering.blockOf(it.block()))
        case Decl.AsFinalizerDecl(it) => value = lowering.blockOf(it.block())
        case Decl.AsPrimaryInitDecl(it) =>
            (params, value) = (lowering.params(it.paramLists(), primary: true), lowering.blockOf(it.block()))
        case Decl.AsVarDecl(it) => value = it.expr().map {one => lowering.expr(one)}
        case Decl.AsPropDecl(it) => if (let Some(propBody) <- it.propBody()) {
            accessors = propBody.propAccessors() |> map {
                accessor =>
                let accessorParams = lowering.params(accessor.paramLists())
                lowering.add(Expr.LambdaExpr(accessorParams, lowering.block(accessor.block())), accessor.syntax)
            } |> collectArray
        }
        case _ => ()
    }
    lowering.finish(params, value, accessors)
}

/**
 * One body as it is lowered: its arrays and where each element is written.
 */
class BodyLowering {
    let types = SignatureLowering()
    let exprs = ArrayList<Expr>()
    let exprPtrs = ArrayList<?SyntaxNodePtr<SyntaxKind>>()
    let pats = ArrayList<Pat>()
    let patPtrs = ArrayList<?SyntaxNodePtr<SyntaxKind>>()
    let locals = ArrayList<Local>()
    let localPtrs = ArrayList<?SyntaxNodePtr<SyntaxKind>>()
    let funcs = ArrayList<LocalFunc>()

    func finish(params: Array<BodyParam>, value: ?ExprId, accessors: Array<ExprId>): LoweredBody {
        LoweredBody(
            Body(exprs: exprs.toArray(), pats: pats.toArray(), locals: locals.toArray(), funcs: funcs.toArray(),
                types: types.types.toArray(), params: params, value: value, accessors: accessors),
            BodySourceMap(exprs: exprPtrs.toArray(), pats: patPtrs.toArray(), locals: localPtrs.toArray(),
                types: types.ptrs.toArray())
        )
    }

    /**
     * The parameters of every list in order; a `let` or `var` one of a primary constructor a member
     * as well.
     */
    func params(lists: Iterator<ParamList>, primary!: Bool = false): Array<BodyParam> {
        let lowered = ArrayList<BodyParam>()
        for (list in lists) {
            for (param in list.params()) {
                lowered.add(paramOf(param, primary))
            }
        }
        lowered.toArray()
    }

    private func paramOf(param: AstParam, primary: Bool): BodyParam {
        // the default value first: it sees the parameters before this one, not this one (N67)
        let defaultValue = param.expr().map {one => expr(one)}
        BodyParam(local(param.name(), LocalKind.ParamLocal), ty: param.ty().map {one => types.lower(one)},
            defaultValue: defaultValue, isMember: primary && (param.letToken().isSome() || param.varToken().isSome()))
    }

    func local(name: ?Name, kind: LocalKind, lone!: Bool = false): ?LocalId {
        let one = name ?? return None
        locals.add(Local(one.text(), kind, lone: lone))
        localPtrs.add(SyntaxNodePtr(one.syntax))
        LocalId(locals.size - 1)
    }

    func add(expr: Expr, node: CjSyntaxNode): ExprId {
        exprs.add(expr)
        exprPtrs.add(SyntaxNodePtr(node))
        ExprId(exprs.size - 1)
    }

    private func missing(): ExprId {
        exprs.add(Expr.MissingExpr)
        exprPtrs.add(None)
        ExprId(exprs.size - 1)
    }

    func blockOf(node: ?Block): ?ExprId {
        node.map {one => block(one)}
    }

    func block(node: ?Block): ExprId {
        match (node) {
            case Some(one) => add(Expr.BlockExpr(stmts(one.stmts())), one.syntax)
            case None => missing()
        }
    }

    func stmts(nodes: Iterator<AstStmt>): Array<Stmt> {
        let lowered = ArrayList<Stmt>()
        for (node in nodes) {
            match (node) {
                case AstStmt.ExprStmt(one) => lowered.add(Stmt.ExprStmt(expr(one)))
                case AstStmt.DeclStmt(decl) => if (let Some(one) <- stmtOf(decl)) {
                    lowered.add(one)
                }
            }
        }
        lowered.toArray()
    }

    /**
     * A declaration in a block: a variable, or a function; nothing for a type, which a body does not
     * have (N65).
     */
    private func stmtOf(decl: Decl): ?Stmt {
        match (decl) {
            case Decl.AsVarDecl(it) =>
                // the initializer first: it does not see the names it is bound to (N61)
                let value = it.expr().map {one => expr(one)}
                let ty = it.ty().map {one => types.lower(one)}
                let pat = match ((it.name(), it.pattern())) {
                    case (Some(name), _) => addPat(Pat.BindPat(local(name, LocalKind.VarLocal).getOrThrow()), name.syntax)
                    case (None, Some(pattern)) => pat(pattern, LocalKind.VarLocal, lone: false)
                    case (None, None) => addPat(Pat.MissingPat, None)
                }
                Stmt.LetStmt(pat, ty, value)
            case Decl.AsFuncDecl(it) =>
                let name = local(it.name(), LocalKind.FuncLocal) ?? return None
                let generics = match (it.typeParamList()) {
                    case Some(list) => list.typeParams() |> map {param => param.name()?.text() ?? ""} |> collectArray
                    case None => Array<String>()
                }
                let params = params(it.paramLists())
                let ret = it.retType().flatMap {one => one.ty()}.map {one => types.lower(one)}
                let bounds = match (it.whereClause()) {
                    case Some(clause) => clause.genericConstraints() |> map {
                        constraint: GenericConstraint =>
                        TypeBound(types.lower(constraint.ty()), types.bounds(constraint.typeBoundList()))
                    } |> collectArray
                    case None => Array<TypeBound>()
                }
                funcs.add(LocalFunc(name, generics, params, ret, blockOf(it.block()), bounds: bounds))
                Stmt.FuncStmt(funcs.size - 1)
            case Decl.AsMacroExpandDecl(it) => it.decl().flatMap {inner => stmtOf(inner)}
            case _ => None
        }
    }

    func expr(node: AstExpr): ExprId {
        let lowered = match (node) {
            case AstExpr.AsLiteral(it) => Expr.LitExpr(it.value()?.text() ?? "")
            case AstExpr.AsStringLit(it) => Expr.StrExpr(it.interpolations() |> map {
                one: Interpolation => add(Expr.BlockExpr(stmts(one.stmts())), one.syntax)
            } |> collectArray)
            case AstExpr.AsRefExpr(it) => Expr.PathExpr(it.nameRef()?.text() ?? "", typeArgs(it.typeArgList()?.types()))
            case AstExpr.AsMemberAccessExpr(it) =>
                Expr.FieldExpr(exprOf(it.receiver()), it.nameRef()?.text() ?? "", typeArgs(it.typeArgList()?.types()))
            case AstExpr.AsCallExpr(it) => Expr.CallExpr(exprOf(it.callee()), args(it.argList()))
            case AstExpr.AsTrailingLambdaExpr(it) =>
                let callee = exprOf(it.callee())
                let lambda = lambdaOf(it.lambda())
                match (this.exprs[callee.index]) {
                    // `f(a) {…}` is `f(a, {…})`
                    case Expr.CallExpr(inner, args) => Expr.CallExpr(inner, args.concat([CallArg(None, lambda)]))
                    case _ => Expr.CallExpr(callee, [CallArg(None, lambda)])
                }
            case AstExpr.AsIndexExpr(it) => Expr.IndexExpr(exprOf(it.base()), it.indices() |> map {one => expr(one)} |> collectArray)
            case AstExpr.AsOptionalExpr(it) => Expr.OptionalExpr(exprOf(it.expr()))
            case AstExpr.AsUnaryExpr(it) => Expr.UnaryExpr(it.op()?.text() ?? "", exprOf(it.expr()))
            case AstExpr.AsBinExpr(it) => Expr.BinaryExpr(it.op()?.text() ?? "", exprOf(it.lhs()), exprOf(it.rhs()))
            case AstExpr.AsIsExpr(it) => Expr.IsExpr(exprOf(it.expr()), types.lower(it.ty()))
            case AstExpr.AsAsExpr(it) => Expr.AsExpr(exprOf(it.expr()), types.lower(it.ty()))
            case AstExpr.AsRangeExpr(it) => Expr.RangeExpr(it.start().map {one => expr(one)}, it.end().map {one => expr(one)},
                it.step().map {one => expr(one)}, it.op()?.kind == SyntaxKind.DotDotEq)
            case AstExpr.AsPostfixExpr(it) => Expr.PostfixExpr(exprOf(it.expr()), it.op()?.text() ?? "")
            case AstExpr.AsParenExpr(it) => return exprOf(it.expr())
            case AstExpr.AsTupleExpr(it) => Expr.TupleExpr(it.exprs() |> map {one => expr(one)} |> collectArray)
            case AstExpr.AsArrayExpr(it) => Expr.ArrayExpr(it.exprs() |> map {one => expr(one)} |> collectArray)
            case AstExpr.AsUnitExpr(_) => Expr.UnitExpr
            case AstExpr.AsIfExpr(it) =>
                let condition = exprOf(it.condition())
                let then = block(it.then())
                let otherwise = match ((it.elseBlock(), it.elseIf())) {
                    case (Some(one), _) => Some(block(one))
                    case (None, Some(one)) => Some(expr(AstExpr.AsIfExpr(one)))
                    case (None, None) => None<ExprId>
                }
                Expr.IfExpr(condition, then, otherwise)
            case AstExpr.AsLetExpr(it) =>
                // what it matches first: it does not see the names it binds
                let value = exprOf(it.expr())
                Expr.LetExpr(it.patterns() |> map {one => pat(one, LocalKind.PatLocal, lone: true)} |> collectArray, value)
            case AstExpr.AsMatchExpr(it) =>
                let scrutinee = it.expr().map {one => expr(one)}
                let arms = match (it.matchBody()) {
                    case Some(matchBody) => matchBody.matchCases() |> map {one: MatchCase => arm(one)} |> collectArray
                    case None => Array<MatchArm>()
                }
                Expr.MatchExpr(scrutinee, arms)
            case AstExpr.AsTryExpr(it) =>
                let resources = match (it.resourceList()) {
                    case Some(list) => list.resourceDecls() |> map {one: ResourceDecl => resource(one)} |> collectArray
                    case None => Array<Resource>()
                }
                let tried = block(it.block())
                let catches = it.catchClauses() |> map {one: CatchClause => catchArm(one)} |> collectArray
                Expr.TryExpr(resources, tried, catches, it.finallyClause().map {one => block(one.block())})
            case AstExpr.AsForInExpr(it) =>
                let iterated = exprOf(it.expr())
                let pattern = match (it.pattern()) {
                    case Some(one) => pat(one, LocalKind.PatLocal, lone: true)
                    case None => addPat(Pat.MissingPat, None)
                }
                Expr.ForExpr(pattern, iterated, it.guard().flatMap {one => one.expr()}.map {one => expr(one)}, block(it.block()))
            case AstExpr.AsWhileExpr(it) => Expr.WhileExpr(exprOf(it.expr()), block(it.block()))
            case AstExpr.AsDoWhileExpr(it) =>
                let body = block(it.block())
                Expr.DoWhileExpr(body, exprOf(it.expr()))
            case AstExpr.AsThrowExpr(it) => Expr.ThrowExpr(exprOf(it.expr()))
            case AstExpr.AsReturnExpr(it) => Expr.ReturnExpr(it.expr().map {one => expr(one)})
            case AstExpr.AsBreakExpr(_) => Expr.BreakExpr
            case AstExpr.AsContinueExpr(_) => Expr.ContinueExpr
            case AstExpr.AsSpawnExpr(it) =>
                let context = it.context().map {one => expr(one)}
                let lambda = it.syntax.children() |> filterMap {child: CjSyntaxNode => LambdaExpr.cast(child)} |> first
                Expr.SpawnExpr(context, lambdaOf(lambda))
            case AstExpr.AsSynchronizedExpr(it) => Expr.SynchronizedExpr(exprOf(it.expr()), block(it.block()))
            case AstExpr.AsUnsafeExpr(it) => Expr.UnsafeExpr(block(it.block()))
            case AstExpr.AsLambdaExpr(it) => return lambdaOf(it)
            case AstExpr.AsThisExpr(_) => Expr.ThisExpr
            case AstExpr.AsSuperExpr(_) => Expr.SuperExpr
            case AstExpr.AsWildcardExpr(_) => Expr.WildcardExpr
            case AstExpr.AsTypeConvExpr(it) => Expr.ConvExpr(it.primType()?.keyword()?.text() ?? "", exprOf(it.expr()))
            case AstExpr.AsPrimTypeExpr(it) => Expr.PrimExpr(it.keyword()?.text() ?? "")
            case AstExpr.AsVArrayExpr(it) =>
                Expr.VArrayExpr(types.lower(it.vArrayType().map {one => Type.AsVArrayType(one)}), args(it.argList()))
            case AstExpr.AsQuoteExpr(_) | AstExpr.AsMacroExpandDecl(_) => Expr.MacroExpr([])
            case AstExpr.AsMacroExpandExpr(it) => Expr.MacroExpr(macroArgs(it))
        }
        add(lowered, node.syntax)
    }

    private func exprOf(node: ?AstExpr): ExprId {
        match (node) {
            case Some(one) => expr(one)
            case None => missing()
        }
    }

    private func typeArgs(nodes: ?Iterator<Type>): Array<TypeRefId> {
        match (nodes) {
            case Some(it) => it |> map {one: Type => types.lower(one)} |> collectArray
            case None => Array<TypeRefId>()
        }
    }

    /**
     * `@M(a, b)`'s arguments, of the innermost call when `@A[x] @M(a, b)` nests them.
     */
    private func macroArgs(node: MacroExpandExpr): Array<CallArg> {
        match (node.macroArgs()) {
            case Some(it) => args(it.argList())
            case None => node.macroExpandExpr().map {inner => macroArgs(inner)} ?? []
        }
    }

    private func args(list: ?ArgList): Array<CallArg> {
        let it = list?.args() ?? return []
        it |> map {
            arg: Arg => CallArg(arg.nameRef()?.text(), exprOf(arg.expr()), isInout: arg.inoutToken().isSome())
        } |> collectArray
    }

    /**
     * A lambda: its parameters, then its statements, a block of its own.
     */
    private func lambdaOf(node: ?LambdaExpr): ExprId {
        let it = node ?? return missing()
        let params = match (it.lambdaParamList()) {
            case Some(list) => list.lambdaParams() |> map {
                param => BodyParam(local(param.name(), LocalKind.LambdaParamLocal), ty: param.ty().map {one => types.lower(one)})
            } |> collectArray
            case None => Array<BodyParam>()
        }
        // the block has no node of its own: the lambda's is the lambda's
        exprs.add(Expr.BlockExpr(stmts(it.stmts())))
        exprPtrs.add(None)
        add(Expr.LambdaExpr(params, ExprId(exprs.size - 1)), it.syntax)
    }

    private func arm(node: MatchCase): MatchArm {
        let pats = node.patterns() |> map {one => pat(one, LocalKind.PatLocal, lone: true)} |> collectArray
        let guard = node.guard().flatMap {one => one.expr()}.map {one => expr(one)}
        let condition = node.condition().map {one => expr(one)}
        let body = add(Expr.BlockExpr(stmts(node.stmts())), node.syntax)
        MatchArm(pats, guard, condition, body)
    }

    private func resource(node: ResourceDecl): Resource {
        let value = exprOf(node.expr())
        let ty = node.ty().map {one => types.lower(one)}
        Resource(local(node.name(), LocalKind.ResourceLocal), ty, value)
    }

    private func catchArm(node: CatchClause): CatchArm {
        let (local, caught) = match (node.catchPat()) {
            case Some(catchPat) => (local(catchPat.name(), LocalKind.CatchLocal),
                catchPat.types() |> map {one: Type => types.lower(one)} |> collectArray)
            case None => (None<LocalId>, Array<TypeRefId>())
        }
        CatchArm(local, caught, block(node.block()))
    }

    /**
     * The pattern `node`, its names locals of `kind`; a lone name may be a constructor if `lone`.
     */
    func pat(node: Pattern, kind: LocalKind, lone!: Bool): PatId {
        let lowered = match (node) {
            case Pattern.AsWildcardPat(_) => Pat.WildcardPat
            case Pattern.AsLiteralPat(it) => Pat.LitPat(compactText(it.syntax))
            case Pattern.AsBindPat(it) => match (local(it.name(), kind, lone: lone)) {
                case Some(one) => Pat.BindPat(one)
                case None => Pat.MissingPat
            }
            case Pattern.AsTypePat(it) => Pat.TypePat(local(it.name(), kind), types.lower(it.ty()))
            case Pattern.AsTuplePat(it) => Pat.TuplePat(it.patterns() |> map {one => pat(one, kind, lone: lone)} |> collectArray)
            case Pattern.AsEnumPat(it) => Pat.EnumPat(it.pathSegments() |> map {
                segment: PathSegment => segment.nameRef()?.text() ?? ""
            } |> collectArray, it.patterns() |> map {one => pat(one, kind, lone: lone)} |> collectArray)
        }
        addPat(lowered, node.syntax)
    }

    private func addPat(pat: Pat, node: ?CjSyntaxNode): PatId {
        pats.add(pat)
        patPtrs.add(node.map {one => SyntaxNodePtr(one)})
        PatId(pats.size - 1)
    }
}
