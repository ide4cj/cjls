package loupe

import std.collection.*
import cjsyntax.ast.{ExtendDecl, Type, isIdent}
import loupe.db.AnalysisDatabase
import loupe.hir.{DefId, ItemFile, ItemKind, overridingMembers, subtypesOf}
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * What implements the name at `offset` of the file, rust-analyzer's `goto_implementation`: of a function
 * or a property of a type, the members overriding or implementing it (`overridingMembers`); of a class or an
 * interface, the types below it and the `extend`s declaring it (`subtypesOf`), an `extend` at the type it
 * extends. Nothing for any other name.
 */
public func implementationsAt(db: AnalysisDatabase, fileId: FileId, offset: Int64): Array<NavigationTarget> {
    let file = db.sourceFile(fileId) ?? return []
    let token = tokenAt(parse(db, file).syntaxNode(), offset) ?? return []
    if (!isIdent(token)) {
        return []
    }
    let found = ArrayList<NavigationTarget>()
    for (definition in meaningsAt(db, file, token)) {
        let id = match (definition) {
            case DeclDef(id) => id
            case _ => continue
        }
        let below = match (id.item(db).kind) {
            case Func | Prop => overridingMembers(db, id)
            case Class | Interface => subtypesOf(db, id)
            case _ => continue
        }
        for (one in below) {
            if (let Some(target) <- implementationTarget(db, one) && !found.contains(target)) {
                found.add(target)
            }
        }
    }
    found.toArray()
}

/**
 * Where the implementation `id` is: a declaration's name, an `extend`'s type, which it has no name for.
 */
func implementationTarget(db: AnalysisDatabase, id: DefId): ?NavigationTarget {
    if (id.item(db).kind != ItemKind.Extend) {
        return declTarget(db, id)
    }
    let target = declTarget(db, id) ?? return None
    let ty: ?Type = match (id.file(db)) {
        case Source(_) => itemNodeOf(db, id).flatMap {node => ExtendDecl.cast(node)}.flatMap {decl => decl.ty()}
        case _ => None
    }
    match (ty) {
        case Some(one) => NavigationTarget(target.fileId, target.fullRange, one.syntax.textRange)
        case None => target
    }
}
