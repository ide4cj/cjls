package loupe.hir

import std.collection.*
import loupe.db.{AnalysisDatabase, SourceFile}

/**
 * The supertypes of `ty` one level up, as the file `from` sees them: those its declaration names,
 * its arguments substituted, then those of the `extend`s of it the file sees whose type `ty` is an
 * instance of (an `extend Box<Int64>` is not `Box<String>`'s, N86). None of a tuple, a function or
 * a type parameter.
 */
func directSupertypes(db: AnalysisDatabase, ty: Ty, from: ?SourceFile): Array<Ty> {
    let (head, named) = match (ty.kind(db)) {
        case DeclTy(id, args) => (ExtendedType.DeclType(id), signatureTypes(db, id).supers.map {
            one => substitute(db, one, id, args)
        })
        case PrimTy(name) => (ExtendedType.PrimType(name), Array<Ty>())
        case _ => return []
    }
    let found = ArrayList<Ty>(named)
    for (ext in extendsOf(db, head, from)) {
        let args = extendArgs(db, ext, ty) ?? continue
        for (one in signatureTypes(db, ext).supers) {
            let applied = substitute(db, one, ext, args)
            if (!found.contains(applied)) {
                found.add(applied)
            }
        }
    }
    found.toArray()
}

/**
 * The arguments of the type parameters of the `extend` `ext` that make the type it extends `ty`;
 * `None` if no arguments do. One `ty` does not tell is an error type.
 */
func extendArgs(db: AnalysisDatabase, ext: DefId, ty: Ty): ?Array<Ty> {
    let sig = signatureTypes(db, ext)
    let pattern = sig.ty ?? return None
    let binds = Array<?Ty>(sig.generics.size, repeat: None)
    if (!matchTy(db, pattern, ty, ext, binds)) {
        return None
    }
    binds.map {one => one ?? Ty(db, ErrorTy)}
}

/**
 * Whether `actual` is `pattern`, a type written with the type parameters of `owner`, for some of
 * their arguments, each bound in `binds` as it is met. An error type in `actual` matches anything:
 * what is not known hides nothing.
 */
func matchTy(db: AnalysisDatabase, pattern: Ty, actual: Ty, owner: DefId, binds: Array<?Ty>): Bool {
    let all = {patterns: Array<Ty>, actuals: Array<Ty> => patterns.size == actuals.size &&
        (0..patterns.size).iterator().all {i => matchTy(db, patterns[i], actuals[i], owner, binds)}}
    match ((pattern.kind(db), actual.kind(db))) {
        case (_, ErrorTy) => true
        case (ParamTy(of, index), _) where of == owner && index < binds.size => match (binds[index]) {
            case Some(bound) => bound == actual
            case None =>
                binds[index] = actual
                true
        }
        case (DeclTy(a, aArgs), DeclTy(b, bArgs)) => a == b && all(aArgs, bArgs)
        case (TupleTy(a), TupleTy(b)) => all(a, b)
        case (FuncTy(aParams, aRet, aC), FuncTy(bParams, bRet, bC)) => aC == bC && all(aParams.concat([aRet]), bParams.concat([bRet]))
        case (VArrayTy(a, aSize), VArrayTy(b, bSize)) => aSize == bSize && matchTy(db, a, b, owner, binds)
        case _ => pattern == actual
    }
}

/**
 * `ty` as an instance of the declaration `target`: itself or one of its supertypes, level by level,
 * its arguments substituted (`IntBoxes` as a `Box` is `Box<Array<Int64>>`); `None` if it is none.
 */
func asInstanceOf(db: AnalysisDatabase, ty: Ty, target: DefId, from: ?SourceFile): ?Ty {
    for (one in allSupertypes(db, ty, from)) {
        if (let DeclTy(id, _) <- one.kind(db) && id == target) {
            return one
        }
    }
    None
}

/**
 * `ty` and its supertypes, level by level, each once, and each declaration's own once: supertypes
 * of a cycle cjc reports (`A<T> <: B<A<T>>`, `B<T> <: A<B<T>>`) would grow without end.
 */
