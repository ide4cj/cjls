package loupe.hir

import std.collection.*
import calca.*
import calca.macros.*
import loupe.db.{AnalysisDatabase, SourceFile}

// A resource limit, not a language limit: overflow becomes UnknownTy, never a partial proof (A30).
const GENERIC_BOUNDS_LIMIT = 256

/**
 * The declaration's written bounds and those its bounding interfaces require of their arguments
 * (#437). Keep this separate from signature lowering: mutually referring signatures are valid.
 * An expansion exceeding the budget returns unknown bounds for its parameters instead (A30).
 */
@CalcaTracked
func genericBounds(db: AnalysisDatabase, owner: DefId): Array<TyBound> {
    let pending = ArrayList<TyBound>()
    let seen = HashMap<Ty, HashSet<Ty>>()
    for (bound in signatureTypes(db, owner).bounds) {
        for (upper in bound.bounds) {
            if (!addGenericBound(db, pending, seen, bound.ty, upper)) {
                return incompleteGenericBounds(db, owner, pending)
            }
        }
    }
    var at = 0
    while (at < pending.size) {
        let bound = pending[at]
        at++
        if (let DeclTy(id, args) <- bound.bounds[0].kind(db)) {
            for (required in signatureTypes(db, id).bounds) {
                let subject = substitute(db, required.ty, id, args)
                for (upper in required.bounds) {
                    if (
                        !addGenericBound(
                            db,
                            pending,
                            seen,
                            subject,
                            substitute(db, upper, id, args)
                        )
                    ) {
                        return incompleteGenericBounds(db, owner, pending)
                    }
                }
            }
        }
    }
    pending.toArray()
}

/**
 * Records a new instantiated relation, as cjc's Assumption does. A concrete subject is a
 * requirement to validate, not an assumption about a type parameter; it adds no further bounds.
 */
func addGenericBound(
    db: AnalysisDatabase,
    pending: ArrayList<TyBound>,
    seen: HashMap<Ty, HashSet<Ty>>,
    subject: Ty,
    upper: Ty
): Bool {
    if (subject == upper) {
        return true
    }
    match (subject.kind(db)) {
        case ParamTy(_, _) => ()
        case _ => return true
    }
    let bounds = seen.get(subject) ?? HashSet<Ty>()
    if (bounds.contains(upper)) {
        return true
    }
    if (pending.size >= GENERIC_BOUNDS_LIMIT) {
        return false
    }
    bounds.add(upper)
    seen[subject] = bounds
    pending.add(TyBound(subject, [upper]))
    true
}

func incompleteGenericBounds(
    db: AnalysisDatabase,
    owner: DefId,
    pending: ArrayList<TyBound>
): Array<TyBound> {
    let subjects =
        ArrayList<Ty>(Array(genericsOf(db, owner).size) { i => Ty(db, ParamTy(owner, i)) })
    for (bound in pending where !subjects.contains(bound.ty)) {
        subjects.add(bound.ty)
    }
    let unknown = Ty(db, UnknownTy(UnknownReason.GenericBoundsLimit))
    // Discard partial constraints: even a currently unique member may acquire another overload.
    subjects.toArray().map { one => TyBound(one, [unknown]) }
}

/**
 * The reason a parameter's bounds are unknown after bounded expansion, if they are.
 */
func incompleteBoundsOf(db: AnalysisDatabase, ty: Ty): ?Ty {
    if (let ParamTy(owner, _) <- ty.kind(db)) {
        for (bound in genericBounds(db, owner) where bound.ty == ty) {
            for (
                upper in bound.bounds where upper.kind(db) ==
                    UnknownTy(UnknownReason.GenericBoundsLimit)
            ) {
                return upper
            }
        }
    }
    None
}

/**
 * The supertypes of `ty` one level up, as the file `from` sees them: those its declaration names,
 * its arguments substituted, then those of the `extend`s of it the file sees whose type `ty` is an
 * instance of (an `extend Box<Int64>` is not `Box<String>`'s, N86). None of a tuple, a function or
 * a type parameter.
 */
