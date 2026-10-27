package loupe

public import cjformat.TextEdit
import cjformat.{FormatOptions, format, formatRange}
import ginkgo.TextRange
import loupe.db.AnalysisDatabase
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * The edits that format a file (`cjformat.format`), on the tree the database already holds; `None`
 * for a file with syntax errors, or one the database does not know.
 *
 * Not a query: an editor asks it once for a version it then changes.
 */
public func formatting(
    db: AnalysisDatabase,
    fileId: FileId,
    options!: FormatOptions = FormatOptions()
): ?Array<TextEdit> {
    format(parse(db, db.sourceFile(fileId) ?? return None), options: options)
}

/**
 * The edits that format the complete syntax node enclosing `range` (`cjformat.formatRange`); `None` as for `formatting`.
 */
public func rangeFormatting(
    db: AnalysisDatabase,
    fileId: FileId,
    range: TextRange,
    options!: FormatOptions = FormatOptions()
): ?Array<TextEdit> {
    formatRange(parse(db, db.sourceFile(fileId) ?? return None), range, options: options)
}
