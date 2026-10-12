package loupe.hir

import std.collection.*
import std.deriving.*
import cjsyntax.CjSyntaxNode
import cjsyntax.ast.{FuncDecl, InitDecl, PropDecl, VarDecl}
import calca.*
import calca.macros.*
import loupe.db.{AnalysisDatabase, Package, SourceFile}
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * The `common` declarations `def`, a `specific` one, completes (#318): of its package, its name and
 * its kind, put aside by its `DefMap`; for a member, those of the same name and kind among the
 * members of the declarations its type completes. None for a declaration that is not `specific`.
 */
public func commonsOf(db: AnalysisDatabase, def: DefId): Array<DefId> {
    match (parentOf(db, def)) {
        case Some(parent) =>
            let member = memberItemOf(db, parent, def) ?? return []
            if (!member.has(Modifier.Specific)) {
                return []
            }
            let found = ArrayList<DefId>()
            for (common in commonsOf(db, parent)) {
                let item = itemOf(db, common) ?? continue
                for (one in item.members where one.kind == member.kind &&
                    one.names.iterator().any {name => member.names.contains(name)}) {
                    found.add(DefId(db, common.file(db), one.id))
                }
            }
            found.toArray()
        case None =>
            let item = itemOf(db, def) ?? return []
            if (!item.has(Modifier.Specific)) {
                return []
            }
            let pkg = packageRefOf(db, def) ?? return []
            let commons = defMap(db, pkg).commons
            let found = ArrayList<DefId>()
            for (name in item.names) {
                for (common in commons.get(name) ?? [] where common.id.item(db).kind == item.kind &&
                    !found.contains(common.id)) {
                    found.add(common.id)
                }
            }
            found.toArray()
    }
}

/**
 * The `specific` declaration that completes `def`, a `common` one of its package (#318), `None` for
 * any other.
 */
public func specificOf(db: AnalysisDatabase, def: DefId): ?DefId {
    let item = itemOf(db, def) ?? return None
    if (!item.has(Modifier.Common)) {
        return None
    }
    let pkg = packageRefOf(db, def) ?? return None
    let map = defMap(db, pkg)
    for (name in item.names) {
        if (!(map.commons.get(name) ?? []).iterator().any {common => common.id == def}) {
            continue
        }
        for (one in map.names.get(name) ?? [] where one.id.item(db).kind == item.kind) {
            if (itemOf(db, one.id).map {it => it.has(Modifier.Specific)} ?? false) {
                return one.id
            }
        }
    }
    None
}

/**
 * The type `ty` is as a build has it: its `specific` declaration for a `common` one that has it.
 */
func completedType(db: AnalysisDatabase, ty: ExtendedType): ExtendedType {
    match (ty) {
        case DeclType(id) => match (specificOf(db, id)) {
            case Some(specific) => ExtendedType.DeclType(specific)
            case None => ty
        }
        case _ => ty
    }
}

/**
 * The members of `common`, a `common` declaration `specific` completes, named `name`, if
 * `specific` has no member of the name: what the `common` type adds to it, with a body (#318).
 */
func commonMembersNamed(db: AnalysisDatabase, specific: DefId, item: Item, name: String): Array<MemberTarget> {
    if (!item.has(Modifier.Specific) || item.members.iterator().any {member => member.names.contains(name)}) {
        return []
    }
    let found = ArrayList<MemberTarget>()
    for (common in commonsOf(db, specific)) {
        found.add(all: membersOfItem(db, common, name))
    }
    found.toArray()
}

/**
 * The item of `def`, a member of `parent`.
 */
func memberItemOf(db: AnalysisDatabase, parent: DefId, def: DefId): ?Item {
    let id = def.item(db)
    let item = itemOf(db, parent) ?? return None
    item.members.iterator().filter {member => member.id == id}.next()
}

/**
 * A `common` declaration no `specific` one completes, though it needs one, as cjc says it: `'common'
 * function 'f' can not find 'specific' match`.
 */
@Derive[Equatable]
public struct NoSpecific {
    public NoSpecific(public let def: DefId, public let message: String) {}
}

/**
 * The `common` declarations of `file`, of `pkg`, that need a `specific` one and have none (#318),
 * in the order of the file, a type before its members: a function, a constructor, a property or a
 * variable of no body; a type with a member that needs one, every constructor of an enum among
 * them, or a function of an interface (which itself needs none); and a member that needs one of a
 * type a `specific` one completes, which has no member of its name and kind.
 */
@CalcaTracked
public func noSpecifics(db: AnalysisDatabase, pkg: Package, file: SourceFile): Array<NoSpecific> {
    let tree = activeItemTree(db, file)
    if (!tree.items.iterator().any {item => item.has(Modifier.Common)}) {
        return []
    }
    let own = ItemFile.Source(file)
    let root = parse(db, file).syntaxNode()
    let ids = itemIdMap(db, file)
    let map = defMap(db, PackageRef.Source(pkg))
    let found = ArrayList<NoSpecific>()
    for (item in tree.items where item.has(Modifier.Common)) {
        let def = DefId(db, own, item.id)
        let name = item.names.get(0) ?? ""
        let completed = item.names.iterator().any {
            one => (map.commons.get(one) ?? []).iterator().any {common => common.id == def}
        }
        let specificMembers = if (completed) {
            specificOf(db, def).flatMap {specific => itemOf(db, specific)}.map {specific => specific.members} ?? []
        } else {
            Array<Item>()
        }
        let missing = ArrayList<NoSpecific>()
        for (member in item.members where needsSpecific(member, item.kind, ids, root)) {
            if (completed && specificMembers.iterator().any {
                one => one.kind == member.kind && one.names == member.names
            }) {
                continue
            }
            // an interface's function needs none of its own: the interface does
            if (item.kind == ItemKind.Interface && member.kind == ItemKind.Func) {
                continue
            }
            missing.add(NoSpecific(DefId(db, own, member.id), messageOf(member, item.kind, name)))
        }
        if (!completed && (needsSpecific(item, None, ids, root) ||
            item.members.iterator().any {member => needsSpecific(member, item.kind, ids, root)})) {
            found.add(NoSpecific(def, messageOf(item, None, "")))
        }
        found.add(all: missing)
    }
    found.toArray()
}

/**
 * Whether `item`, `common`, in a declaration of the kind `around` (`None` at the top), needs a
 * `specific` declaration: a function, a constructor, a property or a variable of no body, and every
 * constructor of an enum. A type needs one by its members (`noSpecifics`).
 */
func needsSpecific(item: Item, around: ?ItemKind, ids: ItemIdMap, root: CjSyntaxNode): Bool {
    if (item.kind == ItemKind.EnumCtor) {
        return around == Some(ItemKind.Enum)
    }
    if (!item.has(Modifier.Common)) {
        return false
    }
    let node = ids.node(item.id, root) ?? return false
    match (item.kind) {
        case Func => FuncDecl.cast(node).map {decl => decl.block().isNone()} ?? false
        case Init => InitDecl.cast(node).map {decl => decl.block().isNone()} ?? false
        case Prop => PropDecl.cast(node).map {decl => decl.propBody().isNone()} ?? false
        case Var => VarDecl.cast(node).map {decl => decl.expr().isNone()} ?? false
        case _ => false
    }
}

/**
 * What cjc says of `item`, in a declaration of the kind `around` named `owner`, that finds no
 * `specific` declaration.
 */
func messageOf(item: Item, around: ?ItemKind, owner: String): String {
    let name = item.names.get(0) ?? ""
    let what = match (item.kind) {
        case Func => "function '${name}'"
        case Init => "constructor"
        case Prop => "property '${name}'"
        case Var => "variable '${name}'"
        case Class => "class '${name}'"
        case Struct => "struct '${name}'"
        case Enum => "enum '${name}'"
        case Interface => "interface '${name}'"
        case EnumCtor where around == Some(ItemKind.Enum) => "enum '${owner}' constructor '${name}'"
        case _ => "declaration '${name}'"
    }
    "'common' ${what} can not find 'specific' match"
}

/**
 * Why the build leaves `file` out, `None` if it does not: it is among a module's inactive files, of a
 * source set the target does not take (#318).
 */
@CalcaTracked
public func inactiveReasonOf(db: AnalysisDatabase, file: SourceFile): ?String {
    let project = db.project() ?? return None
    let fileId = file.fileId(db)
    for (module in project.modules(db)) {
        for (one in module.inactive(db) where one.fileId == fileId) {
            return one.reason
        }
    }
    None
}
