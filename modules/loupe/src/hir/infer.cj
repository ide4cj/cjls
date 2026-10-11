package loupe.hir

import std.collection.*
import std.convert.Parsable
import std.deriving.*
import std.sort.*
import calca.*
import calca.macros.*
import loupe.db.{AnalysisDatabase, Package, SourceFile}

let INTEGER_TYPES = ["Int8", "Int16", "Int32", "Int64", "IntNative", "UInt8", "UInt16", "UInt32", "UInt64", "UIntNative"]
let FLOAT_TYPES = ["Float16", "Float32", "Float64"]
let ASSIGNMENTS = ["=", "+=", "-=", "*=", "/=", "%=", "**=", "&=", "|=", "^=", "<<=", ">>=", "&&=", "||="]
let COMPARISONS = ["==", "!=", "<", ">", "<=", ">="]
let ARITHMETIC = ["+", "-", "*", "/", "%", "**", "&", "|", "^", "<<", ">>"]

/**
 * The members the name after the `.` of a value names, found from the value's type (N75).
 */
@Derive[Equatable]
public struct FieldTargets <: ByIndex {
    public FieldTargets(public let expr: ExprId, public let targets: Array<MemberTarget>) {}

    public func keyIndex(): Int64 {
        expr.index
    }
}

/**
 * The declaration a call of several candidates takes, by its callee (8d).
 */
@Derive[Equatable]
public struct CalleeTarget <: ByIndex {
    public CalleeTarget(public let expr: ExprId, public let decl: DefId) {}

    public func keyIndex(): Int64 {
        expr.index
    }
}

/**
 * What a name the body uses as a value means, as inference resolved it: what highlighting and go to
 * definition read, not resolving it again.
 */
@Derive[Equatable]
public struct NameTarget <: ByIndex {
    public NameTarget(public let expr: ExprId, public let resolution: BodyResolution) {}

    public func keyIndex(): Int64 {
        expr.index
    }
}

/**
 * What the name after the `.` of an expression means, as inference resolved it before the types: a
 * member of a package or of types, or one of a value, which `FieldTargets` tells.
 */
@Derive[Equatable]
public struct AccessTarget <: ByIndex {
    public AccessTarget(public let expr: ExprId, public let resolution: FieldResolution) {}

    public func keyIndex(): Int64 {
        expr.index
    }
}

/**
 * What was found of an expression or a type, in an array sorted by its index.
 */
public interface ByIndex {
    func keyIndex(): Int64
}

/**
 * The one of `sorted` whose index is `index`, by bisection.
 */
func findByIndex<T>(sorted: Array<T>, index: Int64): ?T where T <: ByIndex {
    var low = 0
    var high = sorted.size
    while (low < high) {
        let middle = (low + high) / 2
        let at = sorted[middle].keyIndex()
        if (at == index) {
            return sorted[middle]
        } else if (at < index) {
            low = middle + 1
        } else {
            high = middle
        }
    }
    None
}

/**
 * What inference finds in a body (D55), rust-analyzer's `InferenceResult`: the type of each of its
 * expressions, patterns and locals, by id; the members found after the `.` of a value; the
 * overload each call of several takes. A type not found is an error, or one the analysis cannot
 * find, and why (D77).
 */
@Derive[Equatable]
public struct InferenceResult {
    public InferenceResult(
        /**
         * `None` for a type or a package before a `.`: no value (D77).
         */
        public let exprs!: Array<?Ty> = [],
        public let pats!: Array<Ty> = [],
        public let locals!: Array<Ty> = [],
        public let fields!: Array<FieldTargets> = [],
        public let callees!: Array<CalleeTarget> = [],
        /**
         * What each name used as a value means, by its expression.
         */
        public let names!: Array<NameTarget> = [],
        /**
         * What the name after each `.` means, by its expression.
         */
        public let accesses!: Array<AccessTarget> = [],
        /**
         * What each segment of each path of a type the body writes names, by the type: of those
         * inference lowered.
         */
        public let typePaths!: Array<TypePathTarget> = [],
        /**
         * The type the body gives its declaration: a function's return type, a variable's type;
         * `None` for one of no such type.
         */
        public let ty!: ?Ty = None
    ) {}

    /**
     * The type of `id`; `None` if it is no value, a type or a package before a `.`.
     */
    public operator func [](id: ExprId): ?Ty {
        match (exprs.get(id.index)) {
            case Some(one) => one
            case None => None
        }
    }

    public operator func [](id: PatId): ?Ty {
        pats.get(id.index)
    }

    public operator func [](id: LocalId): ?Ty {
        locals.get(id.index)
    }

    /**
     * The members the name after the `.` of `expr` names, if it follows a value.
     */
    public func fieldOf(expr: ExprId): ?Array<MemberTarget> {
        match (findByIndex(fields, expr.index)) {
            case Some(one) => one.targets
            case None => None
        }
    }

    /**
     * The declaration the call whose callee is `expr` takes, if it was chosen among several; the
     * operator function the operator `expr` calls (8e).
     */
    public func calleeOf(expr: ExprId): ?DefId {
        match (findByIndex(callees, expr.index)) {
            case Some(one) => one.decl
            case None => None
        }
    }

    /**
     * What the name `expr` uses as a value means, if inference resolved it.
     */
    public func nameOf(expr: ExprId): ?BodyResolution {
        match (findByIndex(names, expr.index)) {
            case Some(one) => one.resolution
            case None => None
        }
    }

    /**
     * What the name after the `.` of `expr` means, if inference resolved it.
     */
    public func accessOf(expr: ExprId): ?FieldResolution {
        match (findByIndex(accesses, expr.index)) {
            case Some(one) => one.resolution
            case None => None
        }
    }

    /**
     * What each segment of the path of the type `ty` of the body names, if inference lowered it.
     */
    public func typePathOf(ty: TypeRefId): ?Array<PathResolution> {
        match (findByIndex(typePaths, ty.index)) {
            case Some(one) => one.resolution
            case None => None
        }
    }
}

/**
 * The types of the body of `def` (D55): its expressions checked against the type expected of them
 * where one is, else their types synthesized from what they hold, as cjc's `Check` and `Synthesize`
 * do. A body on a cycle of declarations whose types are not written (`func a() { b() }`, `func b()
 * { a() }`) is all errors: cjc cannot infer them either (N100).
 */
@CalcaTracked[cycleResult: inferBodyOnCycle]
public func inferBody(db: AnalysisDatabase, def: DefId): InferenceResult {
    Inference(db, def).run()
}

func inferBodyOnCycle(db: AnalysisDatabase, def: DefId): InferenceResult {
    let lowered = body(db, def)
    let error = Ty(db, ErrorTy)
    InferenceResult(exprs: lowered.exprs.map {_ => Some(error)}, pats: lowered.pats.map {_ => error},
        locals: lowered.locals.map {_ => error}, ty: error)
}

/**
 * The type of `def` as its signature writes it, else as its body gives it: a function's return
 * type, a variable's or property's type (N100); an error type on a cycle of such declarations.
 */
@CalcaTracked[cycleResult: declaredTyOnCycle]
public func declaredTyOf(db: AnalysisDatabase, def: DefId): Ty {
    if (let Some(ty) <- signatureTypes(db, def).ty) {
        return ty
    }
    match (inferBody(db, def).ty) {
        case Some(ty) => ty
        case None => Ty(db, ErrorTy)
    }
}

func declaredTyOnCycle(db: AnalysisDatabase, _: DefId): Ty {
    Ty(db, ErrorTy)
}

// the level of the members of the type around a body, after any local's (8d)
let MEMBER_LEVEL = 1 << 32

/**
 * What a call may call: the types of its parameters and what it returns, as seen on what it is
 * called on; `open`, the declaration whose type parameters in them are the call's to infer (8c);
 * the declaration it is, if one; how far it is from the call, cjc's scope level counted the other
 * way: a local function by the scopes out to its own, then `MEMBER_LEVEL` for a member of the type
 * around the body, one more for a declaration of the package, two for one imported (N117); the
 * name each parameter is passed by, as its signature says.
 */
struct Callable {
    Callable(let params: Array<Ty>, let ret: Ty, let open!: ?DefId = None, let decl!: ?DefId = None,
        let level!: Int64 = 0, let names!: Array<?String> = []) {}

    func at(level: Int64): Callable {
        Callable(params, ret, open: open, decl: decl, level: level, names: names)
    }

    /**
     * Whether it takes its last parameter by name: of an operator `[]`, the one assigned (N124).
     */
    func takesValue(): Bool {
        match (names.get(names.size - 1)) {
            case Some(Some(_)) => true
            case _ => false
        }
    }

    /**
     * Its type as a value, not called: the type parameters still open unknown.
     */
    func ty(db: AnalysisDatabase): Ty {
        Ty(db, FuncTy(erasedParams(db), erased(db, ret), false))
    }

    func erasedParams(db: AnalysisDatabase): Array<Ty> {
        params.map {one => erased(db, one)}
    }

    func erased(db: AnalysisDatabase, ty: Ty): Ty {
        match (open) {
            case Some(owner) => eraseParams(db, ty, owner)
            case None => ty
        }
    }
}

/**
 * A function whose body is inferred: the return type it writes, and those of its `return`s if it
 * writes none.
 */
class Frame {
    Frame(let ret: ?Ty) {}

    let returns = ArrayList<Ty>()
}

/**
 * What a write of inference replaced, while a candidate of a call is tried (8d): undone after it.
 */
enum Undo {
    | ExprWas(ExprId, ?Ty)
    | PatWas(PatId, Ty)
    | LocalWas(LocalId, Ty)
    | FieldWas(ExprId, ?FieldTargets)
    | CalleeWas(ExprId, ?CalleeTarget)
    | Returned(Frame)
}

/**
 * One body as it is inferred.
 */
class Inference {
    private let hir: Body
    private let scopes: ExprScopes
    private let sig: SignatureTypes
    private let from: ?SourceFile
    private let pkg: ?Package
    private let error: Ty
    // what an expression inference does not reach is of
    private let notInferred: Ty
    private let exprs: Array<?Ty>
    private let pats: Array<Ty>
    private let locals: Array<Ty>
    private let types: Array<?Ty>
    private let lowering: SourceTyLowering
    // by expression: an argument inferred again replaces what it found
    private let fields = HashMap<Int64, FieldTargets>()
    // by callee: an argument inferred again replaces what it found
    private let callees = HashMap<Int64, CalleeTarget>()
    // by expression: what each name used as a value means, resolved once
    private let names = HashMap<Int64, BodyResolution>()
    // by expression: what the name after each `.` means, resolved once
    private let access = HashMap<Int64, FieldResolution>()
    private let frames = ArrayList<Frame>()
    // the first variable of the next call inferred: those of the calls being inferred are under it
    private var nextVar = 0
    // `std.core`'s `Option`, a value is boxed into
    private let option: ?DefId
    // the checks against a type expected that failed: a candidate tried that fails one fits not (8d)
    private var mismatches = 0
    // how many candidates are being tried, one inside another: what is written meanwhile is undone
    private var trying = 0
    private let undo = ArrayList<Undo>()
    // the arguments of the calls whose candidates are tried that are of one type whatever is
    // expected of them, inferred once before: a candidate only compares it
    private let known = HashMap<Int64, Ty>()
    // the blocks of functions returning `Unit` and what their value is: of any type (N118)
    private let dropped = HashSet<Int64>()
    // the operators of a type by name, as looked up once in the body (8e)
    private let operators = HashMap<Ty, HashMap<String, Array<Callable>>>()

    Inference(private let db: AnalysisDatabase, private let def: DefId) {
        hir = body(db, def)
        scopes = exprScopes(db, def)
        sig = signatureTypes(db, def)
        from = sourceFileOf(db, def)
        pkg = packageOf(db, def)
        error = Ty(db, ErrorTy)
        notInferred = Ty(db, TodoTy(Todo.NotInferred))
        exprs = Array<?Ty>(hir.exprs.size, repeat: notInferred)
        pats = Array<Ty>(hir.pats.size, repeat: error)
        locals = Array<Ty>(hir.locals.size, repeat: error)
        types = Array<?Ty>(hir.types.size, repeat: None)
        lowering = SourceTyLowering(db, def, hir)
        option = packageRefOf(db, def).flatMap {ref => langItem(db, ref, LangItem.OptionEnum)}
    }

