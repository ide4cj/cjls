package loupe.hir

import std.collection.*
import calca.*
import calca.macros.*
import index_map.IndexMap
import loupe.db.{AnalysisDatabase, SourceFile}

/**
 * The types and `extend`s of a package, by each declaration they name as a supertype: the edges of the
 * hierarchy down from it, a package's (#389). Those of the macro calls' expansions included, as
 * `packageExtends` has them.
 */
@CalcaTracked
public func packageSubtypes(db: AnalysisDatabase, pkg: PackageRef): IndexMap<DefId, Array<DefId>> {
    let found = IndexMap<DefId, ArrayList<DefId>>()
    let files = filesOf(db, pkg)
    for (
        file in files
            .concat(files |> flatMap { one: ItemFile => expansionsOf(db, one) } |> collectArray)
    ) {
        for (item in itemTreeOf(db, file).items where isSubtypeItem(item.kind)) {
            let def = DefId(db, file, item.id)
            // each a declaration: `supertypes` resolves no type of the language
            for (one in supertypes(db, def)) {
                if (let DeclType(sup) <- one) {
                    if (let Some(list) <- found.get(sup)) {
                        list.add(def)
                    } else {
                        found[sup] = ArrayList<DefId>([def])
                    }
                }
            }
        }
    }
    IndexMap<DefId, Array<DefId>>(found.toArray().map { entry => (entry[0], entry[1].toArray()) })
}

func isSubtypeItem(kind: ItemKind): Bool {
    match (kind) {
        case Class | Interface | Struct | Enum | Extend => true
        case _ => false
    }
}

/**
 * The members `member`, a function or a property, overrides or implements, the nearest first: those of
 * its supertypes, those an `extend` its file sees adds included (`allSupertypes`), of its name, its
 * kind, as static as it is, and of its parameters seen on its type (N107, `paramOn` of a generic
 * supertype), its own type parameters unknown. Never by `override` or `redef`, which cjc requires of
 * none. Nothing for any other declaration.
 */
@CalcaTracked
public func overriddenMembers(db: AnalysisDatabase, member: DefId): Array<DefId> {
    let shape = MemberShape.of(db, member) ?? return []
    let recv = selfTyAround(db, member) ?? return []
    let from = sourceFileOf(db, member)
    let own = shape.paramsOn(db, member, recv, from)
    let found = ArrayList<DefId>()
    // the supertypes but the type itself, each an instance of a declaration
    for (sup in allSupertypes(db, recv, from)[1..]) {
        if (let DeclTy(id, _) <- sup.kind(db)) {
            for (candidate in membersOfItem(db, id, shape.name)) {
                if (
                    let MemberDecl(other) <- candidate && other != member &&
                        !found.contains(other) &&
                        shape.isAlike(db, other) &&
                        shape.paramsOn(db, other, recv, from) == own
                ) {
                    found.add(other)
                }
            }
        }
    }
    found.toArray()
}

/**
 * The members overriding or implementing `member`, a function or a property, by `overriddenMembers`'s
 * rule: those of its type's subtypes, and of the `extend`s declaring one (the extended type's own and
 * those of its `extend`s the `extend` sees, which implement as well), the subtypes of those in turn,
 * found in the packages that may import the declaring one (`importersOf`). In the order the subtypes are
 * met, level by level.
 */
@CalcaTracked
public func overridingMembers(db: AnalysisDatabase, member: DefId): Array<DefId> {
    let shape = MemberShape.of(db, member) ?? return []
    let found = ArrayList<DefId>()
    for (sub in subtypesOf(db, parentOf(db, member) ?? return [])) {
        let from = sourceFileOf(db, sub)
        let (recv, holders) =
            if (sub.item(db).kind == ItemKind.Extend) {
                let extended = extendedTypeOf(db, sub) ?? continue
                let ownHolders =
                    match (extended) {
                        case DeclType(id) => [id]
                        case PrimType(_) => Array<DefId>()
                    }
                (
                    signatureTypes(db, sub).ty ?? continue,
                    ownHolders.concat(extendsOf(db, extended, from))
                )
            } else {
                (selfTyOf(db, sub), [sub])
            }
        let wanted = shape.paramsOn(db, member, recv, from)
        for (holder in holders) {
            for (candidate in membersOfItem(db, holder, shape.name)) {
                if (
                    let MemberDecl(other) <- candidate && other != member &&
                        !found.contains(other) &&
                        shape.isAlike(db, other) &&
                        shape.paramsOn(db, other, recv, from) == wanted
                ) {
                    found.add(other)
                }
            }
        }
    }
    found.toArray()
}