func allSupertypes(db: AnalysisDatabase, ty: Ty, from: ?SourceFile): Array<Ty> {
    let found = ArrayList<Ty>([ty])
    let seen = HashSet<Ty>([ty])
    let expanded = HashSet<DefId>()
    var at = 0
    while (at < found.size) {
        let one = found[at]
        at++
        if (let DeclTy(id, _) <- one.kind(db) && !expanded.add(id)) {
            continue
        }
        for (next in directSupertypes(db, one, from) where !seen.contains(next)) {
            seen.add(next)
            found.add(next)
        }
    }
    found.toArray()
}

/**
 * Whether `sub` is `sup` or one of its subtypes; `Nothing` is every type's, and an error type
 * stands for any.
 */
func isSubtype(db: AnalysisDatabase, sub: Ty, sup: Ty, from: ?SourceFile): Bool {
    if (sub == sup) {
        return true
    }
    match ((sub.kind(db), sup.kind(db))) {
        case (ErrorTy, _) | (_, ErrorTy) => true
        case (PrimTy("Nothing"), _) => true
        case (_, DeclTy(id, _)) => asInstanceOf(db, sub, id, from) == Some(sup)
        case _ => false
    }
}

func isNothing(db: AnalysisDatabase, ty: Ty): Bool {
    ty.kind(db) == PrimTy("Nothing")
}

/**
 * The type of branches of the types `tys`, as cjc joins those of an `if` or a `match`: `Nothing`
 * leaves the others, equal types are their type, else the one common supertype that is a subtype
 * of every other common one (`A` and `B` of `Base`, N97); an error if there is none, or several
 * (two classes of one interface: `Object` and the interface), or a literal of another type (`1` and
 * `2u8`).
 */
func joinTys(db: AnalysisDatabase, tys: Array<Ty>, from: ?SourceFile): Ty {
    let real = tys.filter {one => !isNothing(db, one)}
    let first = real.get(0) ?? return Ty(db, PrimTy("Nothing"))
    if (real.iterator().any {one => one.kind(db) == ErrorTy}) {
        return Ty(db, ErrorTy)
    }
    if (real.iterator().all {one => one == first}) {
        return first
    }
    let common = allSupertypes(db, first, from).filter {
        candidate => real.iterator().all {one => isSubtype(db, one, candidate, from)}
    }
    let least = common.filter {candidate => common.iterator().all {other => isSubtype(db, candidate, other, from)}}
    if (least.size == 1) {
        least[0]
    } else {
        Ty(db, ErrorTy)
    }
}

/**
 * The type `ty`, written in the member `member`, as a member of a value of the type `recv`: the
 * type parameters of the type or `extend` it is in replaced by `recv`'s arguments as an instance of
 * it, `This` by `recv` (N88); `None` for a member of an `extend` `recv` is no instance of (N86).
 */
func asMemberOf(db: AnalysisDatabase, ty: Ty, member: DefId, recv: Ty, from: ?SourceFile): ?Ty {
    let owner = parentOf(db, member) ?? return ty
    let args = ownerArgs(db, owner, recv, from) ?? return None
    let applied = substitute(db, ty, owner, args)
    if (applied.kind(db) == ThisTy) {
        recv
    } else {
        applied
    }
}

/**
 * The arguments of the type parameters of `owner`, a type or an `extend`, `recv` gives them;
 * `None` for an `extend` of a type `recv` is no instance of.
 */
func ownerArgs(db: AnalysisDatabase, owner: DefId, recv: Ty, from: ?SourceFile): ?Array<Ty> {
    if (owner.item(db).kind == ItemKind.Extend) {
        let extended = signatureTypes(db, owner).ty ?? return None
        let instance = match (extended.kind(db)) {
            case DeclTy(id, _) => asInstanceOf(db, recv, id, from) ?? return None
            case _ => recv
        }
        return extendArgs(db, owner, instance)
    }
    match (asInstanceOf(db, recv, owner, from).map {one => one.kind(db)}) {
        case Some(DeclTy(_, args)) => args
        // a member of a type the value is no instance of: a type parameter's bound, a `.cjo` cjc
        // checked; its arguments unknown
        case _ => genericsOf(db, owner).map {_ => Ty(db, ErrorTy)}
    }
}

/**
 * `ty` with the type parameters of `owner` unknown: those of a function called whose arguments are
 * not inferred yet (8c).
 */
func eraseParams(db: AnalysisDatabase, ty: Ty, owner: DefId): Ty {
    let count = genericsOf(db, owner).size
    if (count == 0) {
        return ty
    }
    substitute(db, ty, owner, Array(count) {_ => Ty(db, ErrorTy)})
}