    func run(): InferenceResult {
        for (i in 0..hir.params.size) {
            let ty = sig.params.get(i) ?? error
            param(hir.params[i], ty)
        }
        let ty = match (hir.value) {
            case Some(value) => valueOfDecl(value)
            case None => sig.ty
        }
        let propTy = sig.ty ?? error
        for (accessor in hir.accessors) {
            // a getter returns the property's type, a setter takes it (N105)
            let expected = match (hir[accessor]) {
                case LambdaExpr(params, _) where params.isEmpty() => FuncTy([], propTy, false)
                case _ => FuncTy([propTy], prim("Unit"), false)
            }
            infer(accessor, Ty(db, expected))
        }
        let found = fields.values().toArray()
        sort(found, by: {a: FieldTargets, b: FieldTargets => a.expr.index.compare(b.expr.index)})
        let chosen = callees.values().toArray()
        sort(chosen, by: {a: CalleeTarget, b: CalleeTarget => a.expr.index.compare(b.expr.index)})
        let resolved = names |> map {entry: (Int64, BodyResolution) => NameTarget(ExprId(entry[0]), entry[1])} |>
            collectArray
        sort(resolved, by: {a: NameTarget, b: NameTarget => a.expr.index.compare(b.expr.index)})
        let accessed = access |> map {entry: (Int64, FieldResolution) => AccessTarget(ExprId(entry[0]), entry[1])} |>
            collectArray
        sort(accessed, by: {a: AccessTarget, b: AccessTarget => a.expr.index.compare(b.expr.index)})
        InferenceResult(exprs: exprs, pats: pats, locals: locals, fields: found, callees: chosen, names: resolved,
            accesses: accessed, typePaths: lowering.typePaths(), ty: ty)
    }

    /**
     * What the name `name` of the expression `expr` means: resolved once, whatever candidate is tried.
     */
    private func resolveName(expr: ExprId, name: String): BodyResolution {
        if (let Some(known) <- names.get(expr.index)) {
            return known
        }
        let found = resolveBodyName(db, def, scopes.scopeOf(expr), name)
        names.add(expr.index, found)
        found
    }

    /**
     * What the name after the `.` of `expr` means: resolved once, whatever candidate is tried.
     */
    private func resolveAccess(expr: ExprId): FieldResolution {
        if (let Some(known) <- access.get(expr.index)) {
            return known
        }
        let found = resolveField(db, def, expr)
        access.add(expr.index, found)
        found
    }

    private func setExpr(id: ExprId, ty: ?Ty): Unit {
        if (trying > 0) {
            undo.add(ExprWas(id, exprs[id.index]))
        }
        exprs[id.index] = ty
    }

    /**
     * Records that `id`, a type or a package before a `.`, and each before it (`pkg.Type.member`), is
     * no value (D77).
     */
    private func noValue(id: ExprId): Unit {
        match (hir[id]) {
            case PathExpr(_, _) | PrimExpr(_) => setExpr(id, None)
            case FieldExpr(receiver, _, _) =>
                setExpr(id, None)
                noValue(receiver)
            case _ => ()
        }
    }

    /**
     * The type `id` was inferred of; an error if it is no value.
     */
    private func tyOf(id: ExprId): Ty {
        exprs[id.index] ?? error
    }

    /**
     * The type `id` was inferred of, if it was.
     */
    private func inferredTyOf(id: ExprId): ?Ty {
        exprs[id.index].filter {one => one != notInferred}
    }

    /**
     * `ty` if given, as a list of none or one.
     */
    private func listOf(ty: ?Ty): Array<Ty> {
        match (ty) {
            case Some(one) => [one]
            case None => []
        }
    }

    /**
     * A type the analysis cannot find, `why`.
     */
    private func todo(why: Todo): Ty {
        Ty(db, TodoTy(why))
    }

    /**
     * What is made of `tys` when it cannot be: of a type not known among them, that one, else an
     * error, the user's (D77).
     */
    private func failed(tys: Array<Ty>): Ty {
        unknownOf(db, tys) ?? error
    }

    private func setPat(id: PatId, ty: Ty): Unit {
        if (trying > 0) {
            undo.add(PatWas(id, pats[id.index]))
        }
        pats[id.index] = ty
    }

    private func setLocal(id: LocalId, ty: Ty): Unit {
        if (trying > 0) {
            undo.add(LocalWas(id, locals[id.index]))
        }
        locals[id.index] = ty
    }

    private func setField(expr: ExprId, targets: FieldTargets): Unit {
        if (trying > 0) {
            undo.add(FieldWas(expr, fields.get(expr.index)))
        }
        fields[expr.index] = targets
    }

    private func setCallee(expr: ExprId, decl: DefId): Unit {
        if (trying > 0) {
            undo.add(CalleeWas(expr, callees.get(expr.index)))
        }
        callees[expr.index] = CalleeTarget(expr, decl)
    }

    private func addReturn(frame: Frame, ty: Ty): Unit {
        if (trying > 0) {
            undo.add(Returned(frame))
        }
        frame.returns.add(ty)
    }

    /**
     * Undoes what was written since the journal was `mark` long, the last first.
     */
    private func rollBack(mark: Int64): Unit {
        while (undo.size > mark) {
            // read before removed: -O2 miscompiles one taken apart straight from `remove`
            let last = undo[undo.size - 1]
            undo.remove(at: undo.size - 1)
            match (last) {
                case ExprWas(id, ty) => exprs[id.index] = ty
                case PatWas(id, ty) => pats[id.index] = ty
                case LocalWas(id, ty) => locals[id.index] = ty
                case FieldWas(expr, Some(was)) => fields[expr.index] = was
                case FieldWas(expr, None) => fields.remove(expr.index)
                case CalleeWas(expr, Some(was)) => callees[expr.index] = was
                case CalleeWas(expr, None) => callees.remove(expr.index)
                case Returned(frame) => frame.returns.remove(at: frame.returns.size - 1)
            }
        }
    }

    /**
     * Whether a value of the type `ty` may be given where `expected` is (N111, N116).
     */
    private func fits(ty: Ty, expected: Ty): Bool {
        isAssignable(db, ty, expected, from, option)
    }

    /**
     * Infers `value`, the block of a function or the initializer of a variable, against the type
     * its declaration writes; the type it gives the declaration.
     */
    private func valueOfDecl(value: ExprId): ?Ty {
        match (def.item(db).kind) {
            case Func | Main | Macro => function(sig.ty, value)
            case Init | PrimaryInit | Finalizer =>
                function(prim("Unit"), value)
                None
            case _ =>
                let valueTy = infer(value, sig.ty)
                sig.ty ?? valueTy
        }
    }

    /**
     * Infers `block`, the body of a function returning `ret` if written; the return type: `ret`, else
     * the block's type joined with those of its `return`s (N100). Of no `ret`, the block is checked
     * against `hint` if given, a return type known in part.
     */
    private func function(ret: ?Ty, block: ExprId, hint!: ?Ty = None): Ty {
        let frame = Frame(ret)
        frames.add(frame)
        // of a function returning `Unit`, the block's value is dropped, whatever its type (N118)
        if (let Some(one) <- ret && one.kind(db) == PrimTy("Unit")) {
            dropped.add(block.index)
        }
        let blockTy = infer(block, ret ?? hint)
        frames.remove(at: frames.size - 1)
        match (ret) {
            case Some(one) => one
            case None => joinTys(db, [blockTy].concat(frame.returns.toArray()), from)
        }
    }

    private func param(one: BodyParam, ty: Ty): Unit {
        if (let Some(local) <- one.local) {
            setLocal(local, ty)
        }
        if (let Some(value) <- one.defaultValue) {
            infer(value, ty)
        }
    }

    private func prim(name: String): Ty {
        Ty(db, PrimTy(name))
    }

    /**
     * The type of the lang item `item`, applied to `args`.
     */
    private func langTy(item: LangItem, args: Array<Ty>): Ty {
        match (langId(item)) {
            case Some(id) => Ty(db, DeclTy(id, args))
            case None => todo(Todo.NoStd)
        }
    }

    /**
     * `?arg`, `std.core`'s `Option<arg>`.
     */
    private func optionOf(arg: Ty): Ty {
        match (option) {
            case Some(id) => Ty(db, DeclTy(id, [arg]))
            case None => todo(Todo.NoStd)
        }
    }

    /**
     * `T` of `ty`, an `Option<T>`; none of any other type.
     */
    private func optionArg(ty: Ty): ?Ty {
        match (ty.kind(db)) {
            case DeclTy(id, args) where args.size == 1 && Some(id) == option => args[0]
            case _ => None
        }
    }

    private func langId(item: LangItem): ?DefId {
        let ref = packageRefOf(db, def) ?? return None
        langItem(db, ref, item)
    }

    /**
     * The type `id` the body writes.
     */
    private func typeAt(id: TypeRefId): Ty {
        if (let Some(ty) <- types[id.index]) {
            return ty
        }
        let ty = lowering.lowerType(id)
        types[id.index] = ty
        ty
    }

    /**
     * Infers `id`, checked against `expected` if given, and records its type; a type that may not
     * be given where `expected` is, a mismatch.
     */
    private func infer(id: ExprId, expected: ?Ty): Ty {
        let ty = inferExpr(id, expected)
        setExpr(id, ty)
        if (let Some(one) <- expected && !fits(ty, one) &&
            !(dropped.contains(id.index) && one.kind(db) == PrimTy("Unit"))) {
            mismatches++
        }
        ty
    }

    /**
     * What the value of `id` is, if it is a block, a branch or a body: the last expression of a
     * block, each branch, the block of `synchronized` or `unsafe`.
     */
    private func tailsOf(id: ExprId): Array<ExprId> {
        match (hir[id]) {
            case BlockExpr(stmts) => match (stmts.get(stmts.size - 1)) {
                case Some(ExprStmt(expr)) => [expr]
                case _ => []
            }
            case IfExpr(_, then, Some(otherwise)) => [then, otherwise]
            case MatchExpr(_, arms) => arms.map {arm => arm.body}
            case QuestMatchExpr(_, arms) => arms.map {arm => arm.body}
            case TryExpr(_, tried, catches, _) => [tried].concat(catches.map {arm => arm.body})
            case SynchronizedExpr(_, block) => [block]
            case UnsafeExpr(block) => [block]
            case _ => []
        }
    }

