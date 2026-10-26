package loupe

import cjsyntax.parse
import cjsyntax.ast.SourceFile as AstSourceFile
import loupe.db.ProjectModel
import loupe.vfs.VfsPath
import rope.Rope

/**
 * The header for a new file, or `None` when its project names no package. Explicit macro metadata
 * takes precedence over headers in the current file contents. A new directory is an ordinary
 * package even when its parent is a macro package. Reads no analysis queries, so the server can
 * use this while opening a document on its read loop.
 */
public func newFilePackageLine(model: ProjectModel, path: VfsPath, textOf: (VfsPath) -> ?Rope): ?String {
    let name = model.packageOfNewFile(path) ?? return None
    for (module in model.modules) {
        for (pkg in module.packages where Some(pkg.dir) == path.parent && pkg.name == name) {
            let macroPackage = pkg.isMacro ?? pkg.files.iterator().any {
                file =>
                let text = textOf(file) ?? return false
                let root = AstSourceFile.cast(parse(text.toString()).syntaxNode()) ?? return false
                (root.packageHeader()?.macroToken() ?? None).isSome()
            }
            return "${if (macroPackage) {"macro "} else {""}}package ${name}"
        }
    }
    "package ${name}"
}
