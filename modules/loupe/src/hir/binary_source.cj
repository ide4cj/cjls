package loupe.hir

import std.collection.ArrayList
import std.deriving.Derive
import calca.*
import calca.macros.CalcaTracked
import cjo.{openCjo, Position as CjoPosition}
import cjsyntax.ast.AnyHasName
import ginkgo.TextRange
import index_map.IndexMap
import loupe.db.{AnalysisDatabase, BinaryPackageFile, Package, SourceFile}
import loupe.syntax.parse
import loupe.vfs.FileId
import rope.{Encoding, LineColumn, Rope}

/**
 * A binary declaration's checked source position, shared by navigation and source identity.
 */
@Derive[Equatable]
protected struct BinarySourceLocation {
    public BinarySourceLocation(
        public let fileId: FileId,
        public let fullRange: TextRange,
        public let focusRange: TextRange
    ) {}
}

/**
 * The D65 position/name check; absent sources and mismatched names produce no location.
 */
protected func binarySourceLocation(
    db: AnalysisDatabase,
    pkg: BinaryPackageFile,
    file: Int64,
    id: ItemId
): ?BinarySourceLocation {
    let index = binaryExports(db, pkg).declIndex(BinaryItem(file, id)) ?? return None
    let name =
        (findBinaryItem(itemTreeOf(db, ItemFile.Binary(pkg, file)).items, id)?.names ?? [])
            .get(0) ??
            return None
    // the positions of cjc: lines and columns from 1, columns in bytes, the end past the declaration
    let bytes = pkg.bytes(db)
    let (fileName, begin, end, at) =
        try {
            let cjo = openCjo(bytes)
            let decl = cjo.allDecls[index]
            let lineColumn =
                {
                    position: ?CjoPosition =>
                    position.map { it => (Int64(it.line) - 1, Int64(it.column) - 1) }
                }
            (
                cjo.allFiles[file],
                lineColumn(decl.begin),
                lineColumn(decl.end),
                lineColumn(decl.identifierPos)
            )
        } catch (_: Exception) {
            return None
        }
    let binary = pkg.binary(db)
    let sources = db.project()?.binarySources(db) ?? return None
    let fileId =
        sources
            .iterator()
            .filter { source => source.binary == binary && source.name == fileName }
            .next()?
            .fileId ??
            return None
    let text = (db.sourceFile(fileId) ?? return None).text(db)
    let offsetOf: (?(Int64, Int64)) -> ?Int64 =
        {
            position =>
            match (position) {
                case Some((line, column)) where line >= 0 && column >= 0 && line < text.lineCount =>
                    Some(text.offsetOf(LineColumn(line, column), Encoding.Utf8))
                case _ => None
            }
        }
    // a name in backquotes is at the name, inside them
    let start = offsetOf(at) ?? return None
    if (!writes(text, start, name)) {
        return None
    }
    let focus = TextRange(start, start + name.size)
    let full =
        match ((offsetOf(begin), offsetOf(end))) {
            case (Some(from), Some(to)) where from <= focus.start && focus.end <= to =>
                TextRange(from, to)
            case _ => focus
        }
    BinarySourceLocation(fileId, full, focus)
}

/**
 * The item `id` among `items` and their members.
 */
func findBinaryItem(items: Array<Item>, id: ItemId): ?Item {
    for (item in items) {
        if (item.id == id) {
            return item
        }
        if (let Some(member) <- findBinaryItem(item.members, id)) {
            return member
        }
    }
    None
}

/**
 * Whether `text` has `written` at `offset`.
 */
func writes(text: Rope, offset: Int64, written: String): Bool {
    offset + written.size <= text.size &&
        text.slice(offset..offset + written.size).toString() == written
}

/**
 * The detached context of an attached file, before any source query is run.
 */
func attachedContext(db: AnalysisDatabase, file: SourceFile): ?Package {
    let id = file.fileId(db)
    for (source in db.project()?.binarySources(db) ?? [] where source.fileId == id) {
        return source.context
    }
    None
}

/**
 * Source items paired with the binary declarations at their exact identifier positions.
 * Only this file is parsed; no syntax tree escapes the query. No name/signature fallback can
 * accidentally pair an overload or an inactive platform alternative from another SDK.
 */
