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
public struct FieldTargets {
    public FieldTargets(public let expr: ExprId, public let targets: Array<MemberTarget>) {}
}

/**
 * What inference finds in a body (D55), rust-analyzer's `InferenceResult`: the type of each of its
 * expressions, patterns and locals, by id; the members found after the `.` of a value. A type not
 * found is an error type.
 */
@Derive[Equatable]
public struct InferenceResult {
    public InferenceResult(
        public let exprs!: Array<Ty> = [],
        public let pats!: Array<Ty> = [],
        public let locals!: Array<Ty> = [],
        public let fields!: Array<FieldTargets> = [],
        /**
         * The type the body gives its declaration: a function's return type, a variable's type;
         * `None` for one of no such type.
         */
        public let ty!: ?Ty = None
    ) {}

    public operator func [](id: ExprId): ?Ty {
        exprs.get(id.index)
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
        fields.iterator().filter {one => one.expr == expr}.next().map {one => one.targets}
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
    InferenceResult(exprs: lowered.exprs.map {_ => error}, pats: lowered.pats.map {_ => error},
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

/**
 * What a call may call: the types of its parameters and what it returns, as seen on what it is
 * called on; `open`, the declaration whose type parameters in them are the call's to infer (8c).
 */
struct Callable {
    Callable(let params: Array<Ty>, let ret: Ty, let open!: ?DefId = None) {}

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
 * One body as it is inferred.
 */
class Inference {
    private let hir: Body
    private let scopes: ExprScopes
    private let sig: SignatureTypes
    private let from: ?SourceFile
    private let pkg: ?Package
    private let error: Ty
    private let exprs: Array<Ty>
    private let pats: Array<Ty>
    private let locals: Array<Ty>
    private let types: Array<?Ty>
    private let lowering: SourceTyLowering
    // by expression: an argument inferred again replaces what it found
    private let fields = HashMap<Int64, FieldTargets>()
    private let frames = ArrayList<Frame>()
    // the first variable of the next call inferred: those of the calls being inferred are under it
    private var nextVar = 0

    Inference(private let db: AnalysisDatabase, private let def: DefId) {
        hir = body(db, def)
        scopes = exprScopes(db, def)
        sig = signatureTypes(db, def)
        from = sourceFileOf(db, def)
        pkg = packageOf(db, def)
        error = Ty(db, ErrorTy)
        exprs = Array<Ty>(hir.exprs.size, repeat: error)
        pats = Array<Ty>(hir.pats.size, repeat: error)
        locals = Array<Ty>(hir.locals.size, repeat: error)
        types = Array<?Ty>(hir.types.size, repeat: None)
        lowering = SourceTyLowering(db, def, hir)
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
        InferenceResult(exprs: exprs, pats: pats, locals: locals, fields: found, ty: ty)
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
     * the block's type joined with those of its `return`s (N100).
     */
    private func function(ret: ?Ty, block: ExprId): Ty {
        let frame = Frame(ret)
        frames.add(frame)
        let blockTy = infer(block, ret)
        frames.remove(at: frames.size - 1)
        match (ret) {
            case Some(one) => one
            case None => joinTys(db, [blockTy].concat(frame.returns.toArray()), from)
        }
    }

    private func param(one: BodyParam, ty: Ty): Unit {
        if (let Some(local) <- one.local) {
            locals[local.index] = ty
        }
        if (let Some(value) <- one.defaultValue) {
            infer(value, ty)
        }
    }

    private func prim(name: String): Ty {
        Ty(db, PrimTy(name))
    }

    /**
     * The type of `std.core`'s declaration `name` of `kind`, applied to `args`.
     */
    private func core(name: String, kind: ItemKind, args: Array<Ty>): Ty {
        match (coreId(name, kind)) {
            case Some(id) => Ty(db, DeclTy(id, args))
            case None => error
        }
    }

    private func coreId(name: String, kind: ItemKind): ?DefId {
        let ref = packageRefOf(db, def) ?? return None
        coreDecl(db, ref, name, kind)
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
     * Infers `id`, checked against `expected` if given, and records its type.
     */
    private func infer(id: ExprId, expected: ?Ty): Ty {
        let ty = inferExpr(id, expected)
        exprs[id.index] = ty
        ty
    }

    private func inferExpr(id: ExprId, expected: ?Ty): Ty {
        match (hir[id]) {
            case MissingExpr => error
            case MacroExpr(args) =>
                // what the macro makes of them is not known: each alone
                for (arg in args) {
                    infer(arg.expr, None)
                }
                error
            case LitExpr(text) => literalTy(text, expected)
            case StrExpr(parts) =>
                for (part in parts) {
                    infer(part, None)
                }
                core("String", ItemKind.Struct, [])
            case PathExpr(name, args) => pathTy(id, name, args, expected)
            case FieldExpr(receiver, name, args) => fieldTy(id, receiver, name, args, expected)
            case CallExpr(callee, args) => callTy(callee, args, expected)
            case IndexExpr(base, indices) => indexTy(base, indices)
            case OptionalExpr(inner) =>
                // `a?.b`, `a?()` (8e)
                infer(inner, None)
                error
            case UnaryExpr(op, operand) => unaryTy(op, operand, expected)
            case BinaryExpr(op, lhs, rhs) => binaryTy(op, lhs, rhs, expected)
            case IsExpr(inner, _) =>
                infer(inner, None)
                prim("Bool")
            case AsExpr(inner, ty) =>
                infer(inner, None)
                core("Option", ItemKind.Enum, [typeAt(ty)])
            case RangeExpr(start, end, step, _) => rangeTy(start, end, step, expected)
            case PostfixExpr(inner, _) =>
                infer(inner, None)
                prim("Unit")
            case TupleExpr(elements) =>
                let wanted = match (expected.map {one => one.kind(db)}) {
                    case Some(TupleTy(tys)) where tys.size == elements.size => tys
                    case _ => Array<Ty>()
                }
                Ty(db, TupleTy(Array(elements.size) {i => infer(elements[i], wanted.get(i))}))
            case ArrayExpr(elements) => arrayTy(elements, expected)
            case UnitExpr => prim("Unit")
            case IfExpr(condition, then, otherwise) =>
                infer(condition, prim("Bool"))
                match (otherwise) {
                    case Some(one) => branches([then, one], expected)
                    // of no `else`, `Unit` (N102)
                    case None =>
                        infer(then, None)
                        prim("Unit")
                }
            case LetExpr(patterns, value) =>
                let valueTy = infer(value, None)
                for (pat in patterns) {
                    bindPat(pat, valueTy)
                }
                prim("Bool")
            case MatchExpr(scrutinee, arms) => matchExprTy(scrutinee, arms, expected)
            case TryExpr(resources, tried, catches, cleanup) => tryExprTy(resources, tried, catches, cleanup, expected)
            case ForExpr(pat, iterated, guard, loopBody) =>
                bindPat(pat, elementTy(infer(iterated, None)))
                if (let Some(one) <- guard) {
                    infer(one, prim("Bool"))
                }
                infer(loopBody, None)
                prim("Unit")
            case WhileExpr(condition, loopBody) =>
                infer(condition, prim("Bool"))
                infer(loopBody, None)
                prim("Unit")
            case DoWhileExpr(loopBody, condition) =>
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
                match (infer(lambda, None).kind(db)) {
                    case FuncTy(_, ret, _) => core("Future", ItemKind.Class, [ret])
                    case _ => error
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
            // a type before a `.`, no value
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
                case ExprStmt(expr) => infer(expr, None)
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
        locals[fn.local.index] = Ty(db, FuncTy(params, written ?? error, false))
        if (let Some(block) <- fn.body) {
            let ret = function(written, block)
            locals[fn.local.index] = Ty(db, FuncTy(params, ret, false))
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
            one.returns.add(ty)
        }
    }

    /**
     * Branches of an `if`, `match` or `try`, each checked against `expected`: their join, or, if
     * there is none, what was expected (N97, N106).
     */
    private func branches(ids: Array<ExprId>, expected: ?Ty): Ty {
        let tys = ids.map {one => infer(one, expected)}
        let joined = joinTys(db, tys, from)
        match (expected) {
            case Some(one) where joined.kind(db) == ErrorTy => one
            case _ => joined
        }
    }

    private func matchExprTy(scrutinee: ?ExprId, arms: Array<MatchArm>, expected: ?Ty): Ty {
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
        branches(arms.map {arm => arm.body}, expected)
    }

    private func tryExprTy(resources: Array<Resource>, tried: ExprId, catches: Array<CatchArm>, cleanup: ?ExprId,
        expected: ?Ty): Ty {
        for (resource in resources) {
            let declared = resource.ty.map {one => typeAt(one)}
            let valueTy = infer(resource.value, declared)
            if (let Some(local) <- resource.local) {
                locals[local.index] = declared ?? valueTy
            }
        }
        for (arm in catches) {
            if (let Some(local) <- arm.local) {
                // `e: A | B` is of their join
                locals[local.index] = joinTys(db, arm.types.map {one => typeAt(one)}, from)
            }
        }
        if (let Some(one) <- cleanup) {
            infer(one, None)
        }
        branches([tried].concat(catches.map {arm => arm.body}), expected)
    }

    /**
     * The type of the elements of what `for` iterates over: the argument of the `Iterable` it is an
     * instance of (N105).
     */
    private func elementTy(iterated: Ty): Ty {
        let iterable = coreId("Iterable", ItemKind.Interface) ?? return error
        match (asInstanceOf(db, iterated, iterable, from).map {one => one.kind(db)}) {
            case Some(DeclTy(_, args)) => args.get(0) ?? error
            case _ => error
        }
    }

    /**
     * A lambda: its parameters of the types they write, else of the function type expected; it
     * returns what that type does, else the join of its block's type and its `return`s' (N103).
     */
    private func lambdaTy(params: Array<BodyParam>, block: ExprId, expected: ?Ty): Ty {
        let wanted: ?(Array<Ty>, ?Ty) = match (expected.map {one => one.kind(db)}) {
            // a return type unknown, of a type argument not solved yet, is synthesized (8c)
            case Some(FuncTy(tys, ret, _)) where tys.size == params.size && ret.kind(db) == ErrorTy => (tys, None)
            case Some(FuncTy(tys, ret, _)) where tys.size == params.size => (tys, ret)
            case _ => None
        }
        let paramTys = Array(params.size) {
            i => match (params[i].ty) {
                case Some(ty) => typeAt(ty)
                case None => wanted.flatMap {one => one[0].get(i)} ?? error
            }
        }
        for (i in 0..params.size) {
            param(params[i], paramTys[i])
        }
        Ty(db, FuncTy(paramTys, function(wanted.flatMap {one => one[1]}, block), false))
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
            return core("String", ItemKind.Struct, [])
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
     * The type of the language `expected` is, `?T` looked through.
     */
    private func expectedPrim(expected: ?Ty): ?String {
        let one = expected ?? return None
        match (one.kind(db)) {
            case PrimTy(name) => name
            case DeclTy(id, args) where args.size == 1 && Some(id) == coreId("Option", ItemKind.Enum) =>
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

    private func unaryTy(op: String, operand: ExprId, expected: ?Ty): Ty {
        let ty = infer(operand, expected)
        match (ty.kind(db)) {
            case PrimTy(name) where op == "!" && (name == "Bool" || INTEGER_TYPES.contains(name)) => ty
            case PrimTy(name) where op == "-" && (INTEGER_TYPES.contains(name) || FLOAT_TYPES.contains(name)) => ty
            // an operator a type declares (8e)
            case _ => error
        }
    }

    /**
     * An operator between two: an assignment is `Unit`, its right checked against its left; one of
     * the language's between its types, a literal of the type of the other side (N99); one a type
     * declares, not yet (8e).
     */
    private func binaryTy(op: String, lhs: ExprId, rhs: ExprId, expected: ?Ty): Ty {
        if (ASSIGNMENTS.contains(op)) {
            let target = infer(lhs, None)
            infer(rhs, target)
            return prim("Unit")
        }
        if (op == "&&" || op == "||") {
            infer(lhs, prim("Bool"))
            infer(rhs, prim("Bool"))
            return prim("Bool")
        }
        if (!COMPARISONS.contains(op) && !ARITHMETIC.contains(op)) {
            // `??`, `|>`, `~>` (8e)
            infer(lhs, None)
            infer(rhs, None)
            return error
        }
        let isComparison = COMPARISONS.contains(op)
        var left = error
        var right = error
        if (isNumericLiteral(lhs) && !isNumericLiteral(rhs)) {
            right = infer(rhs, None)
            left = infer(lhs, right)
        } else {
            left = infer(lhs, if (isComparison) {
                None
            } else {
                expected
            })
            right = infer(rhs, rightExpected(op, left))
        }
        match ((left.kind(db), right.kind(db))) {
            case (PrimTy(_), PrimTy(_)) where isComparison => prim("Bool")
            case (PrimTy(_), PrimTy(_)) => left
            case _ => error
        }
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
            case Some(DeclTy(id, args)) where args.size == 1 && Some(id) == coreId("Range", ItemKind.Struct) => args[0]
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
        core("Range", ItemKind.Struct, [element ?? error])
    }

    /**
     * An array: its elements checked against the element type of the `Array` expected, else of their
     * join (N98).
     */
    private func arrayTy(elements: Array<ExprId>, expected: ?Ty): Ty {
        let wanted: ?Ty = match (expected.map {one => one.kind(db)}) {
            case Some(DeclTy(id, args)) where args.size == 1 && Some(id) == coreId("Array", ItemKind.Struct) => args[0]
            case _ => None
        }
        let element = match (wanted) {
            case Some(one) =>
                for (e in elements) {
                    infer(e, one)
                }
                one
            case None where elements.isEmpty() => error
            case None => joinTys(db, elements.map {e => infer(e, None)}, from)
        }
        core("Array", ItemKind.Struct, [element])
    }

    /**
     * `a[i]`: an element of a tuple by a literal; of anything else, the operator `[]` (8e).
     */
    private func indexTy(base: ExprId, indices: Array<ExprId>): Ty {
        let baseTy = infer(base, None)
        for (index in indices) {
            infer(index, None)
        }
        match ((baseTy.kind(db), indices.get(0).map {one => hir[one]})) {
            case (TupleTy(elements), Some(LitExpr(text))) where indices.size == 1 =>
                match (Int64.tryParse(text)) {
                    case Some(n) => elements.get(n) ?? error
                    case None => error
                }
            case _ => error
        }
    }

    /**
     * Binds the pattern `pat` to a value of the type `ty`: its names locals of the types their parts
     * are (N105).
     */
    private func bindPat(pat: PatId, ty: Ty): Unit {
        pats[pat.index] = ty
        match (hir[pat]) {
            case BindPat(local) =>
                let one = hir[local]
                if (!one.lone || !isCtorName(one.name)) {
                    locals[local.index] = ty
                }
            case TypePat(local, written) =>
                let typed = typeAt(written)
                if (let Some(one) <- local) {
                    locals[one.index] = typed
                }
            case TuplePat(elements) =>
                let tys = match (ty.kind(db)) {
                    case TupleTy(all) where all.size == elements.size => all
                    case _ => Array<Ty>()
                }
                for (i in 0..elements.size) {
                    bindPat(elements[i], tys.get(i) ?? error)
                }
            case EnumPat(path, args) =>
                let params = ctorParamsOf(path, ty)
                for (i in 0..args.size) {
                    bindPat(args[i], params.get(i) ?? error)
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
        match (resolveBodyName(db, def, scopes.scopeOf(id), name)) {
            case Values(targets) where targets.size == 1 => match (targets[0]) {
                case LocalOf(local) => locals[local.index]
                case MemberOf(target) => memberValueTy(target, thisTy())
                case DeclOf(decl) => declValueTy(decl, explicit, expected)
                case TypeParamOf(_) => error
            }
            case InFile(Found(ids)) where ids.size == 1 => declValueTy(ids[0], explicit, expected)
            case InFile(Ctors(own, all)) => match (chooseCtor(own, all, expected)) {
                case Some(ctor) => declValueTy(ctor, explicit, expected)
                case None => error
            }
            // functions overloading one another, as a value (8d)
            case _ => error
        }
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
        Callable(signatureTypes(db, id).params.map {one => seen(one)}, seen(valueOf(id)), open: open)
    }

    /**
     * The enum constructor `id`, its enum's type arguments `explicit`, else those of `recv` or of
     * `expected` if of its enum, else open, the call's to infer (8c).
     */
    private func ctorCallable(id: DefId, explicit: Array<Ty>, recv: ?Ty, expected: ?Ty): ?Callable {
        let parent = parentOf(db, id) ?? return None
        let (args, open) = openTypeArgsOf(parent, explicit, recv ?? expected)
        Callable(signatureTypes(db, id).params.map {one => substitute(db, one, parent, args)},
            Ty(db, DeclTy(parent, args)), open: open)
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
            member => Callable(signatureTypes(db, DefId(db, file, member.id)).params.map {
                one => substitute(db, one, id, args)
            }, self, open: open)
        }
    }

    /**
     * What a value of the type `ty` calls.
     */
    private func valueCallables(ty: Ty): Array<Callable> {
        match (ty.kind(db)) {
            case FuncTy(params, ret, _) => [Callable(params, ret)]
            case _ => []
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
     * several; its arguments checked against that one's parameters in order, a named one inferred
     * alone. Overloads it does not tell apart are 8d's.
     */
    private func callTy(callee: ExprId, args: Array<CallArg>, expected: ?Ty): Ty {
        let all = overriding(callablesOf(callee, expected))
        let fitting = if (all.size > 1) {
            all.filter {one => one.params.size == args.size}
        } else {
            all
        }
        if (fitting.size != 1) {
            for (arg in args) {
                infer(arg.expr, None)
            }
            return error
        }
        let callable = fitting[0]
        if (let Some(owner) <- callable.open) {
            return genericCallTy(callee, callable, owner, args, expected)
        }
        exprs[callee.index] = callable.ty(db)
        var positional = 0
        for (arg in args) {
            if (arg.name.isSome()) {
                infer(arg.expr, None)
            } else {
                infer(arg.expr, callable.params.get(positional))
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
                        let ty = infer(expr, None)
                        if (hasErrors(db, ty)) {
                            waiting.add(i)
                        } else {
                            synthesized[i] = ty
                        }
                    }
                case Some(target) => infer(expr, target)
                case None => infer(expr, None)
            }
        }
        let solve = {
            =>
            let solver = TypeArgSolver(db, base, count, from, coreId("Option", ItemKind.Enum))
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
                if (isUntypedLambda(args[i].expr) || !hasErrors(db, ty)) {
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
        let final = {ty: Ty => replaceVars(db, ty, base, solution)}
        for (i in 0..args.size) {
            let target = targets[i] ?? continue
            if (ideal[i].isSome() || waiting.contains(i) || isUntypedLambda(args[i].expr)) {
                infer(args[i].expr, final(target))
            }
        }
        nextVar = base
        exprs[callee.index] = Ty(db, FuncTy(params.map(final), final(ret), false))
        final(ret)
    }

    /**
     * Whether a parameter's type, solved as far as it is, tells an argument that waits anything:
     * a function type's parameters all known, any other type not unknown as a whole (cjc's
     * `UnsolvedAsQuest`).
     */
    private func isKnownEnough(target: Ty): Bool {
        match (target.kind(db)) {
            case FuncTy(params, _, _) => params.iterator().all {one => !hasErrors(db, one)}
            case ErrorTy => false
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
     * What the callee `callee` may call.
     */
    private func callablesOf(callee: ExprId, expected: ?Ty): Array<Callable> {
        match (hir[callee]) {
            case PathExpr(name, args) =>
                let explicit = args.map {one => typeAt(one)}
                match (resolveBodyName(db, def, scopes.scopeOf(callee), name)) {
                    case Values(targets) =>
                        let found = ArrayList<Callable>()
                        for (target in targets) {
                            match (target) {
                                case LocalOf(local) => found.add(all: valueCallables(locals[local.index]))
                                case MemberOf(member) => found.add(all: memberCallables(member, thisTy(), explicit, expected))
                                case DeclOf(id) => found.add(all: declCallables(id, explicit, expected))
                                case TypeParamOf(_) => ()
                            }
                        }
                        found.toArray()
                    case InFile(Found(ids)) =>
                        let found = ArrayList<Callable>()
                        for (id in ids) {
                            found.add(all: declCallables(id, explicit, expected))
                        }
                        found.toArray()
                    case InFile(Ctors(own, all)) => match (chooseCtor(own, all, expected)) {
                        case Some(ctor) => declCallables(ctor, explicit, expected)
                        case None => []
                    }
                    case _ => []
                }
            case FieldExpr(receiver, name, args) => fieldCallables(callee, receiver, name, args, expected)
            // `super(…)` and `this(…)` in a constructor
            case SuperExpr | ThisExpr => match (infer(callee, None).kind(db)) {
                case DeclTy(id, args) => initCallables(id, args).map {one => Callable(one.params, prim("Unit"))}
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
        match (resolveField(db, def, expr)) {
            case PackageMembers(ids) =>
                for (id in ids) {
                    found.add(all: declCallables(id, explicit, expected))
                }
            case TypeMembers(targets) =>
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
        match (resolveField(db, def, expr)) {
            case PackageMembers(ids) where ids.size == 1 => declValueTy(ids[0], explicit, expected)
            case TypeMembers(targets) where targets.size == 1 =>
                memberValueTy(targets[0], typeOfReceiver(receiver, expected))
            case OfValue =>
                let (targets, recv) = valueMembers(expr, infer(receiver, None), name)
                if (targets.size == 1) {
                    memberValueTy(targets[0], recv)
                } else {
                    error
                }
            case _ => error
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
                fields[expr.index] = FieldTargets(expr, targets)
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
            case PathExpr(name, args) => match (resolveBodyName(db, def, scopes.scopeOf(receiver), name)) {
                case Values(targets) where targets.size == 1 => match (targets[0]) {
                    case TypeParamOf(GenericOf(owner, index)) => Ty(db, ParamTy(owner, index))
                    case _ => error
                }
                case InFile(Found(ids)) where ids.size == 1 => typeOfDecl(ids[0], args.map {one => typeAt(one)}, expected)
                case _ => error
            }
            case FieldExpr(_, _, args) => match (resolveField(db, def, receiver)) {
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