/**
 * The types and `extend`s below the type `ty`, level by level, each once: those naming it as a
 * supertype (`packageSubtypes`) in the packages that may import its (`importersOf`), then those below
 * each, the type an `extend` extends standing for it. Nothing for `ty` of no package.
 */
public func subtypesOf(db: AnalysisDatabase, ty: DefId): Array<DefId> {
    let packages = importersOf(db, packageRefOf(db, ty) ?? return [])
    let found = ArrayList<DefId>()
    let seen = HashSet<DefId>([ty])
    var level = [ty]
    while (!level.isEmpty()) {
        let next = ArrayList<DefId>()
        for (one in level) {
            for (pkg in packages) {
                for (sub in packageSubtypes(db, pkg).get(one) ?? []) {
                    if (!seen.add(sub)) {
                        continue
                    }
                    found.add(sub)
                    // below an `extend`, what is below the type it extends
                    let below =
                        if (sub.item(db).kind == ItemKind.Extend) {
                            match (extendedTypeOf(db, sub)) {
                                case Some(DeclType(id)) => id
                                case _ => continue
                            }
                        } else {
                            sub
                        }
                    if (below == sub || seen.add(below)) {
                        next.add(below)
                    }
                }
            }
        }
        level = next.toArray()
    }
    found.toArray()
}

/**
 * The packages that may import `pkg`, it first: of the modules whose deps may hold its module
 * (`PackageIndex.scopes`), and the binaries of its owner for a binary, which import one another. A superset
 * of its transitive importers, which every type below one of its declarations is in.
 */
public func importersOf(db: AnalysisDatabase, pkg: PackageRef): Array<PackageRef> {
    let index = packageIndex(db)
    let owner = index.owners.get(pkg) ?? return [pkg]
    let found = ArrayList<PackageRef>([pkg])
    for ((one, oneOwner) in index.owners where one != pkg) {
        let imports =
            match (one) {
                case Source(_) => index.scopes.get(oneOwner)?.contains(owner) ?? false
                case Binary(_) => oneOwner == owner && pkg.isBinary()
            }
        if (imports) {
            found.add(one)
        }
    }
    found.toArray()
}

extend PackageRef {
    func isBinary(): Bool {
        match (this) {
            case Binary(_) => true
            case Source(_) => false
        }
    }
}

/**
 * What a member overriding another has of it: its name, its kind, a function or a property, and whether
 * it is static.
 */
struct MemberShape {
    MemberShape(let name: String, let kind: ItemKind, let isStatic: Bool) {}

    /**
     * That of `member`; `None` for a declaration other than a function or a property of a type or an
     * `extend`.
     */
    static func of(db: AnalysisDatabase, member: DefId): ?MemberShape {
        let kind = member.item(db).kind
        if (kind != ItemKind.Func && kind != ItemKind.Prop) {
            return None
        }
        let item = memberItemOf(db, member) ?? return None
        MemberShape(item.names.get(0) ?? return None, kind, item.has(Modifier.Static))
    }

    /**
     * Whether `other`, of the name, is of the kind and as static.
     */
    func isAlike(db: AnalysisDatabase, other: DefId): Bool {
        other.item(db).kind == kind &&
            (memberItemOf(db, other)?.has(Modifier.Static) ?? false) == isStatic
    }

    /**
     * The types of the parameters of `member`, seen on `recv` from `from` (`asMemberOf`), its own type
     * parameters unknown; none of a property.
     */
    func paramsOn(db: AnalysisDatabase, member: DefId, recv: Ty, from: ?SourceFile): Array<Ty> {
        if (kind != ItemKind.Func) {
            return []
        }
        signatureTypes(db, member)
            .params
            .map {
                one =>
                eraseParams(db, asMemberOf(db, one, member, recv, from) ?? Ty(db, ErrorTy), member)
            }
    }
}

/**
 * The item of `member`, a member of a type or an `extend`.
 */
func memberItemOf(db: AnalysisDatabase, member: DefId): ?Item {
    let parent = itemOf(db, parentOf(db, member) ?? return None) ?? return None
    let id = member.item(db)
    parent.members.iterator().filter { one => one.id == id }.next()
}
