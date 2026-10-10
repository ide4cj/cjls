package loupe.hir

import std.collection.*
import loupe.db.{AnalysisDatabase, SourceFile}

/**
 * What a call tells of one of its type arguments not written (D57): the types it is a supertype of
 * (`lower`: what is passed), those it is a subtype of (`upper`: its type parameter's bounds, what
 * the call is expected to be), and whether an integer or a float literal of no suffix is passed for
 * it, cjc's ideal types.
 */
class VarBounds {
    let lower = ArrayList<Ty>()
    let upper = ArrayList<Ty>()
    var integer = false
    var float = false
}

/**
 * The type arguments not written of one call, as cjc's `LocalTypeArgumentSynthesis` solves them
 * (D57): `count` variables, `InferTy(base)` on, each bounded by what the call's arguments and the
 * type expected of it say, then chosen: the join of what is passed, else the one bound under every
 * other. No variable outlives the call: what it passes is inferred before, its own variables solved.
 */
class TypeArgSolver {
    private let bounds: Array<VarBounds>

    TypeArgSolver(private let db: AnalysisDatabase, private let base: Int64, private let count: Int64,
        private let from: ?SourceFile, private let option: ?DefId) {
        bounds = Array(count) {_ => VarBounds()}
    }

    /**
     * Bounds each variable by the bounds its type parameter `vars` stands for declares: `T <: Base`
     * of `where` (cjc's `CopyUpperbound`).
     */
    func boundedBy(owner: DefId, vars: Array<Ty>): Unit {
        for (bound in signatureTypes(db, owner).bounds) {
            if (let ParamTy(of, index) <- bound.ty.kind(db) && of == owner && index < count) {
                for (one in bound.bounds) {
                    add(bounds[index].upper, substitute(db, one, owner, vars))
                }
            }
        }
    }

    /**
     * Constrains the variables in `sub` and `sup` so that `sub <: sup`: a variable is above what is
     * below it and below what is above it; a type argument is invariant, a function's parameters
     * contravariant; a value is boxed into an `Option` it is not (cjc's `Unify`). Nothing of an
     * error type, which stands for anything.
     */
    func constrain(sub: Ty, sup: Ty): Unit {
        if (let Some(index) <- varOf(sup)) {
            add(bounds[index].lower, sub)
            return
        }
        if (let Some(index) <- varOf(sub)) {
            add(bounds[index].upper, sup)
            return
        }
        if (!hasVars(sub) && !hasVars(sup)) {
            return
        }
        match ((sub.kind(db), sup.kind(db))) {
            case (ErrorTy, _) | (_, ErrorTy) | (TodoTy(_), _) | (_, TodoTy(_)) => ()
            case (TupleTy(a), TupleTy(b)) where a.size == b.size =>
                for (i in 0..a.size) {
                    constrain(a[i], b[i])
                }
            case (FuncTy(aParams, aRet, _), FuncTy(bParams, bRet, _)) where aParams.size == bParams.size =>
                for (i in 0..aParams.size) {
                    constrain(bParams[i], aParams[i])
                }
                constrain(aRet, bRet)
            // no `VArray` of a type parameter: cjc rejects one
            case (_, DeclTy(id, args)) => match (asInstanceOf(db, sub, id, from).map {one => one.kind(db)}) {
                case Some(DeclTy(_, subArgs)) where subArgs.size == args.size =>
                    for (i in 0..args.size) {
                        equal(subArgs[i], args[i])
                    }
                case _ where Some(id) == option && args.size == 1 => constrain(sub, args[0])
                case _ => ()
            }
            case _ => ()
        }
    }

    /**
     * Constrains for a literal of no suffix passed for a parameter of the type `param`: an integer
     * or, if `isFloat`, a float, of whatever type of its kind the variable turns out to be.
     */
    func literal(isFloat: Bool, param: Ty): Unit {
        if (let Some(index) <- varOf(param)) {
            if (isFloat) {
                bounds[index].float = true
            } else {
                bounds[index].integer = true
            }
            return
        }
        if (let DeclTy(id, args) <- param.kind(db) && Some(id) == option && args.size == 1) {
            literal(isFloat, args[0])
        }
    }

    /**
     * The type of each variable, `None` for one nothing tells, or of bounds no type meets. A lower
     * bound holds no variable: what is passed was inferred before, with none. An upper bound may (a
     * `where` bound, `T <: Comparable<T>`): one still naming a variable not solved is left out, so
     * the order of cjc's `TyVarConstraintGraph` is no question.
     */
    func solve(): Array<?Ty> {
        let solved = Array<?Ty>(count, repeat: None)
        let known = {tys: Array<Ty> => tys.map {one => replaceVars(db, one, base, solved)}.filter {
            one => !hasUnknowns(db, one)
        }}
        for (i in 0..count) {
            solved[i] = choose(known(bounds[i].lower.toArray()), known(bounds[i].upper.toArray()), bounds[i])
        }
        solved
    }

