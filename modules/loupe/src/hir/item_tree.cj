package loupe.hir

import py_interop.*
import py_interop.internal_macros.*

import std.collection.*
import std.deriving.*
import ginkgo.{SyntaxElement, SyntaxNodePtr}
import cjsyntax.{CjParse, CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.{AnyHasName, Decl, ImportTree, Modifiers, NameRef, Pattern, VarDecl}
import cjsyntax.ast.SourceFile as SourceFileNode
import calca.*
import calca.macros.*
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.syntax.parse

/**
 * A modifier, as written before a declaration.
 */
@DerivePython[equatable]
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
let MODIFIERS: Array<(SyntaxKind, Modifier)> =
    [
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
@DerivePython[equatable]
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
@DerivePython[equatable]
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
@DerivePython[equatable]
@Derive[Equatable]
public struct ImportItem {
    public ImportItem(
        public let id: ItemId,
        public let modifiers: Array<Modifier>,
        public let paths: Array<ImportPath>,
        /**
         * Its `@When`'s, `None` for none.
         */
        public let condition!: ?CfgExpr = None
    ) {}
}

/**
 * A declaration of the file, as name resolution needs it, and nothing that moves when the file is
 * edited elsewhere: no range, no body, no signature.
 */
@DerivePython[equatable]
@Derive[Equatable]
public struct Item {
    public Item(
        public let id: ItemId,
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
        public let members: Array<Item>,
        /**
         * The `@When` before it, or before the outermost macro call on it, `None` for none: whether
         * it is in a build is the cfg's to say (`activeItemTree`).
         */
        public let condition!: ?CfgExpr = None,
        /**
         * The macros called on each parameter of its own parameter lists that has any, in the
         * parameters' order, each outermost first: `@M let x` of a primary constructor (D119).
         */
        public let paramMacros!: Array<Array<String>> = [],
        /**
         * Whether the declaration has the built-in `@C` annotation, distinct from a macro call.
         */
        public let isC!: Bool = false
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
 * by their `ItemId`s. An edit inside a body, or one that only moves items, leaves it equal, so what
 * read it is not run again.
 */
@DerivePython[equatable]
@Derive[Equatable]
public struct ItemTree {
    public ItemTree(
        public let packageHeader!: ?PackageItem = None,
        public let imports!: Array<ImportItem> = [],
        public let items!: Array<Item> = []
    ) {}

    /**
     * The tree of `tree`, its items named by `ids`, made of it.
     */
    @PyIgnore
    public static func of(tree: CjParse, ids: ItemIdMap): ItemTree {
        let root = SourceFileNode.cast(tree.syntaxNode()) ?? return ItemTree()
        let packageHeader =
            root
                .packageHeader()
                .map {
                    header =>
                    PackageItem(
                        String.join(pathSegments(header.syntax), delimiter: "."),
                        header.macroToken().isSome(),
                        modifiersOf([header.modifiers()])
                    )
                }
        let imports =
            root.importDecls() |>
                map {
                    decl =>
                    let paths = ArrayList<ImportPath>()
                    if (let Some(tree) <- decl.importTree()) {
                        lowerImportTree(tree, [], paths)
                    }
                    ImportItem(
                        idOf(ids, decl.syntax),
                        modifiersOf([decl.modifiers()]),
                        paths.toArray(),
                        condition: conditionOf(decl.syntax)
                    )
                } |>
                collectArray
        ItemTree(
            packageHeader: packageHeader,
            imports: imports,
            items: lowerItems(root.decls(), ids)
        )
    }
}

/**
 * The file's `ItemTree`.
 */
@CalcaTracked
public func itemTree(db: AnalysisDatabase, file: SourceFile): ItemTree {
    ItemTree.of(parse(db, file), itemIdMap(db, file))
}

private func lowerItems(decls: Iterator<Decl>, ids: ItemIdMap): Array<Item> {
    itemsIn(decls)
        .map {
            item =>
            let modifiers =
                modifiersOf(
                    item
                        .macroCalls
                        .map { call => call.modifiers() }
                        .concat([item.decl.modifiers()]),
                    inForeignBlock: item.inForeignBlock
                )
            let macros = item.macroCalls.map { call => macroName(call) }
            let macrosOfItem =
                match (item.decl) {
                    case Decl.AsMacroExpandDecl(call) => macros.concat([macroName(call)])
                    case _ => macros
                }
            let outermost = item.macroCalls.get(0).map { call => call.syntax } ?? item.decl.syntax
            let paramMacros =
                paramMacroCallsOf(item.decl.syntax)
                    .map { chain => chain.map { call => macroName(call) } }
            Item(
                idOf(ids, item.decl.syntax),
                namesOf(item.decl),
                modifiers,
                macrosOfItem,
                lowerItems(item.members(), ids),
                condition: conditionOf(outermost),
                paramMacros: paramMacros,
                isC: item
                    .decl
                    .annotations()
                    .any { annotation => annotation.nameRef()?.text() == Some("C") } ||
                    item
                        .macroCalls
                        .iterator()
                        .any {
                            call =>
                            call
                                .annotations()
                                .any { annotation => annotation.nameRef()?.text() == Some("C") }
                        }
            )
        }
}

/**
 * The id `ids` gives the node: made of the same tree, they have every item.
 */
private func idOf(ids: ItemIdMap, node: CjSyntaxNode): ItemId {
    ids.idOf(SyntaxNodePtr(node)) ??
        throw IllegalStateException("no id for the item at ${node.textRange}")
}

/**
 * What `decl` declares by name: its own, without backquotes; what a keyword names, `main`, `init`,
 * `~init`; the bindings of a `let`.
 */
private func namesOf(decl: Decl): Array<String> {
    match (decl) {
        case Decl.AsMainDecl(_) => ["main"]
        case Decl.AsInitDecl(_) => ["init"]
        case Decl.AsFinalizerDecl(_) => ["~init"]
        case Decl.AsVarDecl(it) => bindingsOf(it)
        case _ =>
            match (AnyHasName.cast(decl.syntax).flatMap { it => it.name() }) {
                case Some(name) => [name.text()]
                case None => []
            }
    }
}

/**
 * The names a `let`, `var` or `const` binds, in the order they are written.
 */
private func bindingsOf(decl: VarDecl): Array<String> {
    if (let Some(name) <- decl.name()) {
        return [name.text()]
    }
    let names = ArrayList<String>()
    if (let Some(pattern) <- decl.pattern()) {
        collectBindings(pattern, names)
    }
    names.toArray()
}

private func collectBindings(pattern: Pattern, names: ArrayList<String>): Unit {
    match (pattern) {
        case Pattern.AsBindPat(it) =>
            if (let Some(name) <- it.name()) {
                names.add(name.text())
            }
        case Pattern.AsTypePat(it) =>
            if (let Some(name) <- it.name()) {
                names.add(name.text())
            }
        case Pattern.AsTuplePat(it) =>
            for (inner in it.patterns()) {
                collectBindings(inner, names)
            }
        case Pattern.AsEnumPat(it) =>
            for (inner in it.patterns()) {
                collectBindings(inner, names)
            }
        case Pattern.AsWildcardPat(_) | Pattern.AsLiteralPat(_) => ()
    }
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
    MODIFIERS.filter { modifier => written.contains(modifier[0]) }.map { modifier => modifier[1] }
}

/**
 * The names `tree` imports, `prefix` before them: one per leaf of its braces.
 */
private func lowerImportTree(
    tree: ImportTree,
    prefix: Array<String>,
    paths: ArrayList<ImportPath>
): Unit {
    let segments = prefix.concat(pathSegments(tree.syntax))
    match (tree.importTreeList()) {
        case Some(list) =>
            for (inner in list.importTrees()) {
                lowerImportTree(inner, segments, paths)
            }
        case None =>
            paths
                .add(
                    ImportPath(
                        segments,
                        alias: tree.importAlias()?.name()?.text(),
                        isGlob: tree.starToken().isSome()
                    )
                )
    }
}

/**
 * The path of an import up to `name`, a name of its tree or the name of its alias, as `lowerImportTree` writes it: the
 * segments up to the one `name` is in (`org::a` one), with the alias, a glob if the leaf is one; and whether `name`
 * is the name a leaf brings, its last or its alias, the path then the leaf's. `None` for a name of no import.
 */
public func importPathTo(name: CjSyntaxNode): ?(ImportPath, Bool) {
    let parent = name.parent ?? return None
    let (tree, upTo): (ImportTree, ?CjSyntaxNode) =
        if (let Some(one) <- ImportTree.cast(parent) && NameRef.canCast(name.kind)) {
            (one, name)
        } else if (parent.kind == SyntaxKind.ImportAlias && name.kind == SyntaxKind.Name) {
            (ImportTree.cast(parent.parent ?? return None) ?? return None, None)
        } else {
            return None
        }
    let outers = ArrayList<ImportTree>()
    outers
        .add(
            all: tree.syntax.ancestors() |> skip(1) |>
                filterMap { node: CjSyntaxNode => ImportTree.cast(node) } |>
                collectArray
        )
    outers.reverse()
    let segments = ArrayList<String>()
    for (outer in outers) {
        segments.add(all: pathSegments(outer.syntax))
    }
    segments.add(all: pathSegments(tree.syntax, upTo: upTo))
    var last: ?NameRef = None
    for (one in tree.nameRefs()) {
        last = one
    }
    let isLeaf =
        tree.importTreeList().isNone() && tree.starToken().isNone() &&
            (upTo.isNone() || last.map { one => one.syntax.textRange } == Some(name.textRange))
    let alias = if (isLeaf) { tree.importAlias()?.name()?.text() } else { None<String> }
    (
        ImportPath(
            segments.toArray(),
            alias: alias,
            isGlob: upTo.isNone() && tree.starToken().isSome()
        ),
        isLeaf
    )
}

/**
 * The names of a path that are children of `node`, in order: `a.b` two, `org::a.b` two as well,
 * `org::a` and `b`; up to the name `upTo`, if one, and the one it is joined to after it (`org` of
 * `org::a` is `org::a`).
 */
private func pathSegments(node: CjSyntaxNode, upTo!: ?CjSyntaxNode = None): Array<String> {
    let segments = ArrayList<String>()
    var joinNext = false
    var reached = false
    for (element in node.childrenWithTokens()) {
        match (element) {
            case SyntaxElement.Node(child) where NameRef.canCast(child.kind) =>
                if (reached && !joinNext) {
                    break
                }
                let name = NameRef.cast(child)?.text() ?? ""
                if (joinNext && !segments.isEmpty()) {
                    let org = segments[segments.size - 1]
                    segments[segments.size - 1] = "${org}::${name}"
                } else {
                    segments.add(name)
                }
                joinNext = false
                reached = reached || upTo.map { one => one.textRange } == Some(child.textRange)
            case SyntaxElement.Token(token) where token.kind == SyntaxKind.ColonColon =>
                joinNext = true
            case SyntaxElement.Token(token) where reached && !token.kind.isTrivia() => break
            case _ => ()
        }
    }
    segments.toArray()
}
