package loupe.hir

import calca.{TrackedBody, TrackedFunction}
import calca.macros.CalcaTracked
import loupe.db.{AnalysisDatabase, Package, SourceFile}

/**
 * Why a file's explicit package header disagrees with its package's metadata or first named
 * header in path order, as cjc checks consistency; `None` when it agrees or has no named header.
 */
@CalcaTracked
protected func packageHeaderError(db: AnalysisDatabase, file: SourceFile): ?String {
    let pkg = packageOfFile(db, file) ?? return None
    let header = itemTree(db, file).packageHeader ?? return None
    if (header.name.isEmpty()) {
        return None
    }
    if (let Some(macroPackage) <- pkg.isMacro(db)) {
        if (header.isMacro == macroPackage) {
            return None
        }
        return if (macroPackage) {
            "file in macro package '${pkg.name(db)}' must declare 'macro package'"
        } else {
            "file in ordinary package '${pkg.name(db)}' must not declare 'macro package'"
        }
    }
    let expected = packageHeaderKind(db, pkg) ?? return None
    if (header.isMacro != expected) {
        return "package name with macro should be consistent in the same package."
    }
    None
}

/**
 * The macro kind of the first named header in path order, or `None` if no file has one.
 * Shared by file diagnostics so the package is scanned only once per relevant change.
 */
@CalcaTracked
func packageHeaderKind(db: AnalysisDatabase, pkg: Package): ?Bool {
    let files = pkg.files(db)
    let paths = pkg.filePaths(db)
    var firstPath: ?String = None
    var kind: ?Bool = None
    for (i in 0..files.size) {
        let path = paths[i].toString()
        if (let Some(first) <- firstPath) {
            if (path.compare(first) != Ordering.LT) {
                continue
            }
        }
        let header =
            db.sourceFile(files[i]).flatMap { file => itemTree(db, file).packageHeader } ?? continue
        if (header.name.isEmpty()) {
            continue
        }
        firstPath = path
        kind = header.isMacro
    }
    kind
}