    /**
     * The type of a variable of the bounds `lower`, `upper` and `of` (cjc's `FindSolution`): the
     * join of what is passed if it is under every upper bound, a literal's of a type of its kind;
     * else, of literals alone, a numeric upper bound of their kind, or `Int64` and `Float64`; else
     * the upper bound under every other.
     */
    private func choose(lower: Array<Ty>, upper: Array<Ty>, of: VarBounds): ?Ty {
        if (of.integer && of.float) {
            return None
        }
        let ideal: ?Array<String> = if (of.integer) {
            Some(INTEGER_TYPES)
        } else if (of.float) {
            Some(FLOAT_TYPES)
        } else {
            None
        }
        let real = lower.filter {one => !isNothing(db, one)}
        if (!real.isEmpty()) {
            let joined = joinTys(db, real, from)
            let fitsIdeal = match ((ideal, joined.kind(db))) {
                case (None, _) => true
                case (Some(kinds), PrimTy(name)) => kinds.contains(name)
                case _ => false
            }
            if (!isUnknown(db, joined) && fitsIdeal && upper.iterator().all {one => fits(joined, one)}) {
                return joined
            }
            return None
        }
        if (let Some(kinds) <- ideal) {
            for (one in upper) {
                if (let PrimTy(name) <- one.kind(db) && kinds.contains(name)) {
                    return one
                }
            }
            return Ty(db, PrimTy(if (of.integer) {
                "Int64"
            } else {
                "Float64"
            }))
        }
        if (!lower.isEmpty()) {
            // what is passed is `Nothing` alone (`gen(throw e)`): an upper bound if there is one,
            // else `Nothing` itself, which cjc gives too (`let _: Int64 = gen(throw e)` compiles)
            if (let Some(met) <- meet(upper)) {
                return met
            }
            return lower[0]
        }
        meet(upper)
    }

    /**
     * The one of `tys` that is a subtype of every other.
     */
    private func meet(tys: Array<Ty>): ?Ty {
        let least = tys.filter {one => tys.iterator().all {other => fits(one, other)}}
        least.get(0)
    }

    /**
     * Whether a value of the type `sub` may be passed for `sup`: a subtype, or boxed into an
     * `Option`.
     */
    private func fits(sub: Ty, sup: Ty): Bool {
        isAssignable(db, sub, sup, from, option)
    }

    private func equal(a: Ty, b: Ty): Unit {
        constrain(a, b)
        constrain(b, a)
    }

    private func add(tys: ArrayList<Ty>, ty: Ty): Unit {
        if (!tys.contains(ty)) {
            tys.add(ty)
        }
    }

    /**
     * The index of the variable `ty` is, if it is one of this call's.
     */
    private func varOf(ty: Ty): ?Int64 {
        match (ty.kind(db)) {
            case InferTy(n) where n >= base && n < base + count => n - base
            case _ => None
        }
    }

    private func hasVars(ty: Ty): Bool {
        anyIn(db, ty) {one => varOf(one).isSome()}
    }
}

/**
 * Whether `ty` or a type in it is one `test` holds of.
 */
func anyIn(db: AnalysisDatabase, ty: Ty, test: (Ty) -> Bool): Bool {
    if (test(ty)) {
        return true
    }
    let all = {tys: Array<Ty> => tys.iterator().any {one => anyIn(db, one, test)}}
    match (ty.kind(db)) {
        case DeclTy(_, args) => all(args)
        case TupleTy(elements) => all(elements)
        case FuncTy(params, ret, _) => all(params) || anyIn(db, ret, test)
        case VArrayTy(element, _) => anyIn(db, element, test)
        case _ => false
    }
}

/**
 * Whether `ty` is or holds a type not known.
 */
func hasUnknowns(db: AnalysisDatabase, ty: Ty): Bool {
    anyIn(db, ty) {one => isUnknown(db, one)}
}

/**
 * The type not known that `tys` are or hold, what a type made of them is when it cannot be found:
 * one the analysis cannot find before an error, for an error may be no error once it is found
 * (D76); `None` if they hold none.
 */
func unknownOf(db: AnalysisDatabase, tys: Array<Ty>): ?Ty {
    var error: ?Ty = None
    for (ty in tys) {
        match (firstUnknownIn(db, ty)) {
            case Some(found) where isTodo(db, found) => return found
            case Some(found) where error.isNone() => error = found
            case _ => ()
        }
    }
    error
}

/**
 * The first type not known `ty` is or holds, one the analysis cannot find before an error.
 */
func firstUnknownIn(db: AnalysisDatabase, ty: Ty): ?Ty {
    if (isUnknown(db, ty)) {
        return ty
    }
    let all = {tys: Array<Ty> => unknownOf(db, tys)}
    match (ty.kind(db)) {
        case DeclTy(_, args) => all(args)
        case TupleTy(elements) => all(elements)
        case FuncTy(params, ret, _) => all(params.concat([ret]))
        case VArrayTy(element, _) => firstUnknownIn(db, element)
        case _ => None
    }
}

func isTodo(db: AnalysisDatabase, ty: Ty): Bool {
    match (ty.kind(db)) {
        case TodoTy(_) => true
        case _ => false
    }
}

/**
 * Whether `ty` is or holds a variable of a call.
 */
func hasInferVars(db: AnalysisDatabase, ty: Ty): Bool {
    anyIn(db, ty) {
        one => match (one.kind(db)) {
            case InferTy(_) => true
            case _ => false
        }
    }
}

/**
 * `ty` with each variable `InferTy(base + i)` replaced by `solved[i]`, `unsolved` if `None`: an
 * error type unless given.
 */
func replaceVars(db: AnalysisDatabase, ty: Ty, base: Int64, solved: Array<?Ty>, unsolved!: ?Ty = None): Ty {
    let all = {tys: Array<Ty> => tys.map {one => replaceVars(db, one, base, solved, unsolved: unsolved)}}
    match (ty.kind(db)) {
        case InferTy(n) where n >= base && n < base + solved.size => solved[n - base] ?? unsolved ?? Ty(db, ErrorTy)
        case DeclTy(def, args) => Ty(db, DeclTy(def, all(args)))
        case TupleTy(elements) => Ty(db, TupleTy(all(elements)))
        case FuncTy(params, ret, isC) => Ty(db, FuncTy(all(params), replaceVars(db, ret, base, solved, unsolved: unsolved), isC))
        case VArrayTy(element, size) => Ty(db, VArrayTy(replaceVars(db, element, base, solved, unsolved: unsolved), size))
        case _ => ty
    }
}
