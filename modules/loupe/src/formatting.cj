package loupe

public import cjformat.TextEdit
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase
import loupe.syntax.parse
import cjformat.format

/**
 * The edits that format a file (`cjformat.format`), on the tree the database already holds; `None`
 * for a file with syntax errors, or one the database does not know.
 *
 * Not a query: an editor asks it once for a version it then changes.
 */
public func formatting(db: AnalysisDatabase, fileId: FileId): ?Array<TextEdit> {
    format(parse(db, db.sourceFile(fileId) ?? return None))
}
