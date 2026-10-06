package loupe.hir

import std.collection.*
import std.deriving.*
import loupe.db.{AnalysisDatabase, Package}

/**
 * What the left of a `.` in a body stands for, as far as names tell (N75–N79).
 */
@Derive[Equatable]
public enum Receiver <: ToString {
    /**
     * A package the file imports by its name or an alias (N76).
     */
    | PackageReceiver(PackageRef)
    /**
     * Types whose members follow: a type named (N77), a type parameter's bounds (N78), the type
     * `this` or `super` is (N79).
     */
    | TypesReceiver(Array<ExtendedType>)
    /**
     * A value: its type says what follows, which is inference's (N75).
     */
    | ValueReceiver
    /**
     * Nothing, or an ambiguity.
     */
    | NoReceiver

    public func toString(): String {
        match (this) {
            case PackageReceiver(pkg) => "package ${pkg}"
            case TypesReceiver(types) => "types ${types}"
            case ValueReceiver => "value"
            case NoReceiver => "nothing"
        }
    }
}

/**
 * What the name after a `.` in a body means.
 */
@Derive[Equatable]
public enum FieldResolution <: ToString {
    /**
     * Declarations of a package, a type or a value, never a constructor (N76).
     */
    | PackageMembers(Array<DefId>)
    /**
     * Members of a type, functions overloading one another over its levels (N77–N79).
     */
    | TypeMembers(Array<MemberTarget>)
    /**
     * A member of a value, which its type tells: not yet (N75).
     */
    | OfValue
    | NoField

    public func toString(): String {
        match (this) {
            case PackageMembers(ids) => "package members ${ids}"
            case TypeMembers(targets) => "type members ${targets}"
            case OfValue => "of a value"
            case NoField => "nothing"
        }
    }
}

/**
 * What the name after the `.` of `expr`, a `FieldExpr` of the body of `def`, means: a declaration of
 * the package before it (N76), or a member of the types before it (N77–N79); after a value, what its
 * type has, not yet (N75).
 */
public func resolveField(db: AnalysisDatabase, def: DefId, expr: ExprId): FieldResolution {
    let (receiver, name) = match (body(db, def)[expr]) {
        case FieldExpr(receiver, name, _) => (receiver, name)
        case _ => return FieldResolution.NoField
    }
    match (receiverOf(db, def, receiver)) {
        case PackageReceiver(pkg) =>
            let from = packageOf(db, def) ?? return FieldResolution.NoField
            let relation = relationOf(from.name(db), nameOf(db, pkg))
            let ids = visibleOf(packageExports(db, pkg).names.get(name) ?? [], relation, Visibility.Private)
            if (ids.isEmpty()) {
                FieldResolution.NoField
            } else {
                FieldResolution.PackageMembers(ids)
            }
        case TypesReceiver(types) =>
            let targets = memberLookup(db, types, name, from: sourceFileOf(db, def))
            if (targets.isEmpty()) {
                FieldResolution.NoField
            } else {
                FieldResolution.TypeMembers(targets)
            }
        case ValueReceiver => FieldResolution.OfValue
        case NoReceiver => FieldResolution.NoField
    }
}

/**
 * What `expr`, the left of a `.` in the body of `def`, stands for. A name is looked up as any other
 * of the body: a value of its name hides a package or a type (N75).
 */