    private func inferExpr(id: ExprId, expected: ?Ty): Ty {
        if (dropped.contains(id.index)) {
            for (one in tailsOf(id)) {
                dropped.add(one.index)
            }
        }
        match (hir[id]) {
            case MissingExpr => error
            case QuoteExpr => quoteTy()
            case MacroExpr(call) => macroTy(call)
            case LitExpr(text) => literalTy(text, expected)
            case StrExpr(parts) =>
                for (part in parts) {
                    infer(part, None)
                }
                langTy(LangItem.StringStruct, [])
            case PathExpr(name, args) => pathTy(id, name, args, expected)
            case FieldExpr(receiver, name, args) => fieldTy(id, receiver, name, args, expected)
            // a call whose value is dropped returns what it may (N118)
            case CallExpr(callee, args) => callTy(callee, args, expected.filter {
                one => !(dropped.contains(id.index) && one.kind(db) == PrimTy("Unit"))
            })
            case IndexExpr(base, indices) => indexTy(id, base, indices, expected)
            case UnaryExpr(op, operand) => unaryTy(id, op, operand, expected)
            case BinaryExpr(op, lhs, rhs) => binaryTy(id, op, lhs, rhs, expected)
            case IsExpr(inner, _) =>
                infer(inner, None)
                prim("Bool")
            case AsExpr(inner, ty) =>
                infer(inner, None)
                optionOf(typeAt(ty))
            case RangeExpr(start, end, step, _) => rangeTy(start, end, step, expected)
            case PostfixExpr(inner, _) =>
                infer(inner, None)
                prim("Unit")
            case TupleExpr(elements) =>
                let wanted = match (expected.map {one => one.kind(db)}) {
                    case Some(TupleTy(tys)) where tys.size == elements.size => tys
                    case _ => Array<Ty>()
                }
                let tys = Array(elements.size) {i => infer(elements[i], wanted.get(i))}
                // of the tuple expected if each element fits it (`(s, t)` a `(String, ?Tree)`)
                if (!wanted.isEmpty() && (0..tys.size).iterator().all {i => fits(tys[i], wanted[i])}) {
                    Ty(db, TupleTy(wanted))
                } else {
                    Ty(db, TupleTy(tys))
                }
            case ArrayExpr(elements) => arrayTy(elements, expected)
            case UnitExpr => prim("Unit")
            case IfExpr(condition, then, otherwise) =>
                infer(condition, prim("Bool"))
                match (otherwise) {
                    case Some(one) => branches([then, one], expected, dropped.contains(id.index))
                    // of no `else`, `Unit` (N102)
                    case None =>
                        dropped.add(then.index)
                        infer(then, None)
                        prim("Unit")
                }
            case LetExpr(patterns, value) =>
                let valueTy = infer(value, None)
                for (pat in patterns) {
                    bindPat(pat, valueTy)
                }
                prim("Bool")
            case MatchExpr(scrutinee, arms) => matchExprTy(scrutinee, arms, expected, dropped.contains(id.index))
            case QuestMatchExpr(selector, arms) => questMatchTy(selector, arms)
            case LangExpr(item) => match (langId(item)) {
                case Some(decl) => declValueTy(decl, [], expected)
                case None => todo(Todo.NoStd)
            }
            case TryExpr(resources, tried, catches, cleanup) =>
                tryExprTy(resources, tried, catches, cleanup, expected, dropped.contains(id.index))
            case ForExpr(pat, iterated, guard, loopBody) =>
                bindPat(pat, elementTy(infer(iterated, None)))
                if (let Some(one) <- guard) {
                    infer(one, prim("Bool"))
                }
                dropped.add(loopBody.index)
                infer(loopBody, None)
                prim("Unit")
            case WhileExpr(condition, loopBody) =>
                infer(condition, prim("Bool"))
                dropped.add(loopBody.index)
                infer(loopBody, None)
                prim("Unit")
            case DoWhileExpr(loopBody, condition) =>
                dropped.add(loopBody.index)
                infer(loopBody, None)
                infer(condition, prim("Bool"))
                prim("Unit")
            case ThrowExpr(inner) =>
                infer(inner, None)
                prim("Nothing")
            case ReturnExpr(value) =>
                returned(value)
                prim("Nothing")
            case BreakExpr | ContinueExpr => prim("Nothing")
            case SpawnExpr(context, lambda) =>
                if (let Some(one) <- context) {
                    infer(one, None)
                }
                let lambdaTy = infer(lambda, None)
                match (lambdaTy.kind(db)) {
                    case FuncTy(_, ret, _) => langTy(LangItem.FutureClass, [ret])
                    case _ => failed([lambdaTy])
                }
            case SynchronizedExpr(lock, block) =>
                infer(lock, None)
                infer(block, expected)
            case UnsafeExpr(block) => infer(block, expected)
            case LambdaExpr(params, block) => lambdaTy(params, block, expected)
            case ThisExpr => thisTy()
            case SuperExpr => superTy()
            case WildcardExpr => expected ?? error
            case ConvExpr(name, inner) =>
                infer(inner, None)
                prim(name)
            // a type of the language as a value; one before a `.` is no value, never inferred
            case PrimExpr(_) => error
            case VArrayExpr(ty, args) =>
                for (arg in args) {
                    infer(arg.expr, None)
                }
                typeAt(ty)
            case BlockExpr(stmts) => blockTy(stmts, expected)
        }
    }

    /**
     * `quote(…)`: `std.ast`'s `Tokens`, in a file that imports from `std.ast`, else an error (cjc:
     * "import 'std.ast' to use the 'quote' expression", N136).
     */
    private func quoteTy(): Ty {
        let file = from ?? return todo(Todo.NoStd)
        let imported = itemTree(db, file).imports.iterator().any {
            item => item.paths.iterator().any {
                path => path.segments.size >= 2 && path.segments[0] == "std" && path.segments[1] == "ast"
            }
        }
        if (imported) {
            langTy(LangItem.TokensClass, [])
        } else {
            error
        }
    }

    /**
     * A macro call, its arguments each inferred alone: of std.unittest's expression macros, the type
     * their expansion gives, whatever the arguments (N136); of any other, or of one not found, a type
     * the analysis cannot find (#176).
     */
    private func macroTy(call: MacroCall): Ty {
        for (arg in call.args) {
            infer(arg.expr, None)
        }
        let file = from ?? return todo(Todo.MacroCall)
        let owner = pkg ?? return todo(Todo.MacroCall)
        let decl = match (resolveMacroPath(db, owner, file, call.path).get(call.path.size - 1)) {
            case Some(Found(ids)) where ids.size == 1 => ids[0]
            // a macro of a `[…]` and one of none, of one name and package (`@Expect`, `@AssertThrows`): the
            // call takes the one it fits
            case Some(Ambiguous(targets)) => oneMacroOf(targets) ?? return todo(Todo.MacroCall)
            // not found, where cjc may find it: `cjpm test` compiles a package with `--test`, its macros
            // std.unittest.testmacro's unimported (N137, #255)
            case _ => return todo(Todo.MacroCall)
        }
        if (packageRefOf(db, decl).map {one => nameOf(db, one)} != Some("std.unittest.testmacro")) {
            return todo(Todo.MacroCall)
        }
        let thrown = call.attr.map {tys => tys.map {one => typeAt(one)}}
        match (itemOf(db, decl).flatMap {item => item.names.get(0)} ?? "") {
            case "Expect" | "Assert" | "PowerAssert" | "FailExpect" => prim("Unit")
            case "Fail" => prim("Nothing")
            // what it catches: `[A | B]` their join, as `catch (e: A | B)`'s
            case "AssertThrows" => match (thrown) {
                case None => langTy(LangItem.ExceptionClass, [])
                case Some(tys) where tys.isEmpty() => todo(Todo.MacroCall)
                case Some(tys) => joinTys(db, tys, from)
            }
            // `[A | B]` an `Option<Exception>`
            case "ExpectThrows" => match (thrown) {
                case Some(tys) where tys.size == 1 => optionOf(tys[0])
                case Some(tys) where tys.isEmpty() => todo(Todo.MacroCall)
                case _ => optionOf(langTy(LangItem.ExceptionClass, []))
            }
            case _ => todo(Todo.MacroCall)
        }
    }

    /**
     * The first of `targets` if each is a declaration of one package and one name.
     */
    private func oneMacroOf(targets: Array<ScopeTarget>): ?DefId {
        let ids = ArrayList<DefId>()
        for (target in targets) {
            match (target) {
                case OfDecl(id) => ids.add(id)
                case _ => return None
            }
        }
        let first = ids.get(0) ?? return None
        let pkgOf = {id: DefId => packageRefOf(db, id)}
        let nameOf = {id: DefId => itemOf(db, id).flatMap {item => item.names.get(0)}}
        if (ids.iterator().all {id => pkgOf(id) == pkgOf(first) && nameOf(id) == nameOf(first)}) {
            first
        } else {
            None
        }
    }

    /**
     * A name of the body that names nothing: an error (cjc: "undeclared identifier"), but in a package
     * where a macro whose expansion is not read may declare it (#176).
     */
    private func notFound(): Ty {
        match (pkg) {
            case Some(one) where packageHasUnreadMacros(db, one) => todo(Todo.MacroMember)
            case _ => error
        }
    }

    /**
     * A member of a value of the type `recv` that is not found: of a type not known, that one; of a
     * type a macro whose expansion is not read is called on, maybe the macro's (#176); else an error
     * (cjc: "'x' is not a member of").
     */
    private func memberNotFound(recv: Ty): Ty {
        if (isUnknown(db, recv)) {
            return recv
        }
        if (isMacroTyped(recv)) {
            todo(Todo.MacroMember)
        } else {
            error
        }
    }

    /**
     * Whether a macro whose expansion is not read is called on the type of `ty`, or on a bound's.
     */
    private func isMacroTyped(ty: Ty): Bool {
        headsOf(ty).iterator().any {
            head => match (head.kind(db)) {
                case DeclTy(id, _) => hasUnreadMacros(db, id)
                case _ => false
            }
        }
    }

    /**
     * What a call of `callee` that fits none of what it names is: a type the analysis cannot find if
     * a macro whose expansion is not read may declare one that fits, a member of a type it is called
     * on or a name of the package (#176); else an error (cjc: "no matching function").
     */
    private func macroFailure(callee: ExprId): Ty {
        let byMacro = match (hir[callee]) {
            case FieldExpr(receiver, _, _) => match (resolveAccess(callee)) {
                case OfValue => isMacroTyped(tyOf(receiver))
                case TypeMembers(_) => isMacroTyped(typeOfReceiver(receiver, None))
                case _ => false
            }
            case PathExpr(name, _) => match (resolveName(callee, name)) {
                case Values(targets) where targets.iterator().all {
                    one => match (one) {
                        case LocalOf(_) => true
                        case _ => false
                    }
                } => false
                case _ => pkg.map {one => packageHasUnreadMacros(db, one)} ?? false
            }
            case _ => false
        }
        if (byMacro) {
            todo(Todo.MacroMember)
        } else {
            error
        }
    }

    /**
     * A `FieldExpr` of the left `receiver` whose name `resolveField` finds nothing of: a member of a
     * package or a type not found, its left no value; else its left, inferred, names nothing (N75).
     */
    private func noField(receiver: ExprId): Ty {
        match (receiverOf(db, def, receiver)) {
            case PackageReceiver(_) =>
                noValue(receiver)
                notFound()
            case TypesReceiver(types) =>
                match (hir[receiver]) {
                    case ThisExpr | SuperExpr => infer(receiver, None)
                    case _ => noValue(receiver)
                }
                let byMacro = types.iterator().any {
                    one => match (one) {
                        case DeclType(id) => hasUnreadMacros(db, id)
                        case _ => false
                    }
                }
                if (byMacro) {
                    todo(Todo.MacroMember)
                } else {
                    error
                }
            case _ => failed([infer(receiver, None)])
        }
    }

    /**
     * A block: its statements in order; the type of the last if it is an expression, checked against
     * `expected`, else `Unit`.
     */
    private func blockTy(stmts: Array<Stmt>, expected: ?Ty): Ty {
        for (i in 0..stmts.size) {
            match (stmts[i]) {
                case LetStmt(pat, ty, value) =>
                    let declared = ty.map {one => typeAt(one)}
                    let valueTy = value.map {one => infer(one, declared)}
                    bindPat(pat, declared ?? valueTy ?? error)
                case ExprStmt(expr) where i == stmts.size - 1 => return infer(expr, expected)
                // a statement's value is not used: of any type, an `if` of branches of no join (N138)
                case ExprStmt(expr) =>
                    dropped.add(expr.index)
                    infer(expr, None)
                case FuncStmt(index) => localFunc(index)
            }
        }
        prim("Unit")
    }

    /**
     * The local function `index`: its local a function type, its return type inferred from its body
     * if it writes none (N100), and unknown while that body is inferred.
     */
    private func localFunc(index: Int64): Unit {
        let fn = hir.funcs[index]
        let params = fn.params.map {one => one.ty.map {ty => typeAt(ty)} ?? error}
        for (i in 0..fn.params.size) {
            param(fn.params[i], params[i])
        }
        let written = fn.ret.map {one => typeAt(one)}
        setLocal(fn.local, Ty(db, FuncTy(params, written ?? error, false)))
        if (let Some(block) <- fn.body) {
            let ret = function(written, block)
            setLocal(fn.local, Ty(db, FuncTy(params, ret, false)))
        }
    }

    /**
     * A `return` of `value`: checked against the return type of the function it is in, or one of
     * those its return type is joined from.
     */
    private func returned(value: ?ExprId): Unit {
        let frame = frames.get(frames.size - 1)
        let ret = frame.flatMap {one => one.ret}
        let ty = match (value) {
            case Some(one) => infer(one, ret)
            case None => prim("Unit")
        }
        if (let Some(one) <- frame && one.ret.isNone()) {
            addReturn(one, ty)
        }
    }

    /**
     * Branches of an `if`, `match` or `try`, each checked against `expected`: their join, or, if
     * there is none, what was expected (N97, N106); of no join of types known and a value not used,
     * `Unit` (N138).
     */
    private func branches(ids: Array<ExprId>, expected: ?Ty, isDropped: Bool): Ty {
        let tys = ids.map {one => infer(one, expected)}
        let joined = joinTys(db, tys, from)
        // checked against a type each branch fits, the expression is of it, as cjc's check gives
        match (expected) {
            case Some(one) where isUnknown(db, joined) || tys.iterator().all {ty => fits(ty, one)} => one
            case _ where isDropped && joined.kind(db) == ErrorTy && unknownOf(db, tys).isNone() => prim("Unit")
            case _ => joined
        }
    }

    private func matchExprTy(scrutinee: ?ExprId, arms: Array<MatchArm>, expected: ?Ty, isDropped: Bool): Ty {
        let scrutineeTy = scrutinee.map {one => infer(one, None)}
        for (arm in arms) {
            for (pat in arm.pats) {
                bindPat(pat, scrutineeTy ?? error)
            }
            if (let Some(guard) <- arm.guard) {
                infer(guard, prim("Bool"))
            }
            if (let Some(condition) <- arm.condition) {
                infer(condition, prim("Bool"))
            }
        }
        branches(arms.map {arm => arm.body}, expected, isDropped)
    }

