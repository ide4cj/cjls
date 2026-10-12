package loupe.hir

import std.collection.*
import std.deriving.*
import ginkgo.TextRange
import cjsyntax.{CjParse, CjSyntaxNode}
import cjsyntax.ast.{AnyHasName, Decl, MacroExpandDecl}
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
 * What written in a macro call an item of its expansion comes from, where go to definition goes for it or a member
 * of it.
 */
@Derive[Equatable]
public enum ExpansionOrigin {
    /**
     * The interface of `@Derive[...]` at this index there.
     */
    | OfEntry(Int64)
    /**
     * The macro's name in the call: `@Test`'s.
     */
    | OfMacro
    /**
     * The name of the declaration the call is on: the function `@Strategy` replaces.
     */
    | OfName
    /**
     * The option `@UnittestOption[...](...)` names.
     */
    | OfOption
}

/**
 * What a macro call adds after its item, as text cjsyntax parses: declarations, signatures alone, their bodies empty;
 * for each item of it in order, what written in the call it comes from; and whether it replaces the item the call is
 * on, which then declares nothing (`@Strategy`'s function, whose body stays in a lambda of the `let` it becomes).
 */
@Derive[Equatable]
public struct Expansion {
    public Expansion(
        public let text: String,
        public let origins: Array<ExpansionOrigin>,
        public let replaces!: Bool = false
    ) {}
}

/**
 * A macro of std the analysis expands (#175).
 */
@Derive[Equatable]
enum StdMacro {
    /**
     * `std.deriving`'s `@Derive`, on a class, struct or enum.
     */
    | DeriveMacro
    /**
     * `std.unittest.testmacro`'s `@Test`, on a class or a function.
     */
    | TestMacro
    /**
     * `@TestTemplate`, on a class.
     */
    | TestTemplateMacro
    /**
     * `@TestBuilder`, on a function.
     */
    | TestBuilderMacro
    /**
     * `@Strategy`, on a function.
     */
    | StrategyMacro
    /**
     * `@UnittestOption[...](...)`, a call on no declaration.
     */
    | UnittestOptionMacro

    /**
     * The macro of std the declaration `pkg`.`name` is, if it is one the analysis expands.
     */
    static func named(pkg: String, name: String): ?StdMacro {
        match ((pkg, name)) {
            case ("std.deriving", "Derive") => DeriveMacro
            case ("std.unittest.testmacro", "Test") => TestMacro
            case ("std.unittest.testmacro", "TestTemplate") => TestTemplateMacro
            case ("std.unittest.testmacro", "TestBuilder") => TestBuilderMacro
            case ("std.unittest.testmacro", "Strategy") => StrategyMacro
            case ("std.unittest.testmacro", "UnittestOption") => UnittestOptionMacro
            case _ => None
        }
    }

    /**
     * Whether it takes an item of `kind`; on any other, cjc's macro fails, and adds nothing.
     */
    func takes(kind: ItemKind): Bool {
        match (this) {
            case DeriveMacro => kind == ItemKind.Class || kind == ItemKind.Struct || kind == ItemKind.Enum
            case TestMacro => kind == ItemKind.Class || kind == ItemKind.Func
            case TestTemplateMacro => kind == ItemKind.Class
            case TestBuilderMacro | StrategyMacro => kind == ItemKind.Func
            case UnittestOptionMacro => kind == ItemKind.MacroCall
        }
    }

    /**
     * Whether it is one of the macros of `std.unittest.testmacro` of which only the outermost on an item rewrites it,
     * the others seen as its configuration (`topLevelMacroDriver`).
     */
    prop drivesTheItem: Bool {
        get() {
            match (this) {
                case TestMacro | TestTemplateMacro | TestBuilderMacro => true
                case _ => false
            }
        }
    }
}

/**
 * The package and the name of the macro `resolution`, of a macro's name, is: of all its declarations, for a macro with
 * and without an attribute is two of one name, which a lookup finds ambiguous (`Test(input)`, `Test(attr, input)`);
 * `None` if it is not one macro.
 */
