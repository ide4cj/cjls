package loupe

import std.collection.*
import std.unicode.*
import ginkgo.TextRange
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase

/**
 * A declaration of the workspace a search found: an entry of its file's outline, and the name of
 * the one it is under, if any.
 */
public class FoundSymbol {
    public FoundSymbol(
        public let fileId: FileId,
        public let name: String,
        public let kind: StructureKind,
        public let range: TextRange,
        public let selectionRange: TextRange,
        public let containerName: ?String
    ) {}
}

/**
 * The declarations of `files` whose names match `query`, at most `limit` of them: in the order
 * of `files`, and in each as its outline has them, a declaration before what it holds. A name
 * matches when the query's characters are in it in order, whatever their case (`fb` matches
 * `FooBar`), as rust-analyzer's search does; an empty query matches every name.
 */
public func workspaceSymbols(db: AnalysisDatabase, files: Array<FileId>, query: String, limit: Int64): Array<FoundSymbol> {
    let found = ArrayList<FoundSymbol>()
    let wanted = query.toLower().toRuneArray()
    for (file in files) {
        collectMatches(file, fileStructure(db, file), None, wanted, limit, found)
        if (found.size >= limit) {
            break
        }
    }
    found.toArray()
}

private func collectMatches(file: FileId, nodes: Array<StructureNode>, container: ?String, wanted: Array<Rune>,
    limit: Int64, found: ArrayList<FoundSymbol>): Unit {
    for (node in nodes) {
        if (found.size >= limit) {
            return
        }
        if (matches(node.name, wanted)) {
            found.add(FoundSymbol(file, node.name, node.kind, node.range, node.selectionRange, container))
        }
        collectMatches(file, node.children, node.name, wanted, limit, found)
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