    /**
     * The `match` an optional chain is desugared to, as cjc's `SynQuestSugarMatchCaseBody`, whatever
     * is expected of it: its selector synthesized, an `Option` (N133); its first arm synthesized, the
     * type of the `match`, the second checked against it; no join.
     */
    private func questMatchTy(selector: ExprId, arms: Array<MatchArm>): Ty {
        let selectorTy = infer(selector, None)
        let isOption = optionArg(selectorTy).isSome()
        // cjc's "cannot use optional chaining on non-optional value"
        if (!isOption && !isUnknown(db, selectorTy)) {
            mismatches++
        }
        for (arm in arms) {
            for (pat in arm.pats) {
                bindPat(pat, selectorTy)
            }
        }
        let some = infer(arms[0].body, None)
        infer(arms[1].body, some)
        if (isOption) {
            some
        } else {
            failed([selectorTy])
        }
    }

    private func tryExprTy(resources: Array<Resource>, tried: ExprId, catches: Array<CatchArm>, cleanup: ?ExprId,
        expected: ?Ty, isDropped: Bool): Ty {
        for (resource in resources) {
            let declared = resource.ty.map {one => typeAt(one)}
            let valueTy = infer(resource.value, declared)
            if (let Some(local) <- resource.local) {
                setLocal(local, declared ?? valueTy)
            }
        }
        for (arm in catches) {
            if (let Some(local) <- arm.local) {
                // `e: A | B` is of their join
                setLocal(local, joinTys(db, arm.types.map {one => typeAt(one)}, from))
            }
        }
        if (let Some(one) <- cleanup) {
            infer(one, None)
        }
        branches([tried].concat(catches.map {arm => arm.body}), expected, isDropped)
    }

    /**
     * The type of the elements of what `for` iterates over: the argument of the `Iterable` it is an
     * instance of (N105).
     */
    private func elementTy(iterated: Ty): Ty {
        let iterable = langId(LangItem.IterableInterface) ?? return todo(Todo.NoStd)
        match (asInstanceOf(db, iterated, iterable, from).map {one => one.kind(db)}) {
            case Some(DeclTy(_, args)) => args.get(0) ?? error
            // cjc: the type is not an instance of `Iterable`
            case _ => failed([iterated])
        }
    }

    /**
     * A lambda: its parameters of the types they write, else of the function type expected; it
     * returns what that type does, else the join of its block's type and its `return`s' (N103).
     */
    private func lambdaTy(params: Array<BodyParam>, block: ExprId, expected: ?Ty): Ty {
        let wanted: ?(Array<Ty>, ?Ty) = match (expected.map {one => one.kind(db)}) {
            case Some(FuncTy(tys, ret, _)) where tys.size == params.size => (tys, ret)
            case _ => None
        }
        // cjc: a parameter's type must be written, or told by the type expected
        let untold = failed(listOf(expected))
        let paramTys = Array(params.size) {
            i => match (params[i].ty) {
                case Some(ty) => typeAt(ty)
                case None => wanted.flatMap {one => one[0].get(i)} ?? untold
            }
        }
        for (i in 0..params.size) {
            param(params[i], paramTys[i])
        }
        let ret = wanted.flatMap {one => one[1]}
        // a return type holding a type argument not solved yet (8c) is what the body gives, checked
        // against it as far as it is known: the body tells the argument (`Option<R>` of `filterMap`,
        // N132)
        let retTy = match (ret) {
            case Some(one) where isUnknown(db, one) => function(None, block)
            case Some(one) where hasUnknowns(db, one) => function(None, block, hint: one)
            case _ => function(ret, block)
        }
        Ty(db, FuncTy(paramTys, retTy, false))
    }

    /**
     * The type `this` is of in the body: the type it is a member of, or that its `extend` extends.
     */
    private func thisTy(): Ty {
        let parent = parentOf(db, def) ?? return error
        match (parent.item(db).kind) {
            case Extend => signatureTypes(db, parent).ty ?? error
            case Class | Interface | Struct | Enum => selfTyOf(db, parent)
            case _ => error
        }
    }

    /**
     * The superclass of the class the body is in, its arguments as the class names them.
     */
    private func superTy(): Ty {
        let parent = parentOf(db, def) ?? return error
        if (parent.item(db).kind != ItemKind.Class) {
            return error
        }
        for (one in signatureTypes(db, parent).supers) {
            if (let DeclTy(id, _) <- one.kind(db) && id.item(db).kind == ItemKind.Class) {
                return one
            }
        }
        error
    }

    /**
     * A literal: a number of its suffix's type, else of the type expected if it is one of its kind,
     * `?T` looked through, else `Int64` or `Float64`; never of another branch's type (N98).
     */
    private func literalTy(text: String, expected: ?Ty): Ty {
        if (text == "true" || text == "false") {
            return prim("Bool")
        }
        if (text.startsWith("r'") || text.startsWith("r\"")) {
            return prim("Rune")
        }
        if (text.startsWith("b'")) {
            return prim("UInt8")
        }
        if (!isNumber(text)) {
            return langTy(LangItem.StringStruct, [])
        }
        let lower = text.replace("_", "").toAsciiLower()
        let isHex = lower.startsWith("0x")
        if (let Some(suffix) <- suffixOf(lower, isHex)) {
            return prim(suffix)
        }
        let isFloat = if (isHex) {
            lower.contains("p") || lower.contains(".")
        } else {
            lower.contains(".") || lower.contains("e")
        }
        let wanted = expectedPrim(expected)
        let (kinds, fallback) = if (isFloat) {
            (FLOAT_TYPES, "Float64")
        } else {
            (INTEGER_TYPES, "Int64")
        }
        match (wanted) {
            case Some(name) where kinds.contains(name) => prim(name)
            case _ => prim(fallback)
        }
    }

    /**
     * `ty`, an `Option` looked through: what a value given for it is boxed from.
     */
    private func unboxed(ty: Ty): Ty {
        match (ty.kind(db)) {
            case DeclTy(id, args) where args.size == 1 && Some(id) == option => unboxed(args[0])
            case _ => ty
        }
    }

    /**
     * The type of the language `expected` is, `?T` looked through.
     */
    private func expectedPrim(expected: ?Ty): ?String {
        let one = expected ?? return None
        match (one.kind(db)) {
            case PrimTy(name) => name
            case DeclTy(id, args) where args.size == 1 && Some(id) == option =>
                expectedPrim(args[0])
            case _ => None
        }
    }

    private func isNumericLiteral(id: ExprId): Bool {
        match (hir[id]) {
            case LitExpr(text) => isNumber(text)
            case UnaryExpr("-", inner) => isNumericLiteral(inner)
            case _ => false
        }
    }

    /**
     * `!x`, `-x`: of a type of the language, its own; else the operator its type declares (N123).
     */
    private func unaryTy(id: ExprId, op: String, operand: ExprId, expected: ?Ty): Ty {
        // a type of the language expected passes to the operand (`let x: ?Int8 = -1`), another not
        let ty = infer(operand, expected.filter {one => isPrim(unboxed(one))})
        match (ty.kind(db)) {
            case PrimTy(name) where op == "!" && (name == "Bool" || INTEGER_TYPES.contains(name)) => ty
            case PrimTy(name) where op == "-" && (INTEGER_TYPES.contains(name) || FLOAT_TYPES.contains(name)) => ty
            case _ => operatorTy(id, ty, op, [], expected)
        }
    }

    /**
     * An operator between two: an assignment's `assignTy`; one of the language's between its types,
     * a literal of the type of the other side (N99); else the operator the left's type declares,
     * called with the right (N122), as cjc tries the language's first and the declared after.
     */
    private func binaryTy(id: ExprId, op: String, lhs: ExprId, rhs: ExprId, expected: ?Ty): Ty {
        if (ASSIGNMENTS.contains(op)) {
            return assignTy(id, op, lhs, rhs)
        }
        if (op == "&&" || op == "||") {
            infer(lhs, prim("Bool"))
            infer(rhs, prim("Bool"))
            return prim("Bool")
        }
        // a value dropped is of any type, as a call's (N118)
        let kept = expected.filter {one => !(dropped.contains(id.index) && one.kind(db) == PrimTy("Unit"))}
        match (op) {
            case "??" => return coalescingTy(lhs, rhs, kept)
            // `x |> f` is `f(x)` (N128)
            case "|>" => return callTy(rhs, [CallArg(None, lhs)], kept)
            case "~>" => return compositionTy(id, lhs, rhs, expected)
            case _ => ()
        }
        if (!COMPARISONS.contains(op) && !ARITHMETIC.contains(op)) {
            return failed([infer(lhs, None), infer(rhs, None)])
        }
        let isComparison = COMPARISONS.contains(op)
        let left = if (isNumericLiteral(lhs) && !isNumericLiteral(rhs)) {
            // a number before what is not: of the type of the other side, if one of the language
            let found = builtin {
                =>
                let right = infer(rhs, None)
                if (!isPrim(right)) {
                    return None
                }
                let left = infer(lhs, right)
                if (!fits(left, right)) {
                    return None
                }
                builtinTy(op, left, right)
            }
            if (let Some(ty) <- found) {
                return ty
            }
            // else alone, of its default type, the right not told anything (N125)
            infer(lhs, None)
        } else {
            let synthesized = infer(lhs, if (isComparison) {
                None
            } else {
                primOnly(expected)
            })
            if (isPrim(synthesized) || isTuple(synthesized)) {
                // but a comparison: `==` of a type takes one of that type
                let found = builtin {
                    =>
                    let wanted = if (isComparison) {
                        rightExpected(op, synthesized)
                    } else {
                        primOnly(rightExpected(op, synthesized))
                    }
                    let right = infer(rhs, wanted)
                    if (let Some(one) <- wanted && !fits(right, one)) {
                        return None
                    }
                    builtinTy(op, synthesized, right)
                }
                if (let Some(ty) <- found) {
                    return ty
                }
            }
            synthesized
        }
        operatorTy(id, left, op, [CallArg(None, rhs)], expected)
    }

    /**
     * `lhs ?? rhs`, as cjc's `ChkCoalescingExpr`: the left synthesized alone, an `Option<T>`; the
     * right checked against `T`, then of `T`, or, a type expected, `T` checked against it and the
     * right against it, then of it; no join of the two (N127).
     */
    private func coalescingTy(lhs: ExprId, rhs: ExprId, expected: ?Ty): Ty {
        let left = infer(lhs, None)
        let inner = match (optionArg(left)) {
            case Some(one) => one
            case None =>
                // cjc: "coalescing is only valid for 'Option'"
                if (!isUnknown(db, left)) {
                    mismatches++
                }
                infer(rhs, None)
                return failed([left])
        }
        match (expected) {
            case Some(one) =>
                if (!fits(inner, one)) {
                    mismatches++
                }
                infer(rhs, one)
                one
            case None =>
                infer(rhs, inner)
                inner
        }
    }

    /**
     * `lhs ~> rhs`, as cjc: a call of `std.core`'s `composition(lhs, rhs)`, of `(T1) -> T2` and
     * `(T2) -> T3` a `(T1) -> T3`; a lambda of a parameter not written an error, its operands
     * synthesized alone before the call (N129).
     */
    private func compositionTy(id: ExprId, lhs: ExprId, rhs: ExprId, expected: ?Ty): Ty {
        let composition = langId(LangItem.CompositionFunc)
        match (composition) {
            case Some(decl) where !isUntypedLambda(lhs) && !isUntypedLambda(rhs) =>
                callWith(id, funcCallable(decl, [], None), [CallArg(None, lhs), CallArg(None, rhs)], expected)
            case _ =>
                // cjc: "parameters of this lambda expression must have type annotations"
                mismatches++
                infer(lhs, None)
                infer(rhs, None)
                error
        }
    }

    /**
     * What `op`, one of the language's, gives between its types `left` and `right`: a comparison
     * `Bool`, an arithmetic of numbers the left's type, `==` and `!=` of tuples `Bool`; `None`
     * between others.
     */
    private func builtinTy(op: String, left: Ty, right: Ty): ?Ty {
        let isComparison = COMPARISONS.contains(op)
        match ((left.kind(db), right.kind(db))) {
            case (PrimTy(_), PrimTy(_)) where isComparison => prim("Bool")
            case (PrimTy(name), PrimTy(_)) where INTEGER_TYPES.contains(name) || FLOAT_TYPES.contains(name) => left
            case (TupleTy(_), TupleTy(_)) where op == "==" || op == "!=" => prim("Bool")
            case _ => None
        }
    }

