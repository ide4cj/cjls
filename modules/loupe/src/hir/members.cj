package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import index_map.IndexMap
import loupe.db.{AnalysisDatabase, Package}

/**
 * A type an `extend` extends: one declared, or a type of the language by its keyword (`Int64`).
 */
@Derive[Equatable, Hashable]
public enum ExtendedType <: ToString {
    | DeclType(DefId)
    | PrimType(String)

    public func toString(): String {
        match (this) {
            case DeclType(id) => id.toString()
            case PrimType(name) => name
        }
    }
}

/**
 * The type the `extend` `def` extends, its path resolved in its scope; `None` for one that does not
 * resolve to a type.
 */
public func extendedTypeOf(db: AnalysisDatabase, def: DefId): ?ExtendedType {
    let sig = signature(db, def)
    let ty = sig.ty ?? return None
    match (sig[ty]) {
        case PathRef(segments) => typeOfPath(db, def, segments).map {id => ExtendedType.DeclType(id)}
        case PrimRef(name) => ExtendedType.PrimType(name)
        case _ => None
    }
}

/**
 * The type the path `segments`, written in the signature of `def`, names; `None` for a type
 * parameter, an ambiguity, or nothing.
 */
func typeOfPath(db: AnalysisDatabase, def: DefId, segments: Array<TypeSegment>): ?DefId {
    let scope = typeScopeOf(db, def) ?? return None
    let found = resolveTypePath(db, scope, segments.map {segment => segment.name})
    match (found.get(found.size - 1)) {
        case Some(Resolved(TypeOf(id))) => id
        case _ => None
    }
}

/**
 * The `extend`s of a source package, by the type each extends.
 */
@CalcaTracked
public func packageExtends(db: AnalysisDatabase, pkg: Package): IndexMap<ExtendedType, Array<DefId>> {
    let found = IndexMap<ExtendedType, ArrayList<DefId>>()
    for (file in filesOf(db, PackageRef.Source(pkg))) {
        for (item in itemTreeOf(db, file).items where item.kind == ItemKind.Extend) {
            let def = DefId(db, file, item.id)
            if (let Some(ty) <- extendedTypeOf(db, def)) {
                if (let Some(list) <- found.get(ty)) {
                    list.add(def)
                } else {
                    found[ty] = ArrayList<DefId>([def])
                }
            }
        }
    }
    IndexMap<ExtendedType, Array<DefId>>(found.toArray().map {entry => (entry[0], entry[1].toArray())})
}

/**
 * The type a declaration is a member of, directly or through the `extend` it is in; `None` for one
 * of no type.
 */
public func enclosingTypeOf(db: AnalysisDatabase, def: DefId): ?ExtendedType {
    let parent = parentOf(db, def) ?? return None
    match (parent.item(db).kind) {
        case Extend => extendedTypeOf(db, parent)
        case Class | Interface | Struct | Enum => ExtendedType.DeclType(parent)
        case _ => None
    }
}

/**
 * What a name of the type a body is in stands for: a declaration among its members, or a member
 * parameter of its primary constructor (N69).
 */
@Derive[Equatable, Hashable]
public enum MemberTarget <: ToString {
    | MemberDecl(DefId)
    /**
     * A `let` or `var` parameter of a primary constructor: the constructor, and the parameter's
     * local in its body.
     */
    | MemberParam(DefId, LocalId)

    public func toString(): String {
        match (this) {
            case MemberDecl(id) => id.toString()
            case MemberParam(id, local) => "${id} ${local}"
        }
    }
}

/**
 * The level of members of the type around the body of `def`, as seen from its package: its own,
 * its `extend`s', then its supertypes' and theirs, level by level, the nearest that has `name`
 * deciding but for functions, which gather over the levels (N69, N70). A private member of a
 * supertype is found too: cjc finds it, then says it cannot be accessed.
 *
 * The `extend`s are those of the body's package and of the type's; those of another package,
 * seen through an interface it imports, are member lookup's (step 7).
 */
