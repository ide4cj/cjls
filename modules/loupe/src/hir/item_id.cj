package loupe.hir

import std.collection.*
import std.deriving.*
import ginkgo.{SyntaxElement, SyntaxNodePtr}
import cjsyntax.{CjParse, CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.{AnyHasName, Decl, MacroExpandDecl, identText}
import cjsyntax.ast.SourceFile as SourceFileNode
import calca.*
import calca.macros.*
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.syntax.parse

/**
 * What an item is: a declaration the item tree holds, an import, or a macro call on no declaration;
 * or a type built into the compiler (`Array`, `CPointer`), declared in `std.core`'s `.cjo` alone.
 */
@Derive[Equatable, Hashable]
public enum ItemKind <: ToString {
    | Import
    | Func
    | Main
    | Macro
    | Class
    | Interface
    | Struct
    | Enum
    | Extend
    | TypeAlias
    | Var
    | Prop
    | Init
    | Finalizer
    | PrimaryInit
    | EnumCtor
    | MacroCall
    | BuiltIn

    public func toString(): String {
        match (this) {
            case Import => "Import"
            case Func => "Func"
            case Main => "Main"
            case Macro => "Macro"
            case Class => "Class"
            case Interface => "Interface"
            case Struct => "Struct"
            case Enum => "Enum"
            case Extend => "Extend"
            case TypeAlias => "TypeAlias"
            case Var => "Var"
            case Prop => "Prop"
            case Init => "Init"
            case Finalizer => "Finalizer"
            case PrimaryInit => "PrimaryInit"
            case EnumCtor => "EnumCtor"
            case MacroCall => "MacroCall"
            case BuiltIn => "BuiltIn"
        }
    }
}

/**
 * An item of a file, named so that an edit elsewhere leaves it as it is (D34): its kind, a hash of
 * its parent's id and its name, and its place among the items of the file with the same kind and
 * hash. An edit inside a body, a blank line, an item added or removed or moved leaves the ids of the
 * other items alone; only an overload added before one moves it. It means something only in its
 * file, and goes back to a node through the file's `ItemIdMap`.
 */
@Derive[Equatable, Hashable]
public struct ItemId <: ToString {
    public ItemId(public let kind: ItemKind, public let hash: Int64, public let index: Int64) {}

    public func toString(): String {
        "${kind}#${hash}/${index}"
    }
}

/**
 * Where each item of a file is in its tree, and the other way round: an id to the pointer of its
 * node, and a pointer to an id. It changes with every edit that moves an item, which the item tree
 * does not: a query keeps the id, and asks this for the node.
 *
 * The node of an item is its declaration, under any macro calls on it; that of an import, the
 * `ImportDecl`.
 */
public class ItemIdMap <: Equatable<ItemIdMap> {
    private let byId = HashMap<ItemId, SyntaxNodePtr<SyntaxKind>>()
    private let byPtr = HashMap<SyntaxNodePtr<SyntaxKind>, ItemId>()

    /**
     * The ids and pointers in the order the items are in the file, a parent before its members.
     */
    private ItemIdMap(private let ids: Array<ItemId>, private let ptrs: Array<SyntaxNodePtr<SyntaxKind>>) {
        for (i in 0..ids.size) {
            byId.add(ids[i], ptrs[i])
            byPtr.add(ptrs[i], ids[i])
        }
    }

    /**
     * The ids of the items of `tree`.
     */
    public static func of(tree: CjParse): ItemIdMap {
        let builder = ItemIdBuilder()
        if (let Some(root) <- SourceFileNode.cast(tree.syntaxNode())) {
            for (decl in root.importDecls()) {
                builder.add(None, ItemKind.Import, compactText(decl.importTree()?.syntax), decl.syntax)
            }
            builder.addItems(None, root.decls())
        }
        ItemIdMap(builder.ids.toArray(), builder.ptrs.toArray())
    }

    /**
     * Every id, in the order of the file.
     */
    public prop all: Array<ItemId> {
        get() {
            ids
        }
    }

    /**
     * The pointer to the node of `id`, `None` if no item of the file has it.
     */
    public func ptr(id: ItemId): ?SyntaxNodePtr<SyntaxKind> {
        byId.get(id)
    }

    /**
     * The id of the item whose node `ptr` points to, `None` if it is no item's.
     */
    public func idOf(ptr: SyntaxNodePtr<SyntaxKind>): ?ItemId {
        byPtr.get(ptr)
    }

    /**
     * The node of `id` under `root`, the tree this was made of, `None` if no item has it.
     */
    public func node(id: ItemId, root: CjSyntaxNode): ?CjSyntaxNode {
        ptr(id).flatMap {ptr => ptr.tryToNode(root)}
    }

    public operator func ==(other: ItemIdMap): Bool {
        ids == other.ids && ptrs == other.ptrs
    }

    public operator func !=(other: ItemIdMap): Bool {
        !(this == other)
    }
}

/**
 * The file's `ItemIdMap`.
 */
@CalcaTracked
public func itemIdMap(db: AnalysisDatabase, file: SourceFile): ItemIdMap {
    ItemIdMap.of(parse(db, file))
}

/**
 * The ids given so far, and how many items had each kind and hash.
 */
class ItemIdBuilder {
    let ids = ArrayList<ItemId>()
    let ptrs = ArrayList<SyntaxNodePtr<SyntaxKind>>()
    private let seen = HashMap<ItemId, Int64>()

    func add(parent: ?ItemId, kind: ItemKind, name: String, node: CjSyntaxNode): ItemId {
        let first = ItemId(kind, pathHash(parent, name), 0)
        let index = seen.get(first) ?? 0
        seen.add(first, index + 1)
        let id = ItemId(kind, first.hash, index)
        ids.add(id)
        ptrs.add(SyntaxNodePtr(node))
        id
    }

    func addItems(parent: ?ItemId, decls: Iterator<Decl>): Unit {
        for (item in itemsIn(decls)) {
            let id = add(parent, item.kind, item.idName(), item.decl.syntax)
            addItems(id, item.members())
        }
    }
}

/**
 * An item as the tree has it: its declaration, the macro calls on it, outermost first, and whether
 * a `foreign` block holds it. For a macro call on no declaration, `decl` is the call.
 */
struct ItemSyntax {
    ItemSyntax(
        let kind: ItemKind,
        let decl: Decl,
        let macroCalls: Array<MacroExpandDecl>,
        let inForeignBlock: Bool
    ) {}

    /**
     * What its id is made of besides its parent: its name, without backquotes; `main`, `init`,
     * `~init` for what a keyword names; the type and the bounds for an `extend`, as written but for
     * backquotes; the
     * pattern of a `let` that has no single name; the macro of a call. Empty for a name not
     * written yet.
     */
    func idName(): String {
        match (decl) {
            case Decl.AsMainDecl(_) => "main"
            case Decl.AsInitDecl(_) => "init"
            case Decl.AsFinalizerDecl(_) => "~init"
            case Decl.AsExtendDecl(it) => compactText(it.ty()?.syntax) + compactText(it.typeBoundList()?.syntax)
            case Decl.AsVarDecl(it) where it.name().isNone() => compactText(it.pattern()?.syntax)
            case Decl.AsMacroExpandDecl(it) => macroName(it)
            case _ => AnyHasName.cast(decl.syntax)?.name()?.text() ?? ""
        }
    }

    /**
     * What it declares inside: a type's members.
     */
    func members(): Iterator<Decl> {
        let decls = match (decl) {
            case Decl.AsClassDecl(it) => it.declBody()?.decls()
            case Decl.AsInterfaceDecl(it) => it.declBody()?.decls()
            case Decl.AsStructDecl(it) => it.declBody()?.decls()
            case Decl.AsExtendDecl(it) => it.declBody()?.decls()
            case Decl.AsEnumDecl(it) => it.enumBody()?.decls()
            case _ => None<Iterator<Decl>>
        }
        decls ?? Array<Decl>().iterator()
    }
}

/**
 * The items `decls` hold: each declaration, the one under a macro call, those of a `foreign` block,
 * and a macro call on no declaration.
 */
func itemsIn(decls: Iterator<Decl>): Array<ItemSyntax> {
    let items = ArrayList<ItemSyntax>()
    for (decl in decls) {
        collectItem(decl, [], false, items)
    }
    items.toArray()
}

private func collectItem(decl: Decl, macroCalls: Array<MacroExpandDecl>, inForeignBlock: Bool,
    items: ArrayList<ItemSyntax>): Unit {
    let kind = match (decl) {
        case Decl.AsMacroExpandDecl(call) => match (call.decl()) {
            case Some(inner) => return collectItem(inner, macroCalls.concat([call]), inForeignBlock, items)
            case None => ItemKind.MacroCall
        }
        case Decl.AsForeignBlock(block) =>
            for (inner in block.decls()) {
                collectItem(inner, macroCalls, true, items)
            }
            return
        case Decl.AsFuncDecl(_) => ItemKind.Func
        case Decl.AsMainDecl(_) => ItemKind.Main
        case Decl.AsMacroDecl(_) => ItemKind.Macro
        case Decl.AsClassDecl(_) => ItemKind.Class
        case Decl.AsInterfaceDecl(_) => ItemKind.Interface
        case Decl.AsStructDecl(_) => ItemKind.Struct
        case Decl.AsEnumDecl(_) => ItemKind.Enum
        case Decl.AsExtendDecl(_) => ItemKind.Extend
        case Decl.AsTypeAliasDecl(_) => ItemKind.TypeAlias
        case Decl.AsVarDecl(_) => ItemKind.Var
        case Decl.AsPropDecl(_) => ItemKind.Prop
        case Decl.AsInitDecl(_) => ItemKind.Init
        case Decl.AsFinalizerDecl(_) => ItemKind.Finalizer
        case Decl.AsPrimaryInitDecl(_) => ItemKind.PrimaryInit
        case Decl.AsEnumCtor(_) => ItemKind.EnumCtor
    }
    items.add(ItemSyntax(kind, decl, macroCalls, inForeignBlock))
}

/**
 * The macro a call names, as written: `Derive`, `a.b.M`.
 */
func macroName(call: MacroExpandDecl): String {
    call.nameRefs() |> map {name => name.text()} |> collectArray |> {names => String.join(names, delimiter: ".")}
}

/**
 * The tokens of `node` but whitespace and comments, one after another, identifiers without their
 * backquotes: `Map < K , V >`, `Map<K, V>` and `` `Map`<K, V> `` are the same.
 */
func compactText(syntax: ?CjSyntaxNode): String {
    let node = syntax ?? return ""
    let text = StringBuilder()
    for (element in node.descendantsWithTokens()) {
        if (let SyntaxElement.Token(token) <- element) {
            if (!token.kind.isTrivia()) {
                text.append(identText(token))
            }
        }
    }
    text.toString()
}

/**
 * The hash of the parent's id and the name. std's hashes have no seed: the same in every process.
 */
func pathHash(parent: ?ItemId, name: String): Int64 {
    var hasher = DefaultHasher()
    if (let Some(parent) <- parent) {
        hasher.write(parent.kind.hashCode())
        hasher.write(parent.hash)
        hasher.write(parent.index)
    }
    hasher.write(name)
    hasher.finish()
}