    /**
     * An assignment, `Unit`: its right checked against its left; `a[i] = v` of a type's `[]` a
     * call of its `[](i, value!: T)` (N124); `x op= v` the language's `op`, else `x = x.op(v)`, what
     * the operator gives taken by `x` (N126).
     */
    private func assignTy(id: ExprId, op: String, lhs: ExprId, rhs: ExprId): Ty {
        if (op == "=" && let IndexExpr(base, indices) <- hir[lhs]) {
            let baseTy = infer(base, None)
            if (!isIndexedByLanguage(baseTy)) {
                let args = indices.map {one => CallArg(None, one)}.concat([CallArg(None, rhs)])
                let (failure, chosen) = operatorCall(lhs, baseTy, "[]", args, None, setter: true)
                // `a[i]` is of what is assigned to it
                let value = chosen.flatMap {one => one.params.get(one.params.size - 1)}
                setExpr(lhs, value ?? failure)
                return prim("Unit")
            }
        }
        let target = infer(lhs, None)
        if (op == "=") {
            infer(rhs, target)
            return prim("Unit")
        }
        let base = op[0..op.size - 1]
        if (base == "&&" || base == "||") {
            infer(rhs, prim("Bool"))
            return prim("Unit")
        }
        if (isPrim(target)) {
            // `**=` of an integer takes a `UInt64`; `<<=` its left's type (N118)
            let found = builtin {
                =>
                let wanted = if (base == "**") {
                    rightExpected("**", target)
                } else {
                    target
                }
                let right = infer(rhs, wanted)
                if (let Some(one) <- wanted && !fits(right, one)) {
                    return None
                }
                builtinTy(base, target, right)
            }
            if (found.isSome()) {
                return prim("Unit")
            }
        }
        let ty = operatorTy(id, target, base, [CallArg(None, rhs)], target)
        if (!fits(ty, target)) {
            mismatches++
        }
        prim("Unit")
    }

    /**
     * Runs `attempt`, a way of the language's own operators, as cjc tries one with its diagnostics
     * suppressed: what it writes kept if it gives a type, its operands fitting it, else undone, as a
     * candidate tried is (A27). What fails inside an operand is no reason to drop the language's
     * operator: it fails another way too.
     */
    private func builtin(attempt: () -> ?Ty): ?Ty {
        let mark = undo.size
        let before = mismatches
        let vars = nextVar
        trying++
        let ty = attempt()
        trying--
        if (let Some(one) <- ty) {
            // kept: what it journaled is for a candidate tried around it to undo, if there is one
            if (trying == 0) {
                undo.clear()
            }
            return one
        }
        rollBack(mark)
        mismatches = before
        nextVar = vars
        None
    }

    /**
     * The operator `op` of a value of the type `recv` called with `args`, as cjc's
     * `DesugarOperatorOverloadExpr` calls `recv.op(args)`: what it returns, or an error type.
     */
    private func operatorTy(id: ExprId, recv: Ty, op: String, args: Array<CallArg>, expected: ?Ty): Ty {
        operatorCall(id, recv, op, args, expected)[0]
    }

    /**
     * A call of the operator `op` of a value of the type `recv` with `args`: its members of that
     * name of as many parameters, `[]`'s taking `value` last if `setter` and the others if not,
     * chosen among as a call's candidates are (N122); the one taken recorded as what `id` calls.
     * What it returns, and the one taken.
     */
    private func operatorCall(id: ExprId, recv: Ty, op: String, args: Array<CallArg>, expected: ?Ty,
        setter!: Bool = false): (Ty, ?Callable) {
        let candidates = operatorCallables(recv, op).filter {
            one => one.params.size == args.size && one.takesValue() == setter
        }
        let chosen = if (candidates.size > 1) {
            chooseOverload(id, candidates, args, expected)
        } else {
            candidates.get(0)
        }
        match (chosen) {
            case Some(callable) =>
                if (let Some(decl) <- callable.decl) {
                    setCallee(id, decl)
                }
                (callWith(id, callable, args, expected), callable)
            case None =>
                // as a call's: candidates of which none fits, or no one most specific
                if (!candidates.isEmpty()) {
                    mismatches++
                }
                let argTys = args.map {arg => infer(arg.expr, None)}
                // an operator a macro whose expansion is not read may declare (`@CalcaInterned`'s `==`)
                let byMacro = if (isMacroTyped(recv)) {
                    todo(Todo.MacroMember)
                } else {
                    error
                }
                (unknownOf(db, [recv].concat(argTys)) ?? byMacro, None)
        }
    }

    /**
     * The operators named `op` a value of the type `ty` has: its type's, or a type parameter's
     * bounds', as its other members (N86, N107).
     */
    private func operatorCallables(ty: Ty, op: String): Array<Callable> {
        let ofTy = match (operators.get(ty)) {
            case Some(one) => one
            case None =>
                let one = HashMap<String, Array<Callable>>()
                operators[ty] = one
                one
        }
        if (let Some(found) <- ofTy.get(op)) {
            return found
        }
        let found = lookUpOperators(ty, op)
        ofTy[op] = found
        found
    }

    private func lookUpOperators(ty: Ty, op: String): Array<Callable> {
        for (head in headsOf(ty)) {
            let start = match (head.kind(db)) {
                case DeclTy(id, _) => ExtendedType.DeclType(id)
                case PrimTy(name) => ExtendedType.PrimType(name)
                case _ => continue
            }
            let found = ArrayList<Callable>()
            for (target in memberLookup(db, [start], op, from: from) where isMemberOf(target, head)) {
                if (let MemberDecl(decl) <- target && decl.item(db).kind == ItemKind.Func) {
                    found.add(funcCallable(decl, [], head))
                }
            }
            if (!found.isEmpty()) {
                return overriding(found.toArray())
            }
        }
        []
    }

    private func isPrim(ty: Ty): Bool {
        match (ty.kind(db)) {
            case PrimTy(_) => true
            case _ => false
        }
    }

    private func isTuple(ty: Ty): Bool {
        match (ty.kind(db)) {
            case TupleTy(_) => true
            case _ => false
        }
    }

    /**
     * `ty` if it is of a type of the language: what one side of an operator tells the other, as an
     * operator of another type takes what it declares (`"x" * n`).
     */
    private func primOnly(ty: ?Ty): ?Ty {
        ty.filter {one => isPrim(one)}
    }

    /**
     * What the right of `op` is expected of, its left of the type `left`: the same, but for a shift
     * and for an integer's power, of `UInt64`.
     */
    private func rightExpected(op: String, left: Ty): ?Ty {
        match (left.kind(db)) {
            case PrimTy(name) where op == "**" && INTEGER_TYPES.contains(name) => prim("UInt64")
            case _ where op == "**" || op == "<<" || op == ">>" => None
            case _ => left
        }
    }

    private func rangeTy(start: ?ExprId, end: ?ExprId, step: ?ExprId, expected: ?Ty): Ty {
        let wanted: ?Ty = match (expected.map {one => one.kind(db)}) {
            case Some(DeclTy(id, args)) where args.size == 1 && Some(id) == langId(LangItem.RangeStruct) => args[0]
            case _ => None
        }
        var element: ?Ty = None
        match ((start, end)) {
            case (Some(s), Some(e)) where isNumericLiteral(s) && !isNumericLiteral(e) =>
                let endTy = infer(e, wanted)
                infer(s, endTy)
                element = endTy
            case _ =>
                let startTy = start.map {one => infer(one, wanted)}
                let endTy = end.map {one => infer(one, startTy ?? wanted)}
                element = startTy ?? endTy
        }
        if (let Some(one) <- step) {
            infer(one, prim("Int64"))
        }
        langTy(LangItem.RangeStruct, [element ?? error])
    }

    /**
     * An array: its elements checked against the element type of the `Array` expected, else of their
     * join (N98).
     */
    private func arrayTy(elements: Array<ExprId>, expected: ?Ty): Ty {
        let wanted: ?Ty = match (expected.map {one => unboxed(one).kind(db)}) {
            case Some(DeclTy(id, args)) where args.size == 1 && Some(id) == langId(LangItem.ArrayStruct) => args[0]
            case _ => None
        }
        let element = match (wanted) {
            case Some(one) =>
                for (e in elements) {
                    infer(e, one)
                }
                one
            // cjc: an empty array's element type is to be told
            case None where elements.isEmpty() => failed(listOf(expected))
            case None => joinTys(db, elements.map {e => infer(e, None)}, from)
        }
        langTy(LangItem.ArrayStruct, [element])
    }

    /**
     * `a[i]`: an element of a tuple by a literal, of a `VArray` by an `Int64`; of anything else, a
     * call of its operator `[]` with the indices (N122).
     */
    private func indexTy(id: ExprId, base: ExprId, indices: Array<ExprId>, expected: ?Ty): Ty {
        let baseTy = infer(base, None)
        match (baseTy.kind(db)) {
            case TupleTy(elements) =>
                for (index in indices) {
                    infer(index, None)
                }
                // cjc: tuple index must be an integer literal
                match (indices.get(0).map {one => hir[one]}) {
                    case Some(LitExpr(text)) where indices.size == 1 => match (integerOf(text)) {
                        case Some(n) => elements.get(n) ?? error
                        case None => error
                    }
                    case _ => error
                }
            case VArrayTy(element, _) =>
                for (index in indices) {
                    infer(index, prim("Int64"))
                }
                element
            case _ => operatorTy(id, baseTy, "[]", indices.map {one => CallArg(None, one)}, expected)
        }
    }

    /**
     * Whether `a[i]` of a value of the type `ty` is the language's: of a tuple or a `VArray`.
     */
    private func isIndexedByLanguage(ty: Ty): Bool {
        match (ty.kind(db)) {
            case TupleTy(_) | VArrayTy(_, _) => true
            case _ => false
        }
    }

    /**
     * Binds the pattern `pat` to a value of the type `ty`: its names locals of the types their parts
     * are (N105).
     */
    private func bindPat(pat: PatId, ty: Ty): Unit {
        setPat(pat, ty)
        match (hir[pat]) {
            case BindPat(local) =>
                let one = hir[local]
                if (!one.lone || !isCtorName(one.name)) {
                    setLocal(local, ty)
                }
            case TypePat(local, written) =>
                let typed = typeAt(written)
                if (let Some(one) <- local) {
                    setLocal(one, typed)
                }
            case TuplePat(elements) =>
                let tys = match (ty.kind(db)) {
                    case TupleTy(all) where all.size == elements.size => all
                    case _ => Array<Ty>()
                }
                for (i in 0..elements.size) {
                    bindPat(elements[i], tys.get(i) ?? failed([ty]))
                }
            case EnumPat(path, args) =>
                let params = ctorParamsOf(path, ty)
                for (i in 0..args.size) {
                    bindPat(args[i], params.get(i) ?? failed([ty]))
                }
            case _ => ()
        }
    }

    private func isCtorName(name: String): Bool {
        match (pkg) {
            case Some(one) => !ctorsNamed(db, one, name).isEmpty()
            case None => false
        }
    }

    /**
     * The types of the parameters of the constructor `path` names in a pattern of the enum type `ty`,
     * its arguments substituted.
     */
    private func ctorParamsOf(path: Array<String>, ty: Ty): Array<Ty> {
        let name = path.get(path.size - 1) ?? return []
        if (let DeclTy(id, args) <- ty.kind(db) && id.item(db).kind == ItemKind.Enum) {
            for (ctor in ctorsOf(id) where isNamed(db, ctor, name)) {
                return signatureTypes(db, ctor).params.map {one => substitute(db, one, id, args)}
            }
        }
        []
    }

    /**
     * The constructors of the enum `id`.
     */
    private func ctorsOf(id: DefId): Array<DefId> {
        let item = declItemOf(db, id) ?? return []
        let file = id.file(db)
        item.members.filter {member => member.kind == ItemKind.EnumCtor}.map {member => DefId(db, file, member.id)}
    }