func macroPathOf(db: AnalysisDatabase, resolution: Resolution): ?(String, String) {
    let ids = match (resolution) {
        case Found(ids) where !ids.isEmpty() => ids
        case Ambiguous(targets) =>
            let decls = targets |> filterMap {
                one: ScopeTarget => match (one) {
                    case OfDecl(id) => Some(id)
                    case OfPackage(_) => None<DefId>
                }
            } |> collectArray
            if (decls.size != targets.size) {
                return None
            }
            decls
        case _ => return None
    }
    let paths = ids.map {
        id => match ((packageRefOf(db, id), (itemOf(db, id)?.names ?? []).get(0))) {
            case (Some(pkg), Some(name)) => Some((nameOf(db, pkg), name))
            case _ => None<(String, String)>
        }
    }
    let first = paths[0] ?? return None
    let same = paths.iterator().all {
        one => match (one) {
            case Some((pkg, name)) => pkg == first[0] && name == first[1]
            case None => false
        }
    }
    if (same) {
        first
    } else {
        None
    }
}

/**
 * The macro of std `resolution`, of a macro's name, is, if it is one the analysis expands.
 */
func stdMacroOf(db: AnalysisDatabase, resolution: Resolution): ?StdMacro {
    let (pkg, name) = macroPathOf(db, resolution) ?? return None
    StdMacro.named(pkg, name)
}

/**
 * Whether what the macro `resolution` names adds to a declaration, a member if `onMember`, is known: std's
 * `std.deriving` and `std.unittest.testmacro` macros, which the analysis expands or which add nothing a name reaches
 * (`@DeriveExclude`, `@TestCase`, `@Configure`, `@Test` on a member, ...; #175), but `@Strategy` on a member, which
 * cjc makes a `prop` of its class and the analysis does not expand.
 */
public func isReadMacro(db: AnalysisDatabase, resolution: Resolution, onMember!: Bool): Bool {
    match (macroPathOf(db, resolution)) {
        case Some(("std.deriving", _)) => true
        case Some(("std.unittest.testmacro", "Strategy")) => !onMember
        case Some(("std.unittest.testmacro", _)) => true
        case _ => false
    }
}

/**
 * The macro calls on the items of `file` the analysis expands, each with its macro: std's `@Derive` on a type, and
 * what of `std.unittest.testmacro` declares (`@Test`, `@TestTemplate`, `@TestBuilder`, `@Strategy`, `@UnittestOption`),
 * on a declaration of the file's top level. A macro is std's when its name resolves to std's through the file's
 * imports, not by its name alone (`macrosOf`). Of `@Test`, `@TestTemplate` and `@TestBuilder` on one item, only the
 * outermost.
 */
func stdCallsOf(db: AnalysisDatabase, file: SourceFile): Array<(MacroCallId, StdMacro)> {
    let found = ArrayList<(MacroCallId, StdMacro)>()
    for (item in itemTree(db, file).items where !item.macros.isEmpty()) {
        let macros = macrosOf(db, DefId(db, ItemFile.Source(file), item.id))
        var driven = false
        for (i in 0..macros.size) {
            let stdMacro = stdMacroOf(db, macros[i]) ?? continue
            if (!stdMacro.takes(item.kind) || (stdMacro.drivesTheItem && driven)) {
                continue
            }
            driven = driven || stdMacro.drivesTheItem
            found.add((MacroCallId(db, file, item.id, i), stdMacro))
        }
    }
    found.toArray()
}

/**
 * The macro calls on the items of `file` the analysis expands (`stdCallsOf`), in their order.
 */
