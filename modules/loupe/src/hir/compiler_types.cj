package loupe.hir

import loupe.db.{AnalysisDatabase, Package}
import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * Compiler-owned type heads; declaration identities only provide scoped names and navigation.
 */
@DerivePython
public enum CompilerType <: Equatable<CompilerType> & Hashable & ToString {
    | PointerType
    | CStringType
    | RawArrayType
    | CFuncType
    | VArrayType

    /**
     * Type interning compares and hashes these heads on the inference path (C12).
     */
    private prop ordinal: Int64 {
        get() {
            match (this) {
                case PointerType => 0
                case CStringType => 1
                case RawArrayType => 2
                case CFuncType => 3
                case VArrayType => 4
            }
        }
    }

    public operator func ==(other: CompilerType): Bool {
        ordinal == other.ordinal
    }

    public operator func !=(other: CompilerType): Bool {
        ordinal != other.ordinal
    }

    public func hashCode(): Int64 {
        ordinal.hashCode()
    }

    public func toString(): String {
        match (this) {
            case PointerType => "CPointer"
            case CStringType => "CString"
            case RawArrayType => "RawArray"
            case CFuncType => "CFunc"
            case VArrayType => "VArray"
        }
    }
}

let COMPILER_TYPES = [PointerType, CStringType, RawArrayType, CFuncType, VArrayType]

/**
 * The compiler-owned head a scoped BuiltIn declaration names, independent of its origin.
 */
protected func compilerTypeOf(db: AnalysisDatabase, def: DefId): ?CompilerType {
    if (def.item(db).kind != ItemKind.BuiltIn) {
        return None
    }
    let name = itemOf(db, def).flatMap { one => one.names.get(0) } ?? return None
    COMPILER_TYPES.iterator().filter { one => one.toString() == name }.next()
}

/**
 * cjc injects these declarations only while compiling std.core; RawArray stays internal.
 */
func compilerItems(): ItemTree {
    ItemTree(
        items: COMPILER_TYPES
            .map {
                kind =>
                let name = kind.toString()
                let visibility =
                    if (kind == RawArrayType) { Modifier.Internal } else { Modifier.Public }
                Item(ItemId(ItemKind.BuiltIn, name.hashCode(), 0), [name], [visibility], [], [])
            }
    )
}

/**
 * Generic parameter names shared by synthetic declarations and their signatures.
 */
func compilerGenerics(kind: CompilerType): Array<String> {
    match (kind) {
        case CStringType => []
        case _ => ["T"]
    }
}

/**
 * Lowers fitted type arguments to a semantic head; VArray requires a sized type reference.
 */
func compilerTy(db: AnalysisDatabase, kind: CompilerType, args: Array<Ty>): Ty {
    // Fixed arrays require the size carried by VArrayRef, not a generic path application.
    if (kind == VArrayType) {
        return Ty(db, ErrorTy)
    }
    if (kind == CFuncType) {
        return match (args.get(0).map { one => one.kind(db) }) {
            case Some(FuncTy(params, ret, _)) => Ty(db, FuncTy(params, ret, true))
            case _ => Ty(db, ErrorTy)
        }
    }
    Ty(db, BuiltInTy(kind, args))
}

/**
 * Synthesizes a signature in its declaring package, including CPointer's CType bound.
 */
func compilerSignature(db: AnalysisDatabase, def: DefId, pkg: Package): SignatureTypes {
    let kind = compilerTypeOf(db, def) ?? return SignatureTypes()
    let names = compilerGenerics(kind)
    let args = Array(names.size) { i => Ty(db, ParamTy(GenericOwner.Declaration(def), i)) }
    let bounds =
        if (kind == PointerType) {
            let ctypes = defMap(db, PackageRef.Source(pkg)).names.get("CType") ?? []
            ctypes.map { one => TyBound(args[0], [Ty(db, DeclTy(one.id, []))]) }
        } else {
            Array<TyBound>()
        }
    SignatureTypes(generics: names, ty: compilerTy(db, kind, args), bounds: bounds)
}
