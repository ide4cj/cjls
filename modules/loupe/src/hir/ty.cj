package loupe.hir

import std.deriving.*
import calca.*
import calca.macros.*
import loupe.db.AnalysisDatabase

/**
 * A type as inference takes it, rust-analyzer's `Ty`: its names resolved, its aliases expanded,
 * `?T` an `Option<T>`. Interned (D54), as R1's and cjc's are (`TypeManager` hands out one `Ty` for
 * one declaration and arguments): two equal types are one id, compared and hashed as a number.
 */
@CalcaInterned
public struct Ty {
    public let kind: TyKind

    /**
     * The type as cjc writes it in a message: `Array<Int64>`, `(Int64) -> Unit`, `{unknown}` for
     * an error and for one the analysis cannot find alike.
     */
    public func text(db: AnalysisDatabase): String {
        let list = {tys: Array<Ty> => String.join(tys.map {one => one.text(db)}, delimiter: ", ")}
        match (kind(db)) {
            case PrimTy(name) => name
            case DeclTy(def, args) =>
                let name = itemOf(db, def).flatMap {item => item.names.get(0)} ?? "{unknown}"
                if (args.isEmpty()) {
                    name
                } else {
                    "${name}<${list(args)}>"
                }
            case TupleTy(elements) => "(${list(elements)})"
            case FuncTy(params, ret, isC) where isC => "CFunc<(${list(params)}) -> ${ret.text(db)}>"
            case FuncTy(params, ret, _) => "(${list(params)}) -> ${ret.text(db)}"
            case VArrayTy(element, size) => "VArray<${element.text(db)}, $${size}>"
            case ParamTy(owner, index) => genericsOf(db, owner).get(index) ?? "{unknown}"
            case ThisTy => "This"
            case ErrorTy | TodoTy(_) => "{unknown}"
            case InferTy(index) => "{var ${index}}"
        }
    }
}

/**
 * What a `Ty` is: cjc's `TypeKind`s a signature can write; an error, or a type the analysis cannot
 * find; and a variable of the type arguments of a call being inferred.
 */
public enum TyKind <: Hashable & Equatable<TyKind> {
    /**
     * A type of the language by its keyword: `Int64`, `Unit`, `Nothing`.
     */
    | PrimTy(String)
    /**
     * A declaration and its type arguments: a class, interface, struct or enum, or a type of the
     * compiler's own (`CPointer`, `CString`, `RawArray`), each of as many arguments as it has type
     * parameters.
     */
    | DeclTy(DefId, Array<Ty>)
    | TupleTy(Array<Ty>)
    /**
     * Its parameters, its return type, and whether it is a `CFunc`.
     */
    | FuncTy(Array<Ty>, Ty, Bool)
    | VArrayTy(Ty, Int64)
    /**
     * A type parameter: the declaration it is of, and its place among them, as `GenericOf` names
     * it. A member's are its own, or its type's or `extend`'s.
     */
    | ParamTy(DefId, Int64)
    /**
     * `This`, the return type of an instance function of a class (N88): the type of whatever it is
     * called on.
     */
    | ThisTy
    /**
     * An error the user made, which cjc reports, and what is made of it: a type that does not
     * resolve or is not allowed where it is written, a value that is not, a call that fits none;
     * cjc's `InvalidTy`, ty's `Unknown` (D76). It fits any type, as each of a check of it would be
     * an error cjc does not report.
     */
    | ErrorTy
    /**
     * A type the analysis cannot find, why, and what is made of it, where cjc may well find one:
     * ty's `Todo` (D76). It fits any type, as an error does, and is never an error itself.
     */
    | TodoTy(Todo)
    /**
     * A type argument of a call not written, while the call is inferred (D57): cjc's placeholder
     * `TyVar`. Never in an `InferenceResult`: what is not solved is an error type.
     */
    | InferTy(Int64)