func directSupertypes(db: AnalysisDatabase, ty: Ty, from: ?SourceFile): Array<Ty> {
    let (head, named) =
        match (ty.kind(db)) {
            case DeclTy(id, args) =>
                (
                    ExtendedType.DeclType(id),
                    signatureTypes(db, id).supers.map { one => substitute(db, one, id, args) }
                )
            case PrimTy(name) => (ExtendedType.PrimType(name), Array<Ty>())
            case BuiltInTy(kind, _) => (ExtendedType.BuiltInHead(kind), Array<Ty>())
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
    binds.map { one => one ?? Ty(db, ErrorTy) }
}

/**
 * Whether `actual` is `pattern`, a type written with the type parameters of `owner`, for some of
 * their arguments, each bound in `binds` as it is met. A type not known in `actual` matches
 * anything: it hides nothing.
 */
func matchTy(db: AnalysisDatabase, pattern: Ty, actual: Ty, owner: DefId, binds: Array<?Ty>): Bool {
    let all =
        {
            patterns: Array<Ty>, actuals: Array<Ty> =>
            patterns.size == actuals.size &&
                (0..patterns.size)
                    .iterator()
                    .all { i => matchTy(db, patterns[i], actuals[i], owner, binds) }
        }
    match ((pattern.kind(db), actual.kind(db))) {
        case (_, ErrorTy) | (_, TodoTy(_)) | (_, UnknownTy(_)) => true
        case (ParamTy(of, index), _) where of == owner && index < binds.size =>
            match (binds[index]) {
                case Some(bound) => bound == actual
                case None =>
                    binds[index] = actual
                    true
            }
        case (DeclTy(a, aArgs), DeclTy(b, bArgs)) => a == b && all(aArgs, bArgs)
        case (TupleTy(a), TupleTy(b)) => all(a, b)
        case (FuncTy(aParams, aRet, aC), FuncTy(bParams, bRet, bC)) =>
            aC == bC && all(aParams.concat([aRet]), bParams.concat([bRet]))
        case (BuiltInTy(a, aa), BuiltInTy(b, ba)) => a == b && all(aa, ba)
        case (VArrayTy(a, aSize), VArrayTy(b, bSize)) =>
            aSize == bSize && matchTy(db, a, b, owner, binds)
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
 * Whether `sub` is `sup` or one of its subtypes; `Nothing` is every type's, and a type not known
 * stands for any. A tuple's elements are covariant, a function's parameters contravariant and its
 * return type covariant (N116); a type parameter is a subtype of what its bounds are.
 */
func isSubtype(db: AnalysisDatabase, sub: Ty, sup: Ty, from: ?SourceFile): Bool {
    if (sub == sup || isAny(db, sup, from)) {
        return true
    }
    match ((sub.kind(db), sup.kind(db))) {
        case (ErrorTy, _) |
            (_, ErrorTy) |
            (TodoTy(_), _) |
            (_, TodoTy(_)) |
            (UnknownTy(_), _) |
            (_, UnknownTy(_)) => true
        case (PrimTy("Nothing"), _) => true
        case (BuiltInTy(_, _), BuiltInTy(_, _)) => isAlike(db, sub, sup)
        case (TupleTy(subs), TupleTy(sups)) =>
            subs.size == sups.size &&
                (0..subs.size).iterator().all { i => isSubtype(db, subs[i], sups[i], from) }
        case (FuncTy(subParams, subRet, subC), FuncTy(supParams, supRet, supC)) =>
            subC == supC && subParams.size == supParams.size &&
                (0..subParams.size)
                    .iterator()
                    .all { i => isSubtype(db, supParams[i], subParams[i], from) } &&
                isSubtype(db, subRet, supRet, from)
        case (ParamTy(owner, _), _) =>
            genericBounds(db, owner)
                .iterator()
                .any {
                    bound =>
                    bound.ty == sub &&
                        bound.bounds.iterator().any { one => isSubtype(db, one, sup, from) }
                }
        // of an interface implemented as several instances (`K<Int64> & K<String>`), any (N143)
        case (_, DeclTy(id, _)) =>
            let instances =
                allSupertypes(db, sub, from)
                    .filter {
                        one =>
                        match (one.kind(db)) {
                            case DeclTy(other, _) => other == id
                            case _ => false
                        }
                    }
            if (instances.isEmpty()) {
                isSupertypeKind(db, id) && hasMacroSupertypes(db, sub, from)
            } else {
                instances.iterator().any { one => isAlike(db, one, sup) }
            }
        case _ => false
    }
}

/**
 * Whether `id` is a type another may be a subtype of by its declaration or an `extend`: a class or
 * an interface.
 */
func isSupertypeKind(db: AnalysisDatabase, id: DefId): Bool {
    match (id.item(db).kind) {
        case Class | Interface => true
        case _ => false
    }
}

/**
 * `T` of `ty`, `std.core`'s `Option<T>`; `None` of any other type.
 */
func optionArgOf(db: AnalysisDatabase, ty: Ty, from: ?SourceFile): ?Ty {
    let (id, arg) =
        match (ty.kind(db)) {
            case DeclTy(id, args) where args.size == 1 && isNamed(db, id, "Option") => (id, args[0])
            case _ => return None
        }
    let pkg = packageOfFile(db, from ?? return None) ?? return None
    if (langItem(db, PackageRef.Source(pkg), LangItem.OptionEnum) == Some(id)) { arg } else { None }
}

/**
 * Whether `ty` may have supertypes the analysis does not see: a macro whose expansion is not read
 * is called on its declaration, or on one of its supertypes', and may declare it a subtype of
 * anything, or add an `extend` that does (#175, #176). Unknown, not wrong.
 */
func hasMacroSupertypes(db: AnalysisDatabase, ty: Ty, from: ?SourceFile): Bool {
    allSupertypes(db, ty, from)
        .iterator()
        .any {
            one =>
            match (one.kind(db)) {
                case DeclTy(id, _) => hasUnreadMacros(db, id)
                case _ => false
            }
        }
}

/**
 * Whether `ty` is `std.core`'s `Any`, which every type implements (N142).
 */
func isAny(db: AnalysisDatabase, ty: Ty, from: ?SourceFile): Bool {
    let id =
        match (ty.kind(db)) {
            case DeclTy(id, args) where args.isEmpty() && isNamed(db, id, "Any") => id
            case _ => return false
        }
    let file = from ?? return false
    let pkg = packageOfFile(db, file) ?? return false
    langItem(db, PackageRef.Source(pkg), LangItem.AnyInterface) == Some(id)
}

/**
 * Whether `a` and `b` are one type but where either is not known, which stands for any: type
 * arguments are invariant, but `Array<{unknown}>` hides nothing.
 */
func isAlike(db: AnalysisDatabase, a: Ty, b: Ty): Bool {
    if (a == b) {
        return true
    }
    let all =
        {
            xs: Array<Ty>, ys: Array<Ty> =>
            xs.size == ys.size && (0..xs.size).iterator().all { i => isAlike(db, xs[i], ys[i]) }
        }
    match ((a.kind(db), b.kind(db))) {
        case (ErrorTy, _) |
            (_, ErrorTy) |
            (TodoTy(_), _) |
            (_, TodoTy(_)) |
            (UnknownTy(_), _) |
            (_, UnknownTy(_)) => true
        case (DeclTy(x, xs), DeclTy(y, ys)) => x == y && all(xs, ys)
        case (TupleTy(xs), TupleTy(ys)) => all(xs, ys)
        case (FuncTy(xs, x, xc), FuncTy(ys, y, yc)) => xc == yc && all(xs, ys) && isAlike(db, x, y)
        case (BuiltInTy(a, aa), BuiltInTy(b, ba)) => a == b && all(aa, ba)
        case (VArrayTy(x, xn), VArrayTy(y, yn)) => xn == yn && isAlike(db, x, y)
        case _ => false
    }
}

/**
 * Whether a value of the type `sub` may be given where `sup` is expected, as cjc checks it: a
 * subtype, or boxed into the `Option` (`option`, `std.core`'s) `sup` is (N111). A variable of a
 * call stands for any, as an error type does.
 */
func isAssignable(db: AnalysisDatabase, sub: Ty, sup: Ty, from: ?SourceFile, option: ?DefId): Bool {
    if (isSubtype(db, sub, sup, from)) {
        return true
    }
    match ((sub.kind(db), sup.kind(db))) {
        case (InferTy(_), _) | (_, InferTy(_)) => true
        case (_, DeclTy(id, args)) where Some(id) == option && args.size == 1 =>
            isAssignable(db, sub, args[0], from, option)
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
 * `2u8`). Of a branch of a type not known, that one: whatever the join, it is not known.
 */
func joinTys(db: AnalysisDatabase, tys: Array<Ty>, from: ?SourceFile): Ty {
    let real = tys.filter { one => !isNothing(db, one) }
    let first = real.get(0) ?? return Ty(db, PrimTy("Nothing"))
    if (let Some(unknown) <- unknownOf(db, real.filter { one => isUnknown(db, one) })) {
        return unknown
    }
    if (real.iterator().all { one => one == first }) {
        return first
    }
    // `?T` and what is a `T`: `?T`, the others boxed (N144, #249)
    for (one in real) {
        let inner = optionArgOf(db, one, from) ?? continue
        if (real.iterator().all { other => other == one || isSubtype(db, other, inner, from) }) {
            return one
        }
    }
    // of a branch whose supertypes a macro may add to, the common one is not known (#175)
    if (real.iterator().any { one => hasMacroSupertypes(db, one, from) }) {
        return Ty(db, TodoTy(Todo.MacroMember))
    }
    let common =
        allSupertypes(db, first, from)
            .filter {
                candidate =>
                real.iterator().all { one => isSubtype(db, one, candidate, from) }
            }
    let least =
        common
            .filter {
                candidate =>
                common.iterator().all { other => isSubtype(db, candidate, other, from) }
            }
    if (least.size == 1) { least[0] } else { Ty(db, ErrorTy) }
}

/**
 * The type `ty`, written in the member `member`, as a member of a value of the type `recv`: the
 * type parameters of the type or `extend` it is in replaced by `recv`'s arguments as an instance of
 * it, `This` by `recv` (N88); `None` for a member of an `extend` `recv` is no instance of (N86).
 */
public func asMemberOf(
    db: AnalysisDatabase,
    ty: Ty,
    member: DefId,
    recv: Ty,
    from: ?SourceFile
): ?Ty {
    let owner = parentOf(db, member) ?? return ty
    let args = ownerArgs(db, owner, recv, from) ?? return None
    let applied = substitute(db, ty, owner, args)
    if (applied.kind(db) == ThisTy) { recv } else { applied }
}

/**
 * The arguments of the type parameters of `owner`, a type or an `extend`, `recv` gives them;
 * `None` for an `extend` of a type `recv` is no instance of.
 */
func ownerArgs(db: AnalysisDatabase, owner: DefId, recv: Ty, from: ?SourceFile): ?Array<Ty> {
    if (owner.item(db).kind == ItemKind.Extend) {
        let extended = signatureTypes(db, owner).ty ?? return None
        let instance =
            match (extended.kind(db)) {
                case DeclTy(id, _) => asInstanceOf(db, recv, id, from) ?? return None
                case _ => recv
            }
        return extendArgs(db, owner, instance)
    }
    match (asInstanceOf(db, recv, owner, from).map { one => one.kind(db) }) {
        case Some(DeclTy(_, args)) => return args
        case _ => ()
    }
    // of a type parameter, its bound's that is an instance of `owner` (`T <: FromJson<T>`'s `fromJson`)
    if (let ParamTy(param, _) <- recv.kind(db)) {
        for (bound in genericBounds(db, param) where bound.ty == recv) {
            for (one in bound.bounds) {
                if (
                    let Some(DeclTy(_, args)) <- asInstanceOf(db, one, owner, from)
                        .map { it => it.kind(db) }
                ) {
                    return args
                }
            }
        }
    }
    // a member of a type the value is no instance of: a `.cjo` cjc checked; its arguments unknown
    genericsOf(db, owner).map { _ => Ty(db, ErrorTy) }
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
    substitute(db, ty, owner, Array(count) { _ => Ty(db, ErrorTy) })
}
