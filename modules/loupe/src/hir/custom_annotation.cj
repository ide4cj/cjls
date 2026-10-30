package loupe.hir

import cjo.DeclInfo
import cjsyntax.ast.AnyHasAnnotations
import loupe.db.AnalysisDatabase

/**
 * A macro-like spelling denotes an annotation only when its resolved class declares that role.
 */
func isAnnotationClass(db: AnalysisDatabase, id: DefId): Bool {
    if (id.item(db).kind != ItemKind.Class) {
        return false
    }
    match (id.file(db)) {
        case Binary(pkg, index) =>
            let decl = binaryDecl(db, pkg, BinaryItem(index, id.item(db))) ?? return false
            match (decl.info) {
                case Some(DeclInfo.AsClassInfo(info)) => info.isAnno
                case _ => false
            }
        case _ =>
            let (root, ids) = syntaxOf(db, id.file(db)) ?? return false
            let node = ids.node(id.item(db), root) ?? return false
            let annotated = AnyHasAnnotations.cast(node) ?? return false
            annotated
                .annotations()
                .any { annotation => annotation.nameRef()?.text() == Some("Annotation") }
    }
}

/**
 * Constructor visibility is part of successful typing, even while general access diagnostics are deferred.
 */
func isAnnotationConstructorVisible(db: AnalysisDatabase, from: DefId, initializer: DefId): Bool {
    let item = itemOf(db, initializer) ?? return false
    let visibility = visibilityOf(item)
    if (visibility == Visibility.Private) {
        return enclosingTypeOf(db, from) == enclosingTypeOf(db, initializer)
    }
    let source = packageRefOf(db, from) ?? return false
    let target = packageRefOf(db, initializer) ?? return false
    visibility.isSeen(by: relationOf(nameOf(db, source), nameOf(db, target)))
}

/**
 * A declaration macro owns its input until analysis reads a successful replacement.
 */
func isAnnotationInputOpaque(db: AnalysisDatabase, def: DefId): Bool {
    let file = sourceFileOf(db, def) ?? return true
    let pkg = packageOf(db, def) ?? return true
    var current = Some(def)
    while (let Some(owner) <- current) {
        let item = itemOf(db, owner) ?? return true
        for (name in item.macros.concat(item.paramMacros.flatten())) {
            let path = name.split(".")
            if (
                resolveMacroPath(db, pkg, file, path).get(path.size - 1) !=
                    Some(Resolution.NotFound)
            ) {
                return true
            }
        }
        current = parentOf(db, owner)
    }
    false
}