@CalcaTracked
func binarySourceItems(db: AnalysisDatabase, file: SourceFile): IndexMap<ItemId, DefId> {
    let found = IndexMap<ItemId, DefId>()
    let context = attachedContext(db, file) ?? return found
    let pkg = context.binary(db) ?? return found
    let source =
        (db.project()?.binarySources(db) ?? [])
            .iterator()
            .filter { one => one.fileId == file.fileId(db) }
            .next() ??
            return found
    let bytes = pkg.bytes(db)
    let names =
        try {
            openCjo(bytes).allFiles.toArray()
        } catch (_: Exception) {
            return found
        }
    let index = names.indexOf(source.name) ?? return found
    let root = parse(db, file).syntaxNode()
    let ids = itemIdMap(db, file)
    let pending = ArrayList<Item>(binaryItemTrees(db, pkg)[index].items)
    while (!pending.isEmpty()) {
        let item = pending.remove(at: pending.size - 1)
        pending.add(all: item.members)
        let at = binarySourceLocation(db, pkg, index, item.id) ?? continue
        let token = root.tokenAtOffset(at.focusRange.start).rightBiased() ?? continue
        for (node in token.parent.ancestors()) {
            let name = AnyHasName.cast(node).flatMap { one => one.name() } ?? continue
            if (
                name.syntax.textRange.containsRange(at.focusRange) &&
                    item.names.contains(name.text()) &&
                    let Some(id) <- ids.idAround(node) &&
                    id.kind == item.kind
            ) {
                found[id] = DefId(db, ItemFile.Binary(pkg, index), item.id)
                break
            }
        }
    }
    found
}

/**
 * A source body keeps its syntax identity; types and generic owners use its binary identity.
 */
protected func canonicalDef(db: AnalysisDatabase, def: DefId): DefId {
    match (def.file(db)) {
        case Source(file) => binarySourceItems(db, file).get(def.item(db)) ?? def
        case _ => def
    }
}

/**
 * A source context is usable only when this file has declarations matching the installed binary.
 */
func binaryContextOfFile(db: AnalysisDatabase, file: SourceFile): ?Package {
    if (binarySourceItems(db, file).isEmpty()) { None } else { attachedContext(db, file) }
}

/**
 * The resolution package of a detached source context, or a normal source package itself.
 */
protected func resolutionPackage(db: AnalysisDatabase, pkg: Package): PackageRef {
    pkg.binary(db).map { one => PackageRef.Binary(one) } ?? PackageRef.Source(pkg)
}

/**
 * Private binary declarations are visible from their attached source file alone.
 */
func resolutionFile(db: AnalysisDatabase, file: SourceFile): ItemFile {
    for ((_, def) in binarySourceItems(db, file)) {
        return def.file(db)
    }
    ItemFile.Source(file)
}

/**
 * The paired source declaration, for navigation to a binary owner's type parameters.
 */
protected func sourceDefOf(db: AnalysisDatabase, def: DefId): ?DefId {
    let (pkg, index) =
        match (def.file(db)) {
            case Binary(pkg, index) => (pkg, index)
            case _ => return None
        }
    let at = binarySourceLocation(db, pkg, index, def.item(db)) ?? return None
    let file = db.sourceFile(at.fileId) ?? return None
    for ((item, binary) in binarySourceItems(db, file) where binary == def) {
        return DefId(db, ItemFile.Source(file), item)
    }
    None
}

/**
 * Implementation helpers omitted from the binary are available only in the detached context.
 * Binary names win, including overload sets and compiler types; this never changes its exports.
 */
@CalcaTracked
func binarySourceDefMap(db: AnalysisDatabase, pkg: Package, stage: ScopeStage): DefMap {
    let compiled = defMapAt(db, resolutionPackage(db, pkg), stage)
    let trees =
        pkg
            .files(db)
            .filterMap { id => db.sourceFile(id) }
            .filter { file => !binarySourceItems(db, file).isEmpty() }
            .map {
                file =>
                let tree = activeItemTree(db, file)
                (
                    ItemFile.Source(file),
                    ItemTree(
                        items: tree
                            .items
                            .filter {
                                item =>
                                item.kind != ItemKind.Extend && !item.names.isEmpty() &&
                                    item
                                        .names
                                        .iterator()
                                        .all { name => !compiled.names.contains(name) }
                            }
                    )
                )
            }
    let extra = collectDefMap(db, trees)
    let names = IndexMap<String, Array<Def>>(compiled.names.toArray())
    for ((name, defs) in extra.names) {
        names[name] = defs
    }
    let ctors = IndexMap<String, Array<Def>>(compiled.ctors.toArray())
    for ((name, defs) in extra.ctors) {
        ctors[name] = (ctors.get(name) ?? []).concat(defs)
    }
    DefMap(names, ctors, compiled.errors.concat(extra.errors), commons: compiled.commons)
}
