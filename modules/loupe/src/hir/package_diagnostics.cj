package loupe.hir

import calca.*
import calca.macros.*
import loupe.db.*

/**
 * Whether a file's explicit package header disagrees with its package's macro kind. Without
 * explicit metadata, any macro header makes the package a macro package, as `isMacroPackage`
 * determines for building it. Checks only explicit, named headers.
 */
@CalcaTracked
public func packageHeaderError(db: AnalysisDatabase, file: SourceFile): ?String {
    let pkg = packageOfFile(db, file) ?? return None
    let header = itemTree(db, file).packageHeader ?? return None
    if (header.name.isEmpty()) {
        return None
    }
    let macroPackage = isMacroPackage(db, pkg)
    if (header.isMacro == macroPackage) {
        return None
    }
    if (macroPackage) {
        "file in macro package '${pkg.name(db)}' must declare 'macro package'"
    } else {
        "file in ordinary package '${pkg.name(db)}' must not declare 'macro package'"
    }
}