    /**
     * The type a name of the body is, used as a value.
     */
    private func pathTy(id: ExprId, name: String, args: Array<TypeRefId>, expected: ?Ty): Ty {
        let explicit = args.map {one => typeAt(one)}
        match (resolveName(id, name)) {
            case Values(targets) where targets.size == 1 => match (targets[0]) {
                case LocalOf(local) => locals[local.index]
                case MemberOf(target) => memberValueTy(target, thisTy())
                case DeclOf(decl) => declValueTy(decl, explicit, expected)
                case TypeParamOf(_) => error
            }
            case InFile(Found(ids)) where ids.size == 1 => declValueTy(ids[0], explicit, expected)
            // cjc: several constructors, none of the enum expected
            case InFile(Ctors(own, all)) => match (chooseCtor(own, all, expected)) {
                case Some(ctor) => declValueTy(ctor, explicit, expected)
                case None => failed(listOf(expected))
            }
            // functions overloading one another, as a value: the one of the parameters expected
            case Values(_) | InFile(Found(_)) => match (expected.map {one => one.kind(db)}) {
                case Some(FuncTy(params, _, _)) => overloadOfParams(id, callablesOf(id, expected), params)
                case _ => failed(listOf(expected))
            }
            case InFile(NotFound) => notFound()
            // ambiguous: cjc reports it
            case _ => error
        }
    }

    /**
     * The function type of the one of `callables`, overloads named at `id` as a value, that takes
     * what a function of the parameters `params` is passed (cjc's `CollectValidFuncTys`, N121); an
     * error if none does or several.
     */
    private func overloadOfParams(id: ExprId, callables: Array<Callable>, params: Array<Ty>): Ty {
        let fit = callables.filter {
            one => one.open.isNone() && one.params.size == params.size &&
                (0..params.size).iterator().all {i => isSubtype(db, params[i], one.params[i], from)}
        }
        if (fit.size != 1) {
            return error
        }
        if (let Some(decl) <- fit[0].decl) {
            setCallee(id, decl)
        }
        fit[0].ty(db)
    }

    /**
     * The constructor among `own` and `all` a name means: the one of the enum expected, else the one
     * of the package (N46).
     */
    private func chooseCtor(own: Array<DefId>, all: Array<DefId>, expected: ?Ty): ?DefId {
        if (let Some(one) <- expected && let DeclTy(id, _) <- one.kind(db)) {
            let ofExpected = all.filter {ctor => parentOf(db, ctor) == Some(id)}
            if (ofExpected.size == 1) {
                return ofExpected[0]
            }
        }
        let candidates = if (own.isEmpty()) {
            all
        } else {
            own
        }
        if (candidates.size == 1) {
            candidates[0]
        } else {
            None
        }
    }

    /**
     * The type of the declaration `id` used as a value: a function's function type, a variable's
     * type, a constructor's, its enum's; none of a type.
     */
    private func declValueTy(id: DefId, explicit: Array<Ty>, expected: ?Ty): Ty {
        match (id.item(db).kind) {
            case Func => funcCallable(id, explicit, None).ty(db)
            case Var | Prop => valueOf(id)
            case EnumCtor =>
                let callable = ctorCallable(id, explicit, None, expected) ?? return error
                if (callable.params.isEmpty()) {
                    callable.erased(db, callable.ret)
                } else {
                    callable.ty(db)
                }
            case _ => error
        }
    }

    /**
     * What the declaration `id` returns, or a variable's type: as written, else inferred (N100); an
     * error for the declaration whose body this is, which it is inferring.
     */
    private func valueOf(id: DefId): Ty {
        if (let Some(ty) <- signatureTypes(db, id).ty) {
            return ty
        }
        if (id == def) {
            return error
        }
        declaredTyOf(db, id)
    }

    /**
     * The type of the member `target` used as a value, as a member of a value of the type `recv`.
     */
    private func memberValueTy(target: MemberTarget, recv: Ty): Ty {
        match (target) {
            case MemberDecl(id) => match (id.item(db).kind) {
                case Func =>
                    let callables = memberCallables(target, recv, [], None)
                    if (callables.size == 1) {
                        callables[0].ty(db)
                    } else {
                        error
                    }
                case EnumCtor => declValueTy(id, [], recv)
                case _ => asMemberOf(db, valueOf(id), id, recv, from) ?? error
            }
            case MemberParam(ctor, local) =>
                let params = body(db, ctor).params
                for (i in 0..params.size where params[i].local == Some(local)) {
                    let ty = signatureTypes(db, ctor).params.get(i) ?? return error
                    return asMemberOf(db, ty, ctor, recv, from) ?? error
                }
                error
        }
    }

    /**
     * The function `id`, its own type arguments `explicit` if given, else open, the call's to infer
     * (8c); seen on `recv` if it is a member called on one.
     */
    private func funcCallable(id: DefId, explicit: Array<Ty>, recv: ?Ty): Callable {
        let generics = signatureTypes(db, id).generics.size
        let isWritten = generics > 0 && explicit.size == generics
        let own = {
            ty: Ty => if (isWritten) {
                substitute(db, ty, id, explicit)
            } else {
                ty
            }
        }
        let seen = {
            ty: Ty => match (recv) {
                case Some(one) => asMemberOf(db, own(ty), id, one, from) ?? error
                case None => own(ty)
            }
        }
        let open: ?DefId = if (generics > 0 && !isWritten) {
            id
        } else {
            None
        }
        let sig = signatureTypes(db, id)
        Callable(sig.params.map {one => seen(one)}, seen(valueOf(id)), open: open, decl: id, names: sig.paramNames)
    }

    /**
     * The enum constructor `id`, its enum's type arguments `explicit`, else those of `recv` or of
     * `expected` if of its enum, else open, the call's to infer (8c).
     */
    private func ctorCallable(id: DefId, explicit: Array<Ty>, recv: ?Ty, expected: ?Ty): ?Callable {
        let parent = parentOf(db, id) ?? return None
        let (args, open) = openTypeArgsOf(parent, explicit, recv ?? expected)
        Callable(signatureTypes(db, id).params.map {one => substitute(db, one, parent, args)},
            Ty(db, DeclTy(parent, args)), open: open, decl: id)
    }

    /**
     * The type arguments of the type `id`: `explicit`, else those of `wanted` if it is of `id`, else
     * unknown.
     */
    private func typeArgsOf(id: DefId, explicit: Array<Ty>, wanted: ?Ty): Array<Ty> {
        knownTypeArgsOf(id, explicit, wanted) ?? Array(genericsOf(db, id).size) {_ => error}
    }

    /**
     * The type arguments of the type `id` called: as `typeArgsOf`, else its type parameters, open
     * for the call to infer (8c), and `id`.
     */
    private func openTypeArgsOf(id: DefId, explicit: Array<Ty>, wanted: ?Ty): (Array<Ty>, ?DefId) {
        if (let Some(args) <- knownTypeArgsOf(id, explicit, wanted)) {
            return (args, None)
        }
        (Array(genericsOf(db, id).size) {i => Ty(db, ParamTy(id, i))}, id)
    }

    private func knownTypeArgsOf(id: DefId, explicit: Array<Ty>, wanted: ?Ty): ?Array<Ty> {
        let count = genericsOf(db, id).size
        if (explicit.size == count) {
            return explicit
        }
        if (let Some(one) <- wanted && let DeclTy(other, args) <- one.kind(db) && other == id && args.size == count) {
            return args
        }
        None
    }

    /**
     * The constructors of the type `id` applied to `args`, the type parameters of `open` among them
     * the call's to infer; of one that declares none, the one of no parameters.
     */
    private func initCallables(id: DefId, args: Array<Ty>, open!: ?DefId = None): Array<Callable> {
        let item = declItemOf(db, id) ?? return []
        let file = id.file(db)
        let self = Ty(db, DeclTy(id, args))
        let inits = item.members.filter {member => member.kind == ItemKind.Init || member.kind == ItemKind.PrimaryInit}
        if (inits.isEmpty()) {
            return [Callable([], self, open: open)]
        }
        inits.map {
            member =>
            let one = DefId(db, file, member.id)
            Callable(signatureTypes(db, one).params.map {ty => substitute(db, ty, id, args)}, self, open: open,
                decl: one)
        }
    }

    /**
     * What a value of the type `ty` calls.
     */
    private func valueCallables(ty: Ty): Array<Callable> {
        match (ty.kind(db)) {
            case FuncTy(params, ret, _) => [Callable(params, ret)]
            case ErrorTy | TodoTy(_) => []
            // of another type, its `operator func ()` (N130): what is called is the value, not
            // the operator a name of it goes to
            case _ => operatorCallables(ty, "()").map {
                one => Callable(one.params, one.ret, open: one.open, names: one.names)
            }
        }
    }

    /**
     * What the declaration `id` called means: a function, the constructors of a type, an enum
     * constructor, a variable of a function type.
     */
    private func declCallables(id: DefId, explicit: Array<Ty>, expected: ?Ty): Array<Callable> {
        match (id.item(db).kind) {
            case Func => [funcCallable(id, explicit, None)]
            case Class | Struct =>
                let (args, open) = openTypeArgsOf(id, explicit, expected)
                initCallables(id, args, open: open)
            case EnumCtor => match (ctorCallable(id, explicit, None, expected)) {
                case Some(one) => [one]
                case None => []
            }
            case TypeAlias => match (typeOfDecl(id, explicit, expected).kind(db)) {
                case DeclTy(target, args) => initCallables(target, args)
                case _ => []
            }
            case Var | Prop => valueCallables(valueOf(id))
            case _ => []
        }
    }

    /**
     * What the member `target` called on a value or a type of the type `recv` means.
     */
    private func memberCallables(target: MemberTarget, recv: Ty, explicit: Array<Ty>, expected: ?Ty): Array<Callable> {
        match (target) {
            case MemberDecl(id) => match (id.item(db).kind) {
                case Func => [funcCallable(id, explicit, recv)]
                case EnumCtor => match (ctorCallable(id, explicit, recv, expected)) {
                    case Some(one) => [one]
                    case None => []
                }
                case _ => valueCallables(memberValueTy(target, recv))
            }
            case MemberParam(_, _) => valueCallables(memberValueTy(target, recv))
        }
    }

    /**
     * A call: what its callee means, the one of as many parameters as it has arguments if it means
     * several, and of those the one `chooseOverload` takes; its arguments checked against that
     * one's parameters in order, a named one inferred alone.
     */
    private func callTy(callee: ExprId, args: Array<CallArg>, expected: ?Ty): Ty {
        let all = overriding(callablesOf(callee, expected))
        let fitting = if (all.size > 1) {
            all.filter {one => one.params.size == args.size}
        } else {
            all
        }
        let chosen = if (fitting.size > 1) {
            chooseOverload(callee, fitting, args, expected)
        } else {
            fitting.get(0)
        }
        match (chosen) {
            case Some(callable) =>
                // a type's name called goes to the type, not to the constructor taken
                if (all.size > 1 && let Some(decl) <- callable.decl && decl.item(db).kind != ItemKind.Init &&
                    decl.item(db).kind != ItemKind.PrimaryInit) {
                    setCallee(callee, decl)
                }
                callWith(callee, callable, args, expected)
            case None =>
                // candidates of which none fits, or no one most specific, fail a candidate around
                // (cjc's "no matching function", "ambiguous match")
                if (!all.isEmpty()) {
                    mismatches++
                }
                let argTys = args.map {arg => infer(arg.expr, None)}
                // an argument not known fits any candidate: of several, none is taken for it; arguments
                // by name, of default values or variadic are matched by their count alone yet (#254); a
                // macro whose expansion is not read may declare the one that fits
                let byMatching = fitting.isEmpty() || args.iterator().any {arg => arg.name.isSome()} ||
                    all.iterator().any {one => one.names.iterator().any {name => name.isSome()}}
                let failure = if (all.isEmpty()) {
                    calleeFailure(callee)
                } else if (let Some(unknown) <- unknownOf(db, argTys.concat(listOf(expected)))) {
                    unknown
                } else if (byMatching) {
                    todo(Todo.ArgMatching)
                } else {
                    macroFailure(callee)
                }
                match (hir[callee]) {
                    case PathExpr(_, _) | FieldExpr(_, _, _) | LangExpr(_) => setExpr(callee, failure)
                    case _ => ()
                }
                failure
        }
    }

    /**
     * What a call of `callee` that means nothing to call is: of a name of nothing, of a member not
     * found, of a value not known, that one; else an error, a value no function (cjc: "cannot be
     * called").
     */
    private func calleeFailure(callee: ExprId): Ty {
        match (hir[callee]) {
            case PathExpr(name, args) =>
                let ty = pathTy(callee, name, args, None)
                if (isUnknown(db, ty)) {
                    ty
                } else {
                    // a value no function: a macro may have made one of its name
                    macroFailure(callee)
                }
            case FieldExpr(receiver, _, _) => match (resolveAccess(callee)) {
                case OfValue =>
                    let recv = tyOf(receiver)
                    if (isUnknown(db, recv) || !fields.contains(callee.index)) {
                        memberNotFound(recv)
                    } else {
                        // a member no function: a macro may have made it one (`@CalcaInput`'s fields)
                        macroFailure(callee)
                    }
                case NoField => noField(receiver)
                case _ => error
            }
            case LangExpr(_) => todo(Todo.NoStd)
            case _ => failed([tyOf(callee)])
        }
    }