public func membersNamed(db: AnalysisDatabase, def: DefId, name: String): Array<MemberTarget> {
    let start = enclosingTypeOf(db, def) ?? return []
    let from = match (def.file(db)) {
        case Source(file) => packageOfFile(db, file)
        case Binary(_, _) => None<Package>
    }
    let funcs = ArrayList<MemberTarget>()
    let seen = HashSet<ExtendedType>([start])
    var level = [start]
    while (!level.isEmpty()) {
        let found = ArrayList<MemberTarget>()
        let next = ArrayList<ExtendedType>()
        for (ty in level) {
            let extends = extendsOf(db, ty, from)
            found.add(all: ownMembersNamed(db, ty, name))
            for (ext in extends) {
                found.add(all: membersOfItem(db, ext, name))
            }
            for (one in supertypesOf(db, ty).concat(extends |> flatMap {ext: DefId => supertypesOfExtend(db, ext)} |> collectArray)
                where !seen.contains(one)) {
                seen.add(one)
                next.add(one)
            }
        }
        if (!found.isEmpty()) {
            let nonFuncs = found.iterator().any {target => !isFuncMember(db, target)}
            if (funcs.isEmpty() && nonFuncs) {
                return found.toArray()
            }
            for (target in found where isFuncMember(db, target) && !funcs.contains(target)) {
                funcs.add(target)
            }
            if (nonFuncs) {
                break
            }
        }
        level = next.toArray()
    }
    funcs.toArray()
}

func isFuncMember(db: AnalysisDatabase, target: MemberTarget): Bool {
    match (target) {
        case MemberDecl(id) => id.item(db).kind == ItemKind.Func
        case MemberParam(_, _) => false
    }
}

/**
 * The `extend`s of `ty` in the package `from` and in the type's own, if it is a source package's.
 */
func extendsOf(db: AnalysisDatabase, ty: ExtendedType, from: ?Package): Array<DefId> {
    let pkgs = ArrayList<Package>()
    if (let Some(one) <- from) {
        pkgs.add(one)
    }
    if (let DeclType(id) <- ty && let Source(file) <- id.file(db)) {
        if (let Some(own) <- packageOfFile(db, file) && !pkgs.contains(own)) {
            pkgs.add(own)
        }
    }
    pkgs |> flatMap {pkg: Package => packageExtends(db, pkg).get(ty) ?? []} |> collectArray
}

/**
 * The members of the declaration `ty` named `name`; none for a type of the language, whose members
 * are its `extend`s'.
 */
func ownMembersNamed(db: AnalysisDatabase, ty: ExtendedType, name: String): Array<MemberTarget> {
    match (ty) {
        case DeclType(id) => membersOfItem(db, id, name)
        case PrimType(_) => []
    }
}

/**
 * The members of the item of `id` named `name`, a type's or an `extend`'s, and the member
 * parameters of its primary constructor; never a constructor.
 */
func membersOfItem(db: AnalysisDatabase, id: DefId, name: String): Array<MemberTarget> {
    let item = itemOf(db, id) ?? return []
    let file = id.file(db)
    let found = ArrayList<MemberTarget>()
    for (member in item.members) {
        match (member.kind) {
            case Init | Finalizer | Extend | MacroCall => ()
            case PrimaryInit =>
                let ctor = DefId(db, file, member.id)
                let lowered = body(db, ctor)
                for (param in lowered.params where param.isMember) {
                    if (let Some(local) <- param.local && lowered[local].name == name) {
                        found.add(MemberTarget.MemberParam(ctor, local))
                    }
                }
            case _ => if (member.names.contains(name)) {
                found.add(MemberTarget.MemberDecl(DefId(db, file, member.id)))
            }
        }
    }
    found.toArray()
}

/**
 * The types the declaration `ty` inherits from: as its signature writes them, resolved, or as its
 * `.cjo` has them.
 */
func supertypesOf(db: AnalysisDatabase, ty: ExtendedType): Array<ExtendedType> {
    let id = match (ty) {
        case DeclType(id) => id
        case PrimType(_) => return []
    }
    match (id.file(db)) {
        case Source(_) => supertypesOfExtend(db, id)
        case Binary(pkg, index) => binarySupertypes(db, pkg, BinaryItem(index, id.item(db))).map {
            one => ExtendedType.DeclType(one)
        }
    }
}

/**
 * The types after `<:` in the signature of the source declaration `def`, a type or an `extend`,
 * resolved.
 */
func supertypesOfExtend(db: AnalysisDatabase, def: DefId): Array<ExtendedType> {
    let sig = signature(db, def)
    sig.supers |> filterMap {
        ty: TypeRefId => match (sig[ty]) {
            case PathRef(segments) => typeOfPath(db, def, segments).map {id => ExtendedType.DeclType(id)}
            case _ => None
        }
    } |> collectArray
}
