package loupe.hir

import std.collection.*
import std.deriving.*
import ginkgo.{SyntaxElement, SyntaxNodePtr}
import cjsyntax.{CjParse, CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.{Decl, ImportTree, Modifiers, Pattern, VarDecl}
import cjsyntax.ast.SourceFile as SourceFileNode
import calca.*
import calca.macros.*
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.syntax.parse

/**
 * A modifier, as written before a declaration.
 */
@Derive[Equatable]
public enum Modifier <: ToString {
    | Static
    | Public
    | Private
    | Internal
    | Protected
    | Override
    | Redef
    | Abstract
    | Sealed
    | Open
    | Foreign
    | Mut
    | Unsafe
    | Operator
    | Const
    | Common
    | Specific

    public func toString(): String {
        match (this) {
            case Static => "static"
            case Public => "public"
            case Private => "private"
            case Internal => "internal"
            case Protected => "protected"
            case Override => "override"
            case Redef => "redef"
            case Abstract => "abstract"
            case Sealed => "sealed"
            case Open => "open"
            case Foreign => "foreign"
            case Mut => "mut"
            case Unsafe => "unsafe"
            case Operator => "operator"
            case Const => "const"
            case Common => "common"
            case Specific => "specific"
        }
    }
}

/**
 * The modifiers in the order they are kept in, whatever the order they are written in.
 */
let MODIFIERS: Array<(SyntaxKind, Modifier)> = [
    (SyntaxKind.StaticKw, Modifier.Static),
    (SyntaxKind.PublicKw, Modifier.Public),
    (SyntaxKind.PrivateKw, Modifier.Private),
    (SyntaxKind.InternalKw, Modifier.Internal),
    (SyntaxKind.ProtectedKw, Modifier.Protected),
    (SyntaxKind.OverrideKw, Modifier.Override),
    (SyntaxKind.RedefKw, Modifier.Redef),
    (SyntaxKind.AbstractKw, Modifier.Abstract),
    (SyntaxKind.SealedKw, Modifier.Sealed),
    (SyntaxKind.OpenKw, Modifier.Open),
    (SyntaxKind.ForeignKw, Modifier.Foreign),
    (SyntaxKind.MutKw, Modifier.Mut),
    (SyntaxKind.UnsafeKw, Modifier.Unsafe),
    (SyntaxKind.OperatorKw, Modifier.Operator),
    (SyntaxKind.ConstKw, Modifier.Const),
    (SyntaxKind.CommonKw, Modifier.Common),
    (SyntaxKind.SpecificKw, Modifier.Specific)
]

/**
 * The `package` line: the package's name as written (`a.b`, `org::a.b`), and whether it is a
 * `macro package`.
 */
@Derive[Equatable]
public struct PackageItem {
    public PackageItem(
        public let name: String,
        public let isMacro: Bool,
        public let modifiers: Array<Modifier>
    ) {}
}

/**
 * One name an import brings in, as written: `segments` up to it, `org::a` one segment; every name
 * of the package for a glob (`a.b.*`), else the package's and the imported one's.
 */
@Derive[Equatable]
public struct ImportPath {
    public ImportPath(
        public let segments: Array<String>,
        public let alias!: ?String = None,
        public let isGlob!: Bool = false
    ) {}
}

/**
 * An `import`, and every name it brings in: `import a.{b as c, d.*}` brings two.
 */
@Derive[Equatable]
public struct ImportItem {
    public ImportItem(
        public let id: AstId,
        public let modifiers: Array<Modifier>,
        public let paths: Array<ImportPath>
    ) {}
}

/**
 * A declaration of the file, as name resolution needs it, and nothing that moves when the file is
 * edited elsewhere: no range, no body, no signature.
 */
@Derive[Equatable]
public struct Item {
    public Item(
        public let id: AstId,
        /**
         * What it declares by name: one for most, none for an `extend` or a macro call, each
         * binding of a `let` of a pattern. Empty while its name is not written yet.
         */
        public let names: Array<String>,
        /**
         * Those of the declaration and of the macro calls on it; `foreign` for one in a `foreign`
         * block.
         */
        public let modifiers: Array<Modifier>,
        /**
         * The macros called on it, outermost first; for a macro call on no declaration, its macro.
         */
        public let macros: Array<String>,
        /**
         * A type's members, an enum's constructors.
         */
        public let members: Array<Item>
    ) {}

    public prop kind: ItemKind {
        get() {
            id.kind
        }
    }

    /**
     * Whether `modifier` is among its modifiers.
     */
    public func has(modifier: Modifier): Bool {
        modifiers.contains(modifier)
    }
}

/**
 * What a file declares, rust-analyzer's `ItemTree`: its package, its imports and its items, named
 * by their `AstId`s. An edit inside a body, or one that only moves items, leaves it equal, so what
 * read it is not run again.
 */
@Derive[Equatable]
public struct ItemTree {
    public ItemTree(
        public let packageHeader: ?PackageItem,
        public let imports: Array<ImportItem>,
        public let items: Array<Item>
    ) {}

    /**
     * The tree of `tree`, its items named by `ids`, made of it.
     */
    public static func of(tree: CjParse, ids: AstIdMap): ItemTree {
        let root = SourceFileNode.cast(tree.syntaxNode()) ?? return ItemTree(None, [], [])
        let packageHeader = root.packageHeader().map {
            header => PackageItem(String.join(pathSegments(header.syntax), delimiter: "."),
                header.macroToken().isSome(), modifiersOf([header.modifiers()]))
        }
        let imports = root.importDecls() |> map {
            decl =>
            let paths = ArrayList<ImportPath>()
            if (let Some(tree) <- decl.importTree()) {
                lowerImportTree(tree, [], paths)
            }
            ImportItem(idOf(ids, decl.syntax), modifiersOf([decl.modifiers()]), paths.toArray())
        } |> collectArray
        ItemTree(packageHeader, imports, lowerItems(root.decls(), ids))
    }
}

/**
 * The file's `ItemTree`.
 */
@CalcaTracked
public func itemTree(db: AnalysisDatabase, file: SourceFile): ItemTree {
    ItemTree.of(parse(db, file), astIdMap(db, file))
}

private func lowerItems(decls: Iterator<Decl>, ids: AstIdMap): Array<Item> {
    itemsIn(decls).map {
        item =>
        let modifiers = modifiersOf(item.macroCalls.map {call => call.modifiers()}.concat([modifiersNode(item.decl)]),
            inForeignBlock: item.inForeignBlock)
        let macros = item.macroCalls.map {call => macroName(call)}
        let macrosOfItem = match (item.decl) {
            case Decl.AsMacroExpandDecl(call) => macros.concat([macroName(call)])
            case _ => macros
        }
        Item(idOf(ids, item.decl.syntax), namesOf(item.decl), modifiers, macrosOfItem, lowerItems(item.members(), ids))
    }
}

/**
 * The id `ids` gives the node: made of the same tree, they have every item.
 */
private func idOf(ids: AstIdMap, node: CjSyntaxNode): AstId {
    ids.idOf(SyntaxNodePtr(node)) ?? throw IllegalStateException("no id for the item at ${node.textRange}")
}

private func namesOf(decl: Decl): Array<String> {
    let name = match (decl) {
        case Decl.AsFuncDecl(it) => it.name()
        case Decl.AsMacroDecl(it) => it.name()
        case Decl.AsClassDecl(it) => it.name()
        case Decl.AsInterfaceDecl(it) => it.name()
        case Decl.AsStructDecl(it) => it.name()
        case Decl.AsEnumDecl(it) => it.name()
        case Decl.AsTypeAliasDecl(it) => it.name()
        case Decl.AsPropDecl(it) => it.name()
        case Decl.AsPrimaryInitDecl(it) => it.name()
        case Decl.AsEnumCtor(it) => it.name()
        case Decl.AsMainDecl(_) => return ["main"]
        case Decl.AsInitDecl(_) => return ["init"]
        case Decl.AsFinalizerDecl(_) => return ["~init"]
        case Decl.AsVarDecl(it) => return bindingsOf(it)
        case Decl.AsExtendDecl(_) | Decl.AsMacroExpandDecl(_) | Decl.AsForeignBlock(_) => return []
    }
    match (name) {
        case Some(name) => [name.syntax.text()]
        case None => []
    }
}

/**
 * The names a `let`, `var` or `const` binds, in the order they are written.
 */
private func bindingsOf(decl: VarDecl): Array<String> {
    if (let Some(name) <- decl.name()) {
        return [name.syntax.text()]
    }
    let names = ArrayList<String>()
    if (let Some(pattern) <- decl.pattern()) {
        collectBindings(pattern, names)
    }
    names.toArray()
}

private func collectBindings(pattern: Pattern, names: ArrayList<String>): Unit {
    match (pattern) {
        case Pattern.AsBindPat(it) => if (let Some(name) <- it.name()) {
            names.add(name.syntax.text())
        }
        case Pattern.AsTypePat(it) => if (let Some(name) <- it.name()) {
            names.add(name.syntax.text())
        }
        case Pattern.AsTuplePat(it) => for (inner in it.patterns()) {
            collectBindings(inner, names)
        }
        case Pattern.AsEnumPat(it) => for (inner in it.patterns()) {
            collectBindings(inner, names)
        }
        case Pattern.AsWildcardPat(_) | Pattern.AsLiteralPat(_) => ()
    }
}

/**
 * The `Modifiers` of any declaration: every one has them first, after its annotations.
 */
private func modifiersNode(decl: Decl): ?Modifiers {
    for (child in decl.syntax.children()) {
        if (let Some(modifiers) <- Modifiers.cast(child)) {
            return modifiers
        }
    }
    None
}

/**
 * The modifiers of `nodes` together, each once, in the order of `MODIFIERS`; `foreign` added for one in a `foreign` block.
 */
private func modifiersOf(nodes: Array<?Modifiers>, inForeignBlock!: Bool = false): Array<Modifier> {
    let written = HashSet<SyntaxKind>()
    for (node in nodes) {
        for (element in node?.syntax.childrenWithTokens() ?? continue) {
            if (let SyntaxElement.Token(token) <- element) {
                written.add(token.kind)
            }
        }
    }
    if (inForeignBlock) {
        written.add(SyntaxKind.ForeignKw)
    }
    MODIFIERS.filter {modifier => written.contains(modifier[0])}.map {modifier => modifier[1]}
}

/**
 * The names `tree` imports, `prefix` before them: one per leaf of its braces.
 */
private func lowerImportTree(tree: ImportTree, prefix: Array<String>, paths: ArrayList<ImportPath>): Unit {
    let segments = prefix.concat(pathSegments(tree.syntax))
    match (tree.importTreeList()) {
        case Some(list) => for (inner in list.importTrees()) {
            lowerImportTree(inner, segments, paths)
        }
        case None => paths.add(ImportPath(segments, alias: tree.importAlias()?.name()?.syntax.text(),
            isGlob: tree.starToken().isSome()))
    }
}

/**
 * The names of a path that are children of `node`, in order: `a.b` two, `org::a.b` two as well,
 * `org::a` and `b`.
 */
private func pathSegments(node: CjSyntaxNode): Array<String> {
    let segments = ArrayList<String>()
    var joinNext = false
    for (element in node.childrenWithTokens()) {
        match (element) {
            case SyntaxElement.Node(child) where child.kind == SyntaxKind.NameRef =>
                if (joinNext && !segments.isEmpty()) {
                    let org = segments[segments.size - 1]
                    segments[segments.size - 1] = "${org}::${child.text()}"
                } else {
                    segments.add(child.text())
                }
                joinNext = false
            case SyntaxElement.Token(token) where token.kind == SyntaxKind.ColonColon => joinNext = true
            case _ => ()
        }
    }
    segments.toArray()
}