    /**
     * The one of `candidates`, each of as many parameters as `args`, a call takes, as cjc's
     * `MatchFunctionForCall`: level by level from the nearest (N117), each candidate tried; the first
     * level where any fits deciding (N115); of several there, the most specific (N119). `None` if
     * none fits, or no one of those is most specific, or they are enum constructors (N120).
     */
    private func chooseOverload(callee: ExprId, candidates: Array<Callable>, args: Array<CallArg>,
        expected: ?Ty): ?Callable {
        let own = args.filter {arg => isSelfTyped(arg.expr) && !known.contains(arg.expr.index)}
        for (arg in own) {
            known[arg.expr.index] = infer(arg.expr, None)
        }
        let chosen = mostSpecificFitting(callee, candidates, args, expected)
        for (arg in own) {
            known.remove(arg.expr.index)
        }
        chosen
    }

    private func mostSpecificFitting(callee: ExprId, candidates: Array<Callable>, args: Array<CallArg>,
        expected: ?Ty): ?Callable {
        let levels = candidates.map {one => one.level}
        sort(levels)
        var last: ?Int64 = None
        for (level in levels where last != Some(level)) {
            last = level
            let fit = candidates.filter {one => one.level == level && fitsCall(callee, one, args, expected)}
            if (fit.size == 1) {
                return fit[0]
            }
            if (fit.size > 1) {
                if (fit.iterator().any {one => one.decl.map {id => id.item(db).kind} == Some(ItemKind.EnumCtor)}) {
                    return None
                }
                // those no other is more specific than, and not the other way too: two as specific as
                // each other (`g(Int8)`, `g(Int16)`) both stay, and the call is ambiguous, as in cjc
                let best = Array(fit.size) {i => i}.filter {
                    i => (0..fit.size).iterator().all {
                        j => i == j || !isMoreSpecific(fit[j], fit[i]) || isMoreSpecific(fit[i], fit[j])
                    }
                }
                return if (best.size == 1) {
                    fit[best[0]]
                } else {
                    None
                }
            }
        }
        None
    }

    /**
     * Whether `id` is of one type whatever is expected of it: a local, a variable or property, a
     * member of a value, a string, `this`. A candidate tried compares it, inferring it once.
     */
    private func isSelfTyped(id: ExprId): Bool {
        let isValue = {decl: DefId => decl.item(db).kind == ItemKind.Var || decl.item(db).kind == ItemKind.Prop}
        match (hir[id]) {
            case LitExpr(text) => !isNumber(text)
            case StrExpr(_) | ThisExpr => true
            case PathExpr(name, _) => match (resolveName(id, name)) {
                case Values(targets) where targets.size == 1 => match (targets[0]) {
                    case LocalOf(_) => true
                    case DeclOf(decl) => isValue(decl)
                    case MemberOf(MemberDecl(decl)) => isValue(decl)
                    case MemberOf(MemberParam(_, _)) => true
                    case TypeParamOf(_) => false
                }
                case InFile(Found(ids)) where ids.size == 1 => isValue(ids[0])
                case _ => false
            }
            // of a value, a member is looked up from its type alone
            case FieldExpr(receiver, _, _) => match (resolveAccess(id)) {
                case OfValue => isSelfTyped(receiver)
                case _ => false
            }
            case _ => false
        }
    }

    /**
     * Checks the argument `expr` against `expected`; while a candidate is tried, one known before
     * is compared, not inferred again.
     */
    private func checkArg(expr: ExprId, expected: ?Ty): Ty {
        if (trying > 0 && let Some(ty) <- known.get(expr.index)) {
            if (let Some(one) <- expected && !fits(ty, one)) {
                mismatches++
            }
            return ty
        }
        infer(expr, expected)
    }

    /**
     * Whether a call of `callable` fits (N115): its arguments checked against its parameters, its
     * type arguments not written solved, its return type one `expected` takes; what that writes
     * undone, as cjc tries a candidate with its diagnostics suppressed and its constraints reset.
     */
    private func fitsCall(callee: ExprId, callable: Callable, args: Array<CallArg>, expected: ?Ty): Bool {
        let mark = undo.size
        let before = mismatches
        let vars = nextVar
        trying++
        let ret = callWith(callee, callable, args, expected)
        trying--
        let fit = mismatches == before && match (expected) {
            case Some(one) => fits(ret, one)
            case None => true
        }
        rollBack(mark)
        mismatches = before
        nextVar = vars
        fit
    }

    /**
     * Whether `one` is as specific as `other`, of as many parameters (cjc's `CompareFuncCandidates`,
     * N119): each of its parameters a subtype of `other`'s, but of two numbers `Int64` first among
     * the integers, any integer before a float, `Float64` first among the floats; for `other`
     * generic, its type arguments inferred from `one`'s parameters passed to it.
     */
    private func isMoreSpecific(one: Callable, other: Callable): Bool {
        for (i in 0..one.params.size) {
            if (let Some(order) <- numberOrder(one.params[i], other.params[i]) && order > 0) {
                return false
            }
        }
        let theirs = match (other.open) {
            case Some(owner) =>
                let count = genericsOf(db, owner).size
                let vars = Array(count) {i => Ty(db, InferTy(nextVar + i))}
                let open = other.params.map {ty => substitute(db, ty, owner, vars)}
                let solver = TypeArgSolver(db, nextVar, count, from, option)
                solver.boundedBy(owner, vars)
                for (i in 0..one.params.size) {
                    solver.constrain(one.params[i], open[i])
                }
                let solved = solver.solve()
                if (solved.iterator().any {ty => ty.isNone()}) {
                    return false
                }
                open.map {ty => replaceVars(db, ty, nextVar, solved)}
            case None => other.params
        }
        (0..one.params.size).iterator().all {
            i => numberOrder(one.params[i], theirs[i]).isSome() || isSubtype(db, one.params[i], theirs[i], from)
        }
    }

    /**
     * Of two types of numbers, how `a` comes before `b` (cjc's `CompareIntAndFloat`): below zero
     * first, zero alike; `None` if either is no number.
     */
    private func numberOrder(a: Ty, b: Ty): ?Int64 {
        let (left, right) = match ((a.kind(db), b.kind(db))) {
            case (PrimTy(x), PrimTy(y)) => (x, y)
            case _ => return None
        }
        let (l, r) = (numberRank(left), numberRank(right))
        if (l < 0 || r < 0) {
            return None
        }
        // two integers but `Int64`, or two floats but `Float64`, are alike
        if (left == right || l == r) {
            return 0
        }
        l - r
    }

    /**
     * A call of `callable`, of the parameters and return type it says, or whose type arguments are
     * inferred if it has them open.
     */
    private func callWith(callee: ExprId, callable: Callable, args: Array<CallArg>, expected: ?Ty): Ty {
        if (let Some(owner) <- callable.open) {
            return genericCallTy(callee, callable, owner, args, expected)
        }
        setExpr(callee, callable.ty(db))
        var positional = 0
        for (arg in args) {
            if (arg.name.isSome()) {
                infer(arg.expr, None)
            } else {
                checkArg(arg.expr, callable.params.get(positional))
                positional++
            }
        }
        callable.ret
    }

    /**
     * A call of `callable` whose type arguments, those of `owner`, are not written: inferred from
     * the arguments and `expected`, as cjc's `PrepareTyArgsSynthesis` does (D57). Each argument is
     * checked against its parameter if that names no type argument, else synthesized alone and its
     * type a lower bound of the parameter; a literal of no suffix leaves its type to the solution, a
     * lambda of a parameter not written, or an argument of no type alone (`none()`), wait. Solved as
     * far as they tell, those that wait are checked against their parameters as far as solved, the
     * unknown an error type, which bounds again; until a round solves nothing new. Then each that
     * waited, and each literal, is checked against its parameter solved.
     */
    private func genericCallTy(callee: ExprId, callable: Callable, owner: DefId, args: Array<CallArg>,
        expected: ?Ty): Ty {
        let base = nextVar
        let count = genericsOf(db, owner).size
        nextVar += count
        let vars = Array(count) {i => Ty(db, InferTy(base + i))}
        let open = {ty: Ty => substitute(db, ty, owner, vars)}
        let params = callable.params.map(open)
        let ret = open(callable.ret)
        // the parameter of each argument, a named one none: it is inferred alone
        let targets = Array<?Ty>(args.size, repeat: None)
        var positional = 0
        for (i in 0..args.size where args[i].name.isNone()) {
            targets[i] = params.get(positional)
            positional++
        }
        let synthesized = Array<?Ty>(args.size, repeat: None)
        let ideal = Array<?Bool>(args.size, repeat: None)
        let waiting = ArrayList<Int64>()
        for (i in 0..args.size) {
            let expr = args[i].expr
            match (targets[i]) {
                case Some(target) where hasInferVars(db, target) =>
                    if (let Some(isFloat) <- idealLiteral(expr)) {
                        ideal[i] = isFloat
                    } else if (isUntypedLambda(expr)) {
                        waiting.add(i)
                    } else {
                        let ty = checkArg(expr, None)
                        if (hasUnknowns(db, ty)) {
                            waiting.add(i)
                        } else {
                            synthesized[i] = ty
                        }
                    }
                case Some(target) => checkArg(expr, target)
                case None => checkArg(expr, None)
            }
        }
        let solve = {
            =>
            let solver = TypeArgSolver(db, base, count, from, option)
            solver.boundedBy(owner, vars)
            for (i in 0..args.size) {
                let target = targets[i] ?? continue
                if (let Some(ty) <- synthesized[i]) {
                    solver.constrain(ty, target)
                }
                if (let Some(isFloat) <- ideal[i]) {
                    solver.literal(isFloat, target)
                }
            }
            if (let Some(one) <- expected && hasInferVars(db, ret)) {
                solver.constrain(ret, one)
            }
            solver.solve()
        }
        var solved = solve()
        var unsolved = solved.iterator().filter {one => one.isNone()}.count()
        while (unsolved > 0 && !waiting.isEmpty()) {
            for (i in waiting.toArray()) {
                let target = replaceVars(db, targets[i].getOrThrow(), base, solved)
                if (!isKnownEnough(target)) {
                    continue
                }
                let ty = infer(args[i].expr, target)
                if (isUntypedLambda(args[i].expr) || !hasUnknowns(db, ty)) {
                    synthesized[i] = ty
                    waiting.removeIf {one => one == i}
                }
            }
            let next = solve()
            let left = next.iterator().filter {one => one.isNone()}.count()
            if (left >= unsolved) {
                break
            }
            solved = next
            unsolved = left
        }
        let solution = solved
        // a type argument not solved for an argument not known is not known as it is, else an error
        // (cjc: "can not infer")
        let inferred = args |> filterMap {arg: CallArg => inferredTyOf(arg.expr)} |> collectArray
        // an argument by name puts those after it out of place yet (#254)
        let unsolvedTy = match (unknownOf(db, inferred.concat(listOf(expected)))) {
            case Some(unknown) => unknown
            case None where args.iterator().any {arg => arg.name.isSome()} => todo(Todo.ArgMatching)
            case None => error
        }
        let final = {ty: Ty => replaceVars(db, ty, base, solution, unsolved: unsolvedTy)}
        // a call not solved fits not, nor what synthesized a type its parameter solved takes not (8d)
        if (unsolved > 0) {
            mismatches++
        }
        for (i in 0..args.size) {
            let target = targets[i] ?? continue
            if (ideal[i].isSome() || waiting.contains(i) || isUntypedLambda(args[i].expr)) {
                infer(args[i].expr, final(target))
            } else if (let Some(ty) <- synthesized[i] && !fits(ty, final(target))) {
                mismatches++
            }
        }
        nextVar = base
        setExpr(callee, Ty(db, FuncTy(params.map(final), final(ret), false)))
        final(ret)
    }

    /**
     * Whether a parameter's type, solved as far as it is, tells an argument that waits anything:
     * a function type's parameters all known, any other type not unknown as a whole (cjc's
     * `UnsolvedAsQuest`).
     */
    private func isKnownEnough(target: Ty): Bool {
        match (target.kind(db)) {
            case FuncTy(params, _, _) => params.iterator().all {one => !hasUnknowns(db, one)}
            case ErrorTy | TodoTy(_) => false
            case _ => true
        }
    }

