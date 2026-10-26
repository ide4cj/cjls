package loupe.hir

import calca.{TrackedBody, TrackedFunction}
import calca.macros.CalcaTracked
import loupe.db.{AnalysisDatabase, SourceFile}

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
    // A stray macro header must not make every ordinary header wrong. cjc compares against
    // the first file, independently of executable/library output and --compile-macro.
    for (id in pkg.files(db)) {
        let first = db.sourceFile(id).flatMap {one => itemTree(db, one).packageHeader} ?? continue
        if (first.name.isEmpty()) {
            continue
        }
        if (header.isMacro != first.isMacro) {
            return "package name with macro should be consistent in the same package."
        }
        return None
    }
    None
}
