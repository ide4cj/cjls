package loupe

public import cjformat.TextEdit
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase
import loupe.syntax.parse
import cjformat.{format, formatRange}
import ginkgo.TextRange

/**
 * The edits that format a file (`cjformat.format`), on the tree the database already holds; `None`
 * for a file with syntax errors, or one the database does not know.
 *
 * Not a query: an editor asks it once for a version it then changes.
 */
public func formatting(db: AnalysisDatabase, fileId: FileId): ?Array<TextEdit> {
    format(parse(db, db.sourceFile(fileId) ?? return None))
}

/**
 * The edits that format the lines `range` covers (`cjformat.formatRange`), indented as the whole
 * file formatted indents them; `None` as for `formatting`.
 */
public func rangeFormatting(db: AnalysisDatabase, fileId: FileId, range: TextRange): ?Array<TextEdit> {
    formatRange(parse(db, db.sourceFile(fileId) ?? return None), range)
}
