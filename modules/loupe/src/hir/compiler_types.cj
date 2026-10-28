package loupe.hir

import std.deriving.*
import loupe.db.{AnalysisDatabase, Package}

/** Compiler-owned type heads; declaration identities only provide scoped names and navigation. */
@Derive[Equatable, Hashable]
public enum CompilerType <: ToString {
    | PointerType
    | CStringType
    | RawArrayType
    | CFuncType
    | VArrayType

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

/** The compiler-owned head a scoped BuiltIn declaration names, independent of its origin. */
public func compilerTypeOf(db: AnalysisDatabase, def: DefId): ?CompilerType {
    if (def.item(db).kind != ItemKind.BuiltIn) {
        return None
    }
    let name = itemOf(db, def).flatMap { one => one.names.get(0) } ?? return None
    COMPILER_TYPES.iterator().filter { one => one.toString() == name }.next()
}

/** cjc injects these declarations only while compiling std.core; RawArray stays internal. */
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

func compilerGenerics(kind: CompilerType): Array<String> {
    match (kind) {
        case CStringType => []
        case _ => ["T"]
    }
}

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

func compilerSignature(db: AnalysisDatabase, def: DefId, pkg: Package): SignatureTypes {
    let kind = compilerTypeOf(db, def) ?? return SignatureTypes()
    let names = compilerGenerics(kind)
    let args = Array(names.size) { i => Ty(db, ParamTy(def, i)) }
    let bounds =
        if (kind == PointerType) {
            let ctypes = defMap(db, PackageRef.Source(pkg)).names.get("CType") ?? []
            ctypes.map { one => TyBound(args[0], [Ty(db, DeclTy(one.id, []))]) }
        } else {
            Array<TyBound>()
        }
    SignatureTypes(generics: names, ty: compilerTy(db, kind, args), bounds: bounds)
}