@CalcaTracked
public func expandedCalls(db: AnalysisDatabase, file: SourceFile): Array<MacroCallId> {
    stdCallsOf(db, file).map {pair => pair[0]}
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
 * The items of the files the expansions `files` are of that one of them replaces.
 */
func replacedItemsOf(db: AnalysisDatabase, files: Array<ItemFile>): Array<ItemId> {
    files |> filterMap {
        file: ItemFile => match (file) {
            case Expansion(call) where macroExpansion(db, call).replaces => call.item(db)
            case _ => None<ItemId>
        }
    } |> collectArray
}

/**
 * The `Expansion` of `call`; an empty one for a call the analysis does not expand, or on an item no longer there.
 */
@CalcaTracked
public func macroExpansion(db: AnalysisDatabase, call: MacroCallId): Expansion {
    let empty = Expansion("", [])
    let file = call.file(db)
    let item = call.item(db)
    if (!expandedCalls(db, file).contains(call)) {
        return empty
    }
    let resolution = macrosOf(db, DefId(db, ItemFile.Source(file), item)).get(call.index(db)) ?? return empty
    let stdMacro = stdMacroOf(db, resolution) ?? return empty
    let root = parse(db, file).syntaxNode()
    let node = itemIdMap(db, file).node(item, root) ?? return empty
    let decl = Decl.cast(node) ?? return empty
    let macroCall = macroCallsOf(node).get(call.index(db)) ?? return empty
    let expansion = match (stdMacro) {
        case DeriveMacro => deriveExpansion(decl, macroCall)
        case TestMacro where item.kind == ItemKind.Func => testFuncExpansion(decl)
        case TestMacro => testClassExpansion(decl, template: false)
        case TestTemplateMacro => testClassExpansion(decl, template: true)
        case TestBuilderMacro => testBuilderExpansion(decl)
        case StrategyMacro => strategyExpansion(decl)
        case UnittestOptionMacro => optionExpansion(macroCall)
    }
    expansion ?? empty
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
 * Where what declares `item`, an item of the expansion of `call` or a member of one, is written in the call: what it
 * comes from (`ExpansionOrigin`), and around it the call or the declaration; `None` if the call is no longer there.
 */
public func expansionOrigin(db: AnalysisDatabase, call: MacroCallId, item: ItemId): ?(TextRange, TextRange) {
    let items = expansionItemTree(db, call).items
    let declares = {one: Item => one.id == item || one.members.iterator().any {member => member.id == item}}
    let index = (items.enumerate() |> filter {pair: (Int64, Item) => declares(pair[1])} |> first).map {pair: (Int64, Item) => pair[0]} ??
        return None
    let origin = macroExpansion(db, call).origins.get(index) ?? return None
    let file = call.file(db)
    let node = itemIdMap(db, file).node(call.item(db), parse(db, file).syntaxNode()) ?? return None
    let macroCall = macroCallsOf(node).get(call.index(db)) ?? return None
    match (origin) {
        case OfEntry(entry) =>
            let attr = macroCall.macroAttr() ?? return None
            let one = deriveEntries(attr).get(entry) ?? return None
            (one.nameRange, attr.syntax.textRange)
        case OfMacro =>
            let names = macroCall.nameRefs() |> map {name => name.syntax.textRange} |> collectArray
            let last = names.get(names.size - 1) ?? return None
            let start = macroCall.atToken()?.textRange.start ?? names[0].start
            let end = macroCall.macroAttr()?.syntax.textRange.end ?? last.end
            (TextRange(names[0].start, last.end), TextRange(start, end))
        case OfName =>
            let name = AnyHasName.cast(node).flatMap {it => it.name()} ?? return None
            (name.syntax.textRange, node.textRange)
        case OfOption =>
            let args = macroCall.macroArgs() ?? return None
            let token = optionNameOf(args)?[0] ?? return None
            (token.textRange, args.syntax.textRange)
    }
}

/**
 * The macro calls on the item of `node`, outermost first: those around its declaration; for a call on no
 * declaration, those around it, then itself.
 */
func macroCallsOf(node: CjSyntaxNode): Array<MacroExpandDecl> {
    let calls = ArrayList<MacroExpandDecl>()
    if (let Some(call) <- MacroExpandDecl.cast(node)) {
        calls.add(call)
    }
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