    /**
     * For a number of no suffix, cjc's ideal type, whether it is a float.
     */
    private func idealLiteral(id: ExprId): ?Bool {
        match (hir[id]) {
            case LitExpr(text) where isNumber(text) =>
                let lower = text.replace("_", "").toAsciiLower()
                let isHex = lower.startsWith("0x")
                if (suffixOf(lower, isHex).isSome()) {
                    return None
                }
                Some(if (isHex) {
                    lower.contains("p") || lower.contains(".")
                } else {
                    lower.contains(".") || lower.contains("e")
                })
            case UnaryExpr("-", inner) => idealLiteral(inner)
            case _ => None
        }
    }

    /**
     * Whether `id` is a lambda of a parameter whose type it does not write.
     */
    private func isUntypedLambda(id: ExprId): Bool {
        match (hir[id]) {
            case LambdaExpr(params, _) => params.iterator().any {one => one.ty.isNone()}
            case _ => false
        }
    }

    /**
     * `callables`, the nearest first, but those whose parameters a nearer one has: a member that
     * overrides or implements another hides it (N107).
     */
    private func overriding(callables: Array<Callable>): Array<Callable> {
        let kept = ArrayList<Callable>()
        for (one in callables where kept.iterator().all {other => other.erasedParams(db) != one.erasedParams(db)}) {
            kept.add(one)
        }
        kept.toArray()
    }

    /**
     * The level of the local function `local` called at `callee`: how many scopes out from the
     * call its own is (N117).
     */
    private func localLevel(callee: ExprId, local: LocalId): Int64 {
        var level = 0
        for (one in scopes.chain(scopes.scopeOf(callee))) {
            if (scopes[one].entries.contains(local)) {
                return level
            }
            level++
        }
        level
    }

    /**
     * The level of the declaration `id` of the file's scope: the package's before one imported
     * (N117).
     */
    private func fileLevel(id: DefId): Int64 {
        if (pkg.isSome() && packageOf(db, id) == pkg) {
            MEMBER_LEVEL + 1
        } else {
            MEMBER_LEVEL + 2
        }
    }

    /**
     * What the callee `callee` may call.
     */
    private func callablesOf(callee: ExprId, expected: ?Ty): Array<Callable> {
        match (hir[callee]) {
            case PathExpr(name, args) =>
                let explicit = args.map {one => typeAt(one)}
                match (resolveName(callee, name)) {
                    case Values(targets) =>
                        let found = ArrayList<Callable>()
                        for (target in targets) {
                            match (target) {
                                case LocalOf(local) =>
                                    let level = localLevel(callee, local)
                                    found.add(all: valueCallables(locals[local.index]).map {one => one.at(level)})
                                case MemberOf(member) => found.add(all: memberCallables(member, thisTy(), explicit,
                                    expected).map {one => one.at(MEMBER_LEVEL)})
                                case DeclOf(id) => found.add(all: declCallables(id, explicit, expected).map {
                                    one => one.at(fileLevel(id))
                                })
                                case TypeParamOf(_) => ()
                            }
                        }
                        found.toArray()
                    case InFile(Found(ids)) =>
                        let found = ArrayList<Callable>()
                        for (id in ids) {
                            found.add(all: declCallables(id, explicit, expected).map {one => one.at(fileLevel(id))})
                        }
                        found.toArray()
                    case InFile(Ctors(own, all)) => match (chooseCtor(own, all, expected)) {
                        case Some(ctor) => declCallables(ctor, explicit, expected)
                        case None => []
                    }
                    case _ => []
                }
            case FieldExpr(receiver, name, args) => fieldCallables(callee, receiver, name, args, expected)
            case LangExpr(item) => match (langId(item)) {
                case Some(decl) => declCallables(decl, [], expected)
                case None => []
            }
            // `super(…)` and `this(…)` in a constructor
            case SuperExpr | ThisExpr => match (infer(callee, None).kind(db)) {
                case DeclTy(id, args) => initCallables(id, args).map {
                    one => Callable(one.params, prim("Unit"), decl: one.decl)
                }
                case _ => []
            }
            case _ => valueCallables(infer(callee, None))
        }
    }

    /**
     * What `expr`, a `FieldExpr` whose name is `name`, called means.
     */
    private func fieldCallables(expr: ExprId, receiver: ExprId, name: String, args: Array<TypeRefId>,
        expected: ?Ty): Array<Callable> {
        let explicit = args.map {one => typeAt(one)}
        let found = ArrayList<Callable>()
        match (resolveAccess(expr)) {
            case PackageMembers(ids) =>
                noValue(receiver)
                for (id in ids) {
                    found.add(all: declCallables(id, explicit, expected))
                }
            case TypeMembers(targets) =>
                noValue(receiver)
                let recv = typeOfReceiver(receiver, expected)
                for (target in targets) {
                    found.add(all: memberCallables(target, recv, explicit, expected))
                }
            case OfValue =>
                let (targets, recv) = valueMembers(expr, infer(receiver, None), name)
                for (target in targets) {
                    found.add(all: memberCallables(target, recv, explicit, expected))
                }
            case NoField => ()
        }
        found.toArray()
    }

    /**
     * The type `expr`, a `FieldExpr`, is of, used as a value.
     */
    private func fieldTy(expr: ExprId, receiver: ExprId, name: String, args: Array<TypeRefId>, expected: ?Ty): Ty {
        let explicit = args.map {one => typeAt(one)}
        match (resolveAccess(expr)) {
            case PackageMembers(ids) =>
                noValue(receiver)
                if (ids.size == 1) {
                    declValueTy(ids[0], explicit, expected)
                } else {
                    failed(listOf(expected))
                }
            case TypeMembers(targets) =>
                noValue(receiver)
                if (targets.size == 1) {
                    memberValueTy(targets[0], typeOfReceiver(receiver, expected))
                } else {
                    failed(listOf(expected))
                }
            case OfValue =>
                let recvTy = infer(receiver, None)
                let (targets, recv) = valueMembers(expr, recvTy, name)
                if (targets.size == 1) {
                    memberValueTy(targets[0], recv)
                } else if (targets.isEmpty()) {
                    memberNotFound(recvTy)
                } else {
                    // overloads as a value, the expected type telling none
                    failed(listOf(expected))
                }
            case NoField => noField(receiver)
        }
    }

    /**
     * The members named `name` of a value of the type `ty`, recorded for `expr`, and the type they
     * are seen on: `ty`, or the bound of a type parameter that has them; but those of an `extend`
     * `ty` is no instance of (N86).
     */
    private func valueMembers(expr: ExprId, ty: Ty, name: String): (Array<MemberTarget>, Ty) {
        for (head in headsOf(ty)) {
            let start = match (head.kind(db)) {
                case DeclTy(id, _) => ExtendedType.DeclType(id)
                case PrimTy(prim) => ExtendedType.PrimType(prim)
                case _ => continue
            }
            let targets = notOverridden(memberLookup(db, [start], name, from: from).filter {
                target => isMemberOf(target, head)
            }, head)
            if (!targets.isEmpty()) {
                setField(expr, FieldTargets(expr, targets))
                return (targets, head)
            }
        }
        (Array<MemberTarget>(), ty)
    }

    /**
     * `targets`, the nearest first, but the functions whose parameters, seen on `recv`, a nearer one
     * has: those it overrides or implements (N107).
     */
    private func notOverridden(targets: Array<MemberTarget>, recv: Ty): Array<MemberTarget> {
        let kept = ArrayList<MemberTarget>()
        let params = ArrayList<Array<Ty>>()
        for (target in targets) {
            if (let MemberDecl(id) <- target && id.item(db).kind == ItemKind.Func) {
                let own = funcCallable(id, [], recv).erasedParams(db)
                if (params.iterator().any {one => one == own}) {
                    continue
                }
                params.add(own)
            }
            kept.add(target)
        }
        kept.toArray()
    }

    /**
     * The types whose members a value of the type `ty` has: itself, or a type parameter's bounds.
     */
    private func headsOf(ty: Ty): Array<Ty> {
        match (ty.kind(db)) {
            case ParamTy(owner, _) =>
                let found = ArrayList<Ty>()
                for (bound in signatureTypes(db, owner).bounds where bound.ty == ty) {
                    found.add(all: bound.bounds)
                }
                found.toArray()
            case _ => [ty]
        }
    }

    /**
     * Whether `target` is a member of a value of the type `recv`: not one of an `extend` of another
     * instance of its type (N86).
     */
    private func isMemberOf(target: MemberTarget, recv: Ty): Bool {
        match (target) {
            case MemberDecl(id) => match (parentOf(db, id)) {
                case Some(owner) where owner.item(db).kind == ItemKind.Extend => ownerArgs(db, owner, recv, from).isSome()
                case _ => true
            }
            case MemberParam(_, _) => true
        }
    }

    /**
     * The type `receiver`, the left of a `.` that names a type, names: `this` or `super`'s, a type of
     * the language, a type parameter, a declared type of the type arguments written, else of those
     * expected.
     */
    private func typeOfReceiver(receiver: ExprId, expected: ?Ty): Ty {
        match (hir[receiver]) {
            case ThisExpr | SuperExpr => infer(receiver, None)
            case PrimExpr(name) => prim(name)
            case PathExpr(name, args) => match (resolveName(receiver, name)) {
                case Values(targets) where targets.size == 1 => match (targets[0]) {
                    case TypeParamOf(GenericOf(owner, index)) => Ty(db, ParamTy(owner, index))
                    case _ => error
                }
                case InFile(Found(ids)) where ids.size == 1 => typeOfDecl(ids[0], args.map {one => typeAt(one)}, expected)
                case _ => error
            }
            case FieldExpr(_, _, args) => match (resolveAccess(receiver)) {
                case PackageMembers(ids) where ids.size == 1 => typeOfDecl(ids[0], args.map {one => typeAt(one)}, expected)
                case _ => error
            }
            case _ => error
        }
    }

    /**
     * The type the declaration `id` names, applied to `explicit`, else to the arguments `expected`
     * has if of it; an alias expanded.
     */
    private func typeOfDecl(id: DefId, explicit: Array<Ty>, expected: ?Ty): Ty {
        match (id.item(db).kind) {
            case Class | Interface | Struct | Enum | BuiltIn => Ty(db, DeclTy(id, typeArgsOf(id, explicit, expected)))
            case TypeAlias =>
                let aliased = signatureTypes(db, id).ty ?? return error
                substitute(db, aliased, id, typeArgsOf(id, explicit, None))
            case _ => error
        }
    }
}

/**
 * Where a type of numbers named `name` comes among overloads (`numberOrder`): `Int64`, the other
 * integers, `Float64`, the other floats; -1 for no number.
 */
func numberRank(name: String): Int64 {
    if (name == "Int64") {
        0
    } else if (INTEGER_TYPES.contains(name)) {
        1
    } else if (name == "Float64") {
        2
    } else if (FLOAT_TYPES.contains(name)) {
        3
    } else {
        -1
    }
}

/**
 * Whether `text`, a literal, is a number.
 */
func isNumber(text: String): Bool {
    match (text.toRuneArray().get(0)) {
        case Some(first) => first.isAsciiNumber() || first == r'.'
        case None => false
    }
}

/**
 * The type a number's suffix names, `lower` the number in lower case: `i8`, `u64`, `f32`; a hex
 * number has no float suffix, its `f` a digit.
 */
func suffixOf(lower: String, isHex: Bool): ?String {
    for ((letter, name) in [("i", "Int"), ("u", "UInt"), ("f", "Float")] where !(isHex && letter == "f")) {
        for (bits in ["8", "16", "32", "64"] where lower.endsWith(letter + bits)) {
            return name + bits
        }
    }
    None
}

/**
 * The value of `text`, an integer literal of any base, `_`s and its suffix aside (`0x1`, `1_0`,
 * `2i64`); `None` if it is none, or too large to index anything.
 */
func integerOf(text: String): ?Int64 {
    let lower = text.replace("_", "").toAsciiLower()
    let (digits, radix) = if (lower.startsWith("0x")) {
        (lower[2..], 16)
    } else if (lower.startsWith("0o")) {
        (lower[2..], 8)
    } else if (lower.startsWith("0b")) {
        (lower[2..], 2)
    } else {
        (lower, 10)
    }
    var value = 0
    var any = false
    for (r in digits.runes()) {
        if (r == r'i' || r == r'u') {
            break
        }
        let digit = if (r.isAsciiNumber()) {
            Int64(UInt32(r) - UInt32(r'0'))
        } else if (r >= r'a' && r <= r'f') {
            Int64(UInt32(r) - UInt32(r'a')) + 10
        } else {
            return None
        }
        if (digit >= radix || value > (1 << 40)) {
            return None
        }
        value = value * radix + digit
        any = true
    }
    if (any) {
        value
    } else {
        None
    }
}
