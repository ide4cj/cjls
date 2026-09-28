package loupe

import std.collection.*
import std.deriving.*
import std.unicode.*
import calca.*
import calca.macros.*
import ginkgo.TextRange
import cjsyntax.parse as parseText
import loupe.vfs.FileId
import loupe.db.{AnalysisDatabase, SourceFile}

/**
 * A declaration of a file, as a search of the workspace sees it: an entry of its outline, and the
 * name of the one it is under, if any.
 */
@Derive[Equatable]
public struct FileSymbol {
    public FileSymbol(
        public let name: String,
        public let kind: StructureKind,
        public let range: TextRange,
        public let selectionRange: TextRange,
        public let containerName: ?String
    ) {}
}

/**
 * A declaration of the workspace a search found, and the file it is in.
 */
public struct FoundSymbol {
    public FoundSymbol(public let fileId: FileId, public let symbol: FileSymbol) {}
}

/**
 * Every declaration of the file, in the order of its outline, a declaration before what it holds:
 * the index a search of the workspace goes through, rust-analyzer's `file_symbols`.
 *
 * It parses the text itself rather than through `parse`: a search reads every file of the
 * workspace, and `parse` keeps each tree it made until the next revision (D17), which for a
 * workspace of thousands of files is more than the heap holds. The tree is dropped here, and what
 * is kept is names and ranges.
 */
@CalcaTracked
public func fileSymbols(db: AnalysisDatabase, file: SourceFile): Array<FileSymbol> {
    let symbols = ArrayList<FileSymbol>()
    flatten(structureOfTree(parseText(file.text(db).toString())), None, symbols)
    symbols.toArray()
}

/**
 * The declarations of `files` whose names match `query`, at most `limit` of them: in the order
 * of `files`, and in each as `fileSymbols` has them. A name matches when the query's characters
 * are in it in order, whatever their case (`fb` matches `FooBar`), as rust-analyzer's search does;
 * an empty query matches every name.
 */
public func workspaceSymbols(db: AnalysisDatabase, files: Array<FileId>, query: String, limit: Int64): Array<FoundSymbol> {
    let found = ArrayList<FoundSymbol>()
    let wanted = query.toLower().toRuneArray()
    for (fileId in files) {
        let file = db.sourceFile(fileId) ?? continue
        for (symbol in fileSymbols(db, file) where matches(symbol.name, wanted)) {
            if (found.size >= limit) {
                return found.toArray()
            }
            found.add(FoundSymbol(fileId, symbol))
        }
    }
    found.toArray()
}

private func flatten(nodes: Array<StructureNode>, container: ?String, symbols: ArrayList<FileSymbol>): Unit {
    for (node in nodes) {
        symbols.add(FileSymbol(node.name, node.kind, node.range, node.selectionRange, container))
        flatten(node.children, node.name, symbols)
    }
}

/**
 * Whether `wanted`, lowercase, is a subsequence of `name`, whatever its case.
 */
func matches(name: String, wanted: Array<Rune>): Bool {
    var next = 0
    for (rune in name.toLower().runes()) {
        if (next == wanted.size) {
            break
        }
        if (rune == wanted[next]) {
            next++
        }
    }
    next == wanted.size
}
