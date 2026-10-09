package loupe.hir

import std.collection.*
import std.deriving.*
import ginkgo.TextRange
import cjsyntax.{CjParse, CjSyntaxNode}
import cjsyntax.ast.{Decl, MacroExpandDecl}
import cjsyntax.parse as parseText
import calca.*
import calca.macros.*
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.syntax.parse

/**
 * A macro called on an item of a source file (#175): the file, the item, and the macro among those called on it,
 * outermost first (its index in `Item.macros`), interned. What it adds is `ItemFile.Expansion` of it.
 */
@CalcaInterned
public struct MacroCallId {
    public let file: SourceFile
    public let item: ItemId
    public let index: Int64
}

/**
 * What a macro call adds after its item, as text cjsyntax parses: declarations, signatures alone, their bodies empty;
 * and, for each item of it in order, what written in the call it comes from (an interface of `@Derive[...]` by its
 * index there), where a member of it is declared for go to definition.
 */
@Derive[Equatable]
public struct Expansion {
    public Expansion(public let text: String, public let origins: Array<Int64>) {}
}

/**
 * The macro calls of the items of `file` the analysis expands: std's `@Derive` on a type. A macro is std's when its
 * name resolves to std's through the file's imports, not by its name alone (`macrosOf`).
 */
@CalcaTracked
public func expandedCalls(db: AnalysisDatabase, file: SourceFile): Array<MacroCallId> {
    let found = ArrayList<MacroCallId>()
    for (item in itemTree(db, file).items where !item.macros.isEmpty() && isDerivable(item.kind)) {
        let macros = macrosOf(db, DefId(db, ItemFile.Source(file), item.id))
        for (i in 0..macros.size where isStdDerive(db, macros[i])) {
            found.add(MacroCallId(db, file, item.id, i))
        }
    }
    found.toArray()
}

/**
 * The files of the expansions of the macro calls in `file`, in their order; none for a file of a package compiled
 * already, whose macros were expanded, nor for an expansion.
 */
public func expansionsOf(db: AnalysisDatabase, file: ItemFile): Array<ItemFile> {
    match (file) {
        case Source(source) => expandedCalls(db, source).map {call => ItemFile.Expansion(call)}
        case _ => []
    }
}

/**
 * The `Expansion` of `call`; an empty one for a call the analysis does not expand, or on an item no longer there.
 */
@CalcaTracked
public func macroExpansion(db: AnalysisDatabase, call: MacroCallId): Expansion {
    let empty = Expansion("", [])
    let file = call.file(db)
    let item = call.item(db)
    if (!isDerivable(item.kind) || !isStdDerive(db, macrosOf(db, DefId(db, ItemFile.Source(file), item)).get(
        call.index(db)) ?? Resolution.NotFound)) {
        return empty
    }
    let root = parse(db, file).syntaxNode()
    let node = itemIdMap(db, file).node(item, root) ?? return empty
    let decl = Decl.cast(node) ?? return empty
    let macroCall = macroCallsOn(node).get(call.index(db)) ?? return empty
    deriveExpansion(decl, macroCall) ?? empty
}

/**
 * The tree of the text of the expansion of `call`. As `parse`, only the last ones are kept.
 */
@CalcaTracked[lru: 128]
public func expansionParse(db: AnalysisDatabase, call: MacroCallId): CjParse {
    parseText(macroExpansion(db, call).text)
}

/**
 * The `ItemIdMap` of the expansion of `call`.
 */
@CalcaTracked
public func expansionIdMap(db: AnalysisDatabase, call: MacroCallId): ItemIdMap {
    ItemIdMap.of(expansionParse(db, call))
}

/**
 * The `ItemTree` of the expansion of `call`.
 */
@CalcaTracked
public func expansionItemTree(db: AnalysisDatabase, call: MacroCallId): ItemTree {
    ItemTree.of(expansionParse(db, call), expansionIdMap(db, call))
}

/**
 * The root of the tree of `file` and the ids of its items: a source file's, an expansion's; `None` for a file of a
 * package compiled already, which has no tree.
 */
public func syntaxOf(db: AnalysisDatabase, file: ItemFile): ?(CjSyntaxNode, ItemIdMap) {
    match (file) {
        case Source(source) => (parse(db, source).syntaxNode(), itemIdMap(db, source))
        case Expansion(call) => (expansionParse(db, call).syntaxNode(), expansionIdMap(db, call))
        case Binary(_, _) => None
    }
}

/**
 * The source file the names of `file` resolve in: itself, the file of the call for an expansion, whose output cjc
 * pastes in the place of the call; `None` for a file of a package compiled already.
 */
public func scopeFileOf(db: AnalysisDatabase, file: ItemFile): ?SourceFile {
    match (file) {
        case Source(source) => source
        case Expansion(call) => call.file(db)
        case Binary(_, _) => None
    }
}

/**
 * Where what declares `item`, an item of the expansion of `call` or a member of one, is written in the call: the
 * name of the interface of `@Derive[...]` it comes from, and the brackets around them all; `None` if the call is no
 * longer there.
 */
public func expansionOrigin(db: AnalysisDatabase, call: MacroCallId, item: ItemId): ?(TextRange, TextRange) {
    let items = expansionItemTree(db, call).items
    let declares = {one: Item => one.id == item || one.members.iterator().any {member => member.id == item}}
    let index = (items.enumerate() |> filter {pair: (Int64, Item) => declares(pair[1])} |> first).map {pair: (Int64, Item) => pair[0]} ??
        return None
    let origin = macroExpansion(db, call).origins.get(index) ?? return None
    let file = call.file(db)
    let node = itemIdMap(db, file).node(call.item(db), parse(db, file).syntaxNode()) ?? return None
    let attr = macroCallsOn(node).get(call.index(db)).flatMap {one => one.macroAttr()} ?? return None
    let entry = deriveEntries(attr).get(origin) ?? return None
    (entry.nameRange, attr.syntax.textRange)
}

/**
 * The macro calls on the declaration `node`, outermost first: the calls around it.
 */
func macroCallsOn(node: CjSyntaxNode): Array<MacroExpandDecl> {
    let calls = ArrayList<MacroExpandDecl>()
    var parent = node.parent
    while (true) {
        let one = parent ?? break
        let call = MacroExpandDecl.cast(one) ?? break
        calls.add(call)
        parent = one.parent
    }
    calls.reverse()
    calls.toArray()
}

/**
 * Whether `@Derive` takes a declaration of `kind`.
 */
func isDerivable(kind: ItemKind): Bool {
    kind == ItemKind.Class || kind == ItemKind.Struct || kind == ItemKind.Enum
}

/**
 * Whether `resolution`, of a macro's name, is `std.deriving`'s `Derive`.
 */
func isStdDerive(db: AnalysisDatabase, resolution: Resolution): Bool {
    match (resolution) {
        case Found(ids) where ids.size == 1 =>
            let isDerive = (itemOf(db, ids[0])?.names ?? []).contains("Derive")
            isDerive && match (packageRefOf(db, ids[0])) {
                case Some(pkg) => nameOf(db, pkg) == "std.deriving"
                case None => false
            }
        case _ => false
    }
}
