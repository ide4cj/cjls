package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import index_map.IndexMap
import loupe.db.{AnalysisDatabase, Package, SourceFile}

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
 * The type the `extend` `def` extends, its path resolved in its scope, or as its `.cjo` has it;
 * `None` for one that does not resolve to a type.
 */
public func extendedTypeOf(db: AnalysisDatabase, def: DefId): ?ExtendedType {
    if (let Binary(pkg, index) <- def.file(db)) {
        if (def.item(db).kind != ItemKind.Extend) {
            return None
        }
        return binaryExtendedType(db, pkg, BinaryItem(index, def.item(db)))
    }
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
 * The `extend`s of every package of the project, by the type each extends, cjc's map of them: which
 * of them a file sees is the lookup's to choose (`isExtendSeen`, D53).
 */
@CalcaTracked
public func extendsByType(db: AnalysisDatabase): IndexMap<ExtendedType, Array<DefId>> {
    let found = IndexMap<ExtendedType, ArrayList<DefId>>()
    for ((pkg, _) in packageIndex(db).owners) {
        for ((ty, ids) in packageExtends(db, pkg)) {
            if (let Some(list) <- found.get(ty)) {
                list.add(all: ids)
            } else {
                found[ty] = ArrayList<DefId>(ids)
            }
        }
    }
    IndexMap<ExtendedType, Array<DefId>>(found.toArray().map {entry => (entry[0], entry[1].toArray())})
}

/**
 * The `extend`s of a package, by the type each extends.
 */
@CalcaTracked
public func packageExtends(db: AnalysisDatabase, pkg: PackageRef): IndexMap<ExtendedType, Array<DefId>> {
    let found = IndexMap<ExtendedType, ArrayList<DefId>>()
    for (file in filesOf(db, pkg)) {
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
 * The level of members of the type around the body of `def`, as seen from its file (N69, N70):
 * `memberLookup` from that type.
 */
public func membersNamed(db: AnalysisDatabase, def: DefId, name: String): Array<MemberTarget> {
    let start = enclosingTypeOf(db, def) ?? return []
    memberLookup(db, [start], name, from: sourceFileOf(db, def))
}

/**
 * The package `def` is declared in, if it is a source package.
 */
func packageOf(db: AnalysisDatabase, def: DefId): ?Package {
    sourceFileOf(db, def).flatMap {file => packageOfFile(db, file)}
}

/**
 * The file `def` is declared in, if it is a source file.
 */
func sourceFileOf(db: AnalysisDatabase, def: DefId): ?SourceFile {
    match (def.file(db)) {
        case Source(file) => file
        case Binary(_, _) => None
    }
}

/**
 * The package `def` is declared in, of either kind; `None` for a source file of no package.
 */
func packageRefOf(db: AnalysisDatabase, def: DefId): ?PackageRef {
    match (def.file(db)) {
        case Source(file) => packageOfFile(db, file).map {pkg => PackageRef.Source(pkg)}
        case Binary(pkg, _) => PackageRef.Binary(pkg)
    }
}

/**
 * The members named `name` of the types `start`, as seen from the file `from`: their own, the
 * `extend`s' it sees (`isExtendSeen`), then their supertypes' and theirs, level by level, the
 * nearest that has `name` deciding but for functions, which gather over the levels (N69, N70, N77).
 * A member's modifiers do not hide it: cjc finds a private member of a supertype, or one of an
 * `extend` seen through an interface it does not declare, then says it cannot be accessed or is no
 * member (N80, N82).
 */
public func memberLookup(db: AnalysisDatabase, start: Array<ExtendedType>, name: String,
    from!: ?SourceFile): Array<MemberTarget> {
    let funcs = ArrayList<MemberTarget>()
    let seen = HashSet<ExtendedType>(start)
    var level = start
    while (!level.isEmpty()) {
        let found = ArrayList<MemberTarget>()
        let next = ArrayList<ExtendedType>()
        for (ty in level) {
            let extends = extendsOf(db, ty, from)
            found.add(all: ownMembersNamed(db, ty, name))
            for (ext in extends) {
                found.add(all: membersOfItem(db, ext, name))
            }
            for (one in supertypesOf(db, ty).concat(extends |> flatMap {ext: DefId => supertypes(db, ext)} |> collectArray)
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
 * The `extend`s of `ty` the file `from` sees.
 */
func extendsOf(db: AnalysisDatabase, ty: ExtendedType, from: ?SourceFile): Array<DefId> {
    let all = extendsByType(db).get(ty) ?? return []
    let viewer = from.flatMap {file => packageOfFile(db, file).map {pkg => (pkg, file)}}
    all.filter {ext => isExtendSeen(db, ext, ty, viewer)}
}

/**
 * Whether the file of `viewer`, of its package, sees the `extend` `ext` of `ty`, cjc's
 * `IsExtendAccessible`: one of its package does (N81); one of the type's package, `std.core` for a
 * type of the language, is seen wherever the type is (N81, N82, N84); one of another package, an
 * interface's (N83), where the file imports one of the interfaces it lists, and the type (N82). With
 * no file, only the type's package's are.
 */
func isExtendSeen(db: AnalysisDatabase, ext: DefId, ty: ExtendedType, viewer: ?(Package, SourceFile)): Bool {
    let extPkg = packageRefOf(db, ext) ?? return false
    if (let Some((pkg, _)) <- viewer && extPkg == PackageRef.Source(pkg)) {
        return true
    }
    let ofTypesPackage = match (ty) {
        case DeclType(id) => packageRefOf(db, id) == extPkg
        case PrimType(_) => nameOf(db, extPkg) == "std.core"
    }
    if (ofTypesPackage) {
        return true
    }
    let (pkg, file) = viewer ?? return false
    let imports = importsOf(db, pkg, file)
    let typeSeen = match (ty) {
        case DeclType(id) => isImported(db, pkg, imports, id)
        case PrimType(_) => true
    }
    typeSeen && supertypes(db, ext).iterator().any {
        one => match (one) {
            case DeclType(id) => isImported(db, pkg, imports, id)
            case PrimType(_) => false
        }
    }
}

/**
 * Whether a file of `pkg` whose level of imports is `imports` sees the declaration `id` (cjc's
 * `IsDeclAccessible`): one of its package, or one it imports by its name, an alias, a glob, its
 * package's re-export, or its package's name (`import m.i`, then `i.I`).
 */
func isImported(db: AnalysisDatabase, pkg: Package, imports: ImportLevel, id: DefId): Bool {
    let own = packageRefOf(db, id) ?? return false
    if (own == PackageRef.Source(pkg)) {
        return true
    }
    for (names in [imports.file, imports.pkg]) {
        for ((_, all) in names.names) {
            for (one in all) {
                match (one.target) {
                    case OfDecl(other) where other == id => return true
                    case OfPackage(other) where other == own => return true
                    case _ => ()
                }
            }
        }
    }
    let name = itemOf(db, id).flatMap {item => item.names.get(0)} ?? return false
    imports.names(db, name).iterator().any {
        one => match (one.target) {
            case OfDecl(other) => other == id
            case OfPackage(_) => false
        }
    }
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
 * The types the declaration `ty` inherits from; none for a type of the language.
 */
func supertypesOf(db: AnalysisDatabase, ty: ExtendedType): Array<ExtendedType> {
    match (ty) {
        case DeclType(id) => supertypes(db, id)
        case PrimType(_) => []
    }
}

/**
 * The types `def`, a type or an `extend`, inherits from: as its signature writes them, resolved,
 * or as its `.cjo` has them. A query: every name looked up in its members' bodies reads it.
 */
@CalcaTracked
public func supertypes(db: AnalysisDatabase, def: DefId): Array<ExtendedType> {
    match (def.file(db)) {
        case Source(_) =>
            let sig = signature(db, def)
            sig.supers |> filterMap {
                ty: TypeRefId => match (sig[ty]) {
                    case PathRef(segments) => typeOfPath(db, def, segments).map {id => ExtendedType.DeclType(id)}
                    case _ => None
                }
            } |> collectArray
        case Binary(pkg, index) => binarySupertypes(db, pkg, BinaryItem(index, def.item(db))).map {
            one => ExtendedType.DeclType(one)
        }
    }
}