public func receiverOf(db: AnalysisDatabase, def: DefId, expr: ExprId): Receiver {
    match (body(db, def)[expr]) {
        case PathExpr(name, _) => match (resolveBodyName(db, def, exprScopes(db, def).scopeOf(expr), name)) {
            case Values(targets) => match (targets.get(0)) {
                case Some(TypeParamOf(target)) where targets.size == 1 => TypesReceiver(boundsOf(db, target))
                case _ => ValueReceiver
            }
            case InFile(Found(ids)) => receiverOfDecl(db, ids[0])
            case InFile(FoundPackage(pkg)) => PackageReceiver(pkg)
            case InFile(Ctors(_, _)) => ValueReceiver
            case InFile(_) => NoReceiver
        }
        case FieldExpr(_, _, _) => match (resolveField(db, def, expr)) {
            case PackageMembers(ids) => receiverOfDecl(db, ids[0])
            case TypeMembers(_) | OfValue => ValueReceiver
            case NoField => NoReceiver
        }
        case PrimExpr(name) => TypesReceiver([PrimType(name)])
        case ThisExpr => match (enclosingTypeOf(db, def)) {
            case Some(ty) => TypesReceiver([ty])
            case None => NoReceiver
        }
        case SuperExpr => match (superclassOf(db, def)) {
            case Some(ty) => TypesReceiver([ty])
            case None => NoReceiver
        }
        case MissingExpr => NoReceiver
        case _ => ValueReceiver
    }
}

/**
 * The declaration `id` as the left of a `.`: a type, an alias of one, else a value.
 */
func receiverOfDecl(db: AnalysisDatabase, id: DefId): Receiver {
    match (id.item(db).kind) {
        case Class | Interface | Struct | Enum | BuiltIn => TypesReceiver([DeclType(id)])
        case TypeAlias => match (extendedTypeOf(db, id)) {
            case Some(ty) => TypesReceiver([ty])
            case None => NoReceiver
        }
        case _ => ValueReceiver
    }
}

/**
 * The superclass of the class the body of `def` is in: the class among its supertypes, else
 * `std.core`'s `Object` (N79).
 */
func superclassOf(db: AnalysisDatabase, def: DefId): ?ExtendedType {
    let ty = enclosingTypeOf(db, def) ?? return None
    let id = match (ty) {
        case DeclType(id) where id.item(db).kind == ItemKind.Class => id
        case _ => return None
    }
    for (one in supertypes(db, id)) {
        if (let DeclType(other) <- one && other.item(db).kind == ItemKind.Class) {
            return one
        }
    }
    let pkg = packageOf(db, def) ?? return None
    let core = packageIndex(db).find("std.core", from: PackageRef.Source(pkg)) ?? return None
    let objects = packageExports(db, core).names.get("Object") ?? []
    objects.iterator().filter {one => one.id.item(db).kind == ItemKind.Class}.next().map {
        one => ExtendedType.DeclType(one.id)
    }
}

/**
 * The types the `where` of its declaration bounds the type parameter `target` by (N78).
 */
func boundsOf(db: AnalysisDatabase, target: TypeTarget): Array<ExtendedType> {
    match (target) {
        case GenericOf(owner, index) =>
            let sig = signature(db, owner)
            let name = sig.generics.get(index) ?? return []
            let found = ArrayList<ExtendedType>()
            for (bound in sig.bounds where isNamed(sig[bound.ty], name)) {
                for (one in bound.bounds) {
                    if (let PathRef(segments) <- sig[one] && let Some(id) <- typeOfPath(db, owner, segments)) {
                        found.add(DeclType(id))
                    }
                }
            }
            found.toArray()
        case LocalGenericOf(owner, localFunc, index) =>
            let lowered = body(db, owner)
            let fn = lowered.funcs.get(localFunc) ?? return []
            let name = fn.generics.get(index) ?? return []
            let found = ArrayList<ExtendedType>()
            for (bound in fn.bounds where isNamed(lowered.types[bound.ty.index], name)) {
                for (one in bound.bounds) {
                    if (let PathRef(segments) <- lowered.types[one.index]) {
                        let path = resolveBodyTypePath(db, owner, one, segments.map {segment => segment.name})
                        if (let Some(Resolved(TypeOf(id))) <- path.get(path.size - 1)) {
                            found.add(DeclType(id))
                        }
                    }
                }
            }
            found.toArray()
        case _ => []
    }
}

/**
 * Whether `ty` is the lone name `name`, a type parameter as a `where` writes it.
 */
func isNamed(ty: TypeRef, name: String): Bool {
    match (ty) {
        case PathRef(segments) => segments.size == 1 && segments[0].name == name
        case _ => false
    }
}
