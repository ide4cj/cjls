package loupe.hir

import std.collection.*
import calca.*
import calca.macros.*
import loupe.db.{AnalysisDatabase, Package, SourceFile}

/**
 * What each segment of `path`, the macro a call names (`@Derive`, `@deriving.Derive`), means in `file` of `pkg`. A
 * first segment followed by others is a package imported by its name, as in a type (N51, N52), and the macro one of
 * its exports; a lone segment is a macro of the file's scope: its package's, its imports' (an alias, a glob). A macro
 * is seen as nothing else, nor anything else as a macro: a function `Derive` leaves `@Derive` the imported macro. A
 * segment after the macro is not found.
 */
public func resolveMacroPath(db: AnalysisDatabase, pkg: Package, file: SourceFile, path: Array<String>): Array<Resolution> {
    if (path.isEmpty()) {
        return []
    }
    if (path.size == 1) {
        return [lookUp(db, pkg, file, path[0], Namespace.Macros)]
    }
    let found = ArrayList<Resolution>()
    let qualifier = match (qualifierNamed(db, TypeScope([], pkg, file), path[0], stage: ScopeStage.Written)) {
        case Some(Resolved(QualifierOf(one))) =>
            found.add(Resolution.FoundPackage(one))
            Some(one)
        case Some(ConflictedPackages(pkgs)) =>
            found.add(Resolution.Ambiguous(pkgs.map {one => ScopeTarget.OfPackage(one)}))
            None<PackageRef>
        case _ =>
            found.add(Resolution.NotFound)
            None<PackageRef>
    }
    found.add(match (qualifier) {
        case Some(one) => macroOfPackage(db, pkg, one, path[1])
        case None => Resolution.NotFound
    })
    for (_ in 2..path.size) {
        found.add(Resolution.NotFound)
    }
    found.toArray()
}

/**
 * The macro `name` names among the exports of `target` that `pkg` sees.
 */
func macroOfPackage(db: AnalysisDatabase, pkg: Package, target: PackageRef, name: String): Resolution {
    let relation = relationOf(pkg.name(db), nameOf(db, target))
    let ids = visibleOf(exportsAt(db, target, ScopeStage.Written).names.get(name) ?? [], relation, Visibility.Private).filter {
        id => isIn(id.item(db).kind, Namespace.Macros)
    }
    match (ids.size) {
        case 0 => Resolution.NotFound
        case 1 => Resolution.Found(ids)
        case _ => Resolution.Ambiguous(ids.map {id => ScopeTarget.OfDecl(id)})
    }
}

/**
 * What each macro called on `def` names, outermost first: the last segment of its path (`resolveMacroPath`). None
 * for a declaration of a package compiled already, whose macros were expanded, of an expansion, or of a file of no
 * package. A name of `item.macros` is its segments joined by `.`, without spaces or backquotes (`macroName`), and
 * takes no type arguments (cjc: `expected declaration, found '<'`), so its segments are split back at `.`.
 */
public func macrosOf(db: AnalysisDatabase, def: DefId): Array<Resolution> {
    let file = match (def.file(db)) {
        case Source(file) => file
        case _ => return []
    }
    let pkg = packageOfFile(db, file) ?? return []
    let item = declItemOf(db, def) ?? return []
    item.macros.map {
        name =>
        let path = name.split(".")
        resolveMacroPath(db, pkg, file, path)[path.size - 1]
    }
}

/**
 * Whether a macro whose expansion is not read (`isReadMacro`) is called on `def` or on one of its members: what it
 * adds to them is not known (#176).
 */
public func hasUnreadMacros(db: AnalysisDatabase, def: DefId): Bool {
    let onMember = parentOf(db, def).isSome()
    if (macrosOf(db, def).iterator().any {one => !isReadMacro(db, one, onMember: onMember)}) {
        return true
    }
    let item = declItemOf(db, def) ?? return false
    let file = def.file(db)
    item.members.iterator().any {member => !member.macros.isEmpty() && hasUnreadMacros(db, DefId(db, file, member.id))}
}

/**
 * Whether a macro whose expansion is not read is called on a declaration of `pkg`: a name of its files' scope may be
 * one it declares (#176). A query of its own, so that a body reading it is not invalidated by every edit of the
 * package.
 */
@CalcaTracked
public func packageHasUnreadMacros(db: AnalysisDatabase, pkg: Package): Bool {
    for (file in filesOf(db, PackageRef.Source(pkg))) {
        for (item in itemTreeOf(db, file).items where !item.macros.isEmpty() || !item.members.isEmpty()) {
            if (hasUnreadMacros(db, DefId(db, file, item.id))) {
                return true
            }
        }
    }
    false
}