    // by hand: `@Derive[Hashable]` hashes each field, and std's `Array` is not `Hashable`
    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        match (this) {
            case PrimTy(name) =>
                hasher.write(0)
                hasher.write(name)
            case DeclTy(def, args) =>
                hasher.write(1)
                hasher.write(def.hashCode())
                hasher.write(hashOf(args))
            case TupleTy(elements) =>
                hasher.write(2)
                hasher.write(hashOf(elements))
            case FuncTy(params, ret, isC) =>
                hasher.write(3)
                hasher.write(hashOf(params))
                hasher.write(ret.hashCode())
                hasher.write(isC)
            case VArrayTy(element, size) =>
                hasher.write(4)
                hasher.write(element.hashCode())
                hasher.write(size)
            case ParamTy(owner, index) =>
                hasher.write(5)
                hasher.write(owner.hashCode())
                hasher.write(index)
            case ThisTy => hasher.write(6)
            case ErrorTy => hasher.write(7)
            case InferTy(index) =>
                hasher.write(8)
                hasher.write(index)
            case TodoTy(why) =>
                hasher.write(9)
                hasher.write(why.hashCode())
        }
        hasher.finish()
    }

    public operator func ==(other: TyKind): Bool {
        match ((this, other)) {
            case (PrimTy(a), PrimTy(b)) => a == b
            case (DeclTy(a, aArgs), DeclTy(b, bArgs)) => a == b && aArgs == bArgs
            case (TupleTy(a), TupleTy(b)) => a == b
            case (FuncTy(aParams, aRet, aC), FuncTy(bParams, bRet, bC)) => aParams == bParams && aRet == bRet && aC == bC
            case (VArrayTy(a, aSize), VArrayTy(b, bSize)) => a == b && aSize == bSize
            case (ParamTy(a, aIndex), ParamTy(b, bIndex)) => a == b && aIndex == bIndex
            case (ThisTy, ThisTy) => true
            case (ErrorTy, ErrorTy) => true
            case (TodoTy(a), TodoTy(b)) => a == b
            case (InferTy(a), InferTy(b)) => a == b
            case _ => false
        }
    }

    public operator func !=(other: TyKind): Bool {
        !(this == other)
    }
}

/**
 * Why the analysis cannot find a type (D76): what it does not do yet, each a gap of its own.
 */
@Derive[Equatable, Hashable]
public enum Todo <: ToString {
    /**
     * The value of a call of a macro whose expansion is not read: a user's (#176), std's not known
     * (N136), or one not found, which `--test` may make visible (#255).
     */
    | MacroCall
    /**
     * A member of a type a macro is called on, or a name a file's macros may declare: what the
     * expansion would add is not read (D47, #176).
     */
    | MacroMember
    /**
     * A type of a `.cjo` that is not read: of a format newer than the one vendored, or of a file
     * cjc wrote broken (D38).
     */
    | BinaryType
    /**
     * A type the language means of std's (`String`, `Array`, `Option`, D66) where no std is found.
     */
    | NoStd
    /**
     * A type parameter of a local function: not lowered to a `Ty` yet (D55).
     */
    | LocalGeneric
    /**
     * A call that fits none of the overloads it names, by name, of a default value or variadic:
     * arguments are matched to parameters by their count and place alone yet (#254).
     */
    | ArgMatching
    /**
     * An expression inference does not reach.
     */
    | NotInferred

    public func toString(): String {
        match (this) {
            case MacroCall => "macro call"
            case MacroMember => "macro member"
            case BinaryType => "binary type"
            case NoStd => "no std"
            case LocalGeneric => "local generic"
            case ArgMatching => "arg matching"
            case NotInferred => "not inferred"
        }
    }
}

/**
 * Whether `ty` is of no type known: an error, or a type the analysis cannot find.
 */
public func isUnknown(db: AnalysisDatabase, ty: Ty): Bool {
    match (ty.kind(db)) {
        case ErrorTy | TodoTy(_) => true
        case _ => false
    }
}

/**
 * The hash of `tys`, in order.
 */
func hashOf(tys: Array<Ty>): Int64 {
    var hasher = DefaultHasher()
    for (one in tys) {
        hasher.write(one.hashCode())
    }
    hasher.finish()
}

/**
 * `ty` with each type parameter of `owner` replaced by its argument in `args`, as an alias is
 * expanded; one of no argument stays as it is.
 */
public func substitute(db: AnalysisDatabase, ty: Ty, owner: DefId, args: Array<Ty>): Ty {
    if (args.isEmpty()) {
        return ty
    }
    let all = {tys: Array<Ty> => tys.map {one => substitute(db, one, owner, args)}}
    match (ty.kind(db)) {
        case ParamTy(of, index) where of == owner => args.get(index) ?? ty
        case DeclTy(def, tyArgs) => Ty(db, DeclTy(def, all(tyArgs)))
        case TupleTy(elements) => Ty(db, TupleTy(all(elements)))
        case FuncTy(params, ret, isC) => Ty(db, FuncTy(all(params), substitute(db, ret, owner, args), isC))
        case VArrayTy(element, size) => Ty(db, VArrayTy(substitute(db, element, owner, args), size))
        case _ => ty
    }
}
