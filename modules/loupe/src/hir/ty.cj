package loupe.hir

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
     * an error.
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
            case ErrorTy => "{unknown}"
            case InferTy(index) => "{var ${index}}"
        }
    }
}

/**
 * What a `Ty` is: cjc's `TypeKind`s a signature can write, an error, and a variable of the type
 * arguments of a call being inferred.
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
     * A type that does not resolve, or is not allowed where it is written: cjc's `InvalidTy`.
     */
    | ErrorTy
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
            case (InferTy(a), InferTy(b)) => a == b
            case _ => false
        }
    }

    public operator func !=(other: TyKind): Bool {
        !(this == other)
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
