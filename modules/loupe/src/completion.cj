package loupe

import std.collection.*
import std.deriving.*
import std.sort.*
import ginkgo.{Direction, SyntaxElement, SyntaxNodePtr, TextRange, TokenAtOffset}
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind, reparse}
import cjsyntax.ast.{Decl, MemberAccessExpr, RefExpr}
import loupe.db.{AnalysisDatabase, Package, SourceFile}
import loupe.hir.*
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * The name completion inserts at the cursor to parse the file as if one were there, R1's
 * `raCompletionMarker` (D110).
 */
const COMPLETION_MARKER = "cjlsCompletionMarker"

/**
 * The keywords that start an expression or a statement, offered where a name would be.
 */
let EXPRESSION_KEYWORDS =
    [
        "if",
        "match",
        "for",
        "while",
        "do",
        "let",
        "var",
        "func",
        "return",
        "break",
        "continue",
        "this",
        "super",
        "true",
        "false",
        "spawn",
        "try",
        "throw",
        "unsafe"
    ]

/**
 * The keywords that start a member of a type, its modifiers among them, offered between members.
 */
let MEMBER_KEYWORDS =
    [
        "func",
        "let",
        "var",
        "prop",
        "init",
        "operator",
        "const",
        "static",
        "public",
        "private",
        "protected",
        "internal",
        "open",
        "override",
        "redef",
        "mut",
        "unsafe"
    ]

/**
 * The keywords that start a declaration of a file, its modifiers among them; `import` and
 * `package` where the file's preamble may still have one.
 */
let TOP_LEVEL_KEYWORDS =
    [
        "func",
        "class",
        "struct",
        "interface",
        "enum",
        "extend",
        "type",
        "let",
        "var",
        "const",
        "main",
        "macro",
        "public",
        "private",
        "protected",
        "internal",
        "open",
        "abstract",
        "sealed",
        "foreign",
        "unsafe"
    ]

/**
 * The primitive types, keywords offered where a type is.
 */
let PRIM_TYPE_NAMES =
    [
        "Int8",
        "Int16",
        "Int32",
        "Int64",
        "IntNative",
        "UInt8",
        "UInt16",
        "UInt32",
        "UInt64",
        "UIntNative",
        "Float16",
        "Float32",
        "Float64",
        "Rune",
        "Bool",
        "Nothing",
        "Unit"
    ]

/**
 * What a completion item is, for the client to show it as one.
 */
@Derive[Equatable, ToString]
public enum CompletionKind {
    | LocalItem
    | ParamItem
    | FuncItem
    | VarItem
    | PropItem
    | CtorItem
    | ClassItem
    | InterfaceItem
    | StructItem
    | EnumItem
    | TypeAliasItem
    | PkgItem
    | TypeParamItem
    | KeywordItem
}

/**
 * What a completion item stands for, for its detail and documentation when a client asks for them
 * (`completionDetails`): a declaration, as a member of a value of a type if one's; a group of
 * overloads with their receiver types; a local of a body; a member parameter of a primary
 * constructor; nothing, for a keyword or a package.
 */
@Derive[Equatable]
public enum CompletionSource {
    | DeclSource(DefId, ?Ty)
    | OverloadSource(Array<CompletionOverload>)
    | LocalSource(DefId, LocalId)
    | MemberParamSource(DefId, LocalId, ?Ty)
    | NoSource
}

@Derive[Equatable]
public struct CompletionItem {
    public CompletionItem(
        public let label: String,
        public let kind: CompletionKind,
        /**
         * Higher first: a local before a member before the file's scope before a keyword; the
         * client's own match against what was typed comes on top of it.
         */
        public let relevance: Int64,
        public let source: CompletionSource
    ) {}

    /**
     * How many declarations this item offers; counting a group needs no signature query.
     */
    public prop overloadCount: Int64 {
        get() {
            match (source) {
                case OverloadSource(decls) => decls.size
                case _ => 1
            }
        }
    }
}

/**
 * The completions at a cursor: what the item inserted replaces, the name typed so far before the
 * cursor, and the items, the most relevant first.
 */
@Derive[Equatable]
public struct CompletionResult {
    public CompletionResult(public let range: TextRange, public let items: Array<CompletionItem>) {}
}

/**
 * The completions at `offset` of `fileId` (#203): after a `.`, the members of what is before it,
 * a package's declarations, a type's static members and constructors, a value's members on its
 * type; at a name, the locals in scope before it, the members of the type around, the type
 * parameters, the file's scope and the keywords. The position is read in a speculative tree, the
 * file with a name inserted at the cursor (D110); the types and the scopes of the file are its
 * own. `None` where there is nothing to complete.
 */
public func completionsAt(db: AnalysisDatabase, fileId: FileId, offset: Int64): ?CompletionResult {
    let file = db.sourceFile(fileId) ?? return None
    let before = parse(db, file)
    if (offset < 0 || offset > before.green.textLen) {
        return None
    }
    let speculative = reparse(before, TextRange.empty(offset), COMPLETION_MARKER)
    let marker = rightTokenAt(speculative.syntaxNode(), offset) ?? return None
    if (!marker.text().contains(COMPLETION_MARKER)) {
        return None
    }
    let realRoot = before.syntaxNode()
    let parent = marker.parent
    let items =
        if (parent.kind == SyntaxKind.NameRef) {
            nameRefCompletions(db, file, realRoot, offset, parent)
        } else if (parent.kind == SyntaxKind.ErrorNode) {
            keywordCompletions(parent, marker)
        } else if (
            parent.kind == SyntaxKind.Name &&
                (parent.parent?.kind ?? SyntaxKind.ErrorNode) == SyntaxKind.EnumCtor
        ) {
            strayCtorCompletions(parent.parent.getOrThrow(), marker)
        } else if (parent.kind == SyntaxKind.Name) {
            overrideCompletions(db, file, realRoot, offset, parent)
        } else {
            None<Array<CompletionItem>>
        }
    CompletionResult(TextRange(marker.textRange.start, offset), ranked(items ?? return None))
}

/**
 * The completions at the name `nameRef` of the speculative tree, by what it is the name of: a
 * member after a `.`, a name of a body, a type, a segment of an import (#401).
 */
func nameRefCompletions(
    db: AnalysisDatabase,
    file: SourceFile,
    realRoot: CjSyntaxNode,
    offset: Int64,
    nameRef: CjSyntaxNode
): ?Array<CompletionItem> {
    let node = nameRef.parent ?? return None
    if (let Some(access) <- MemberAccessExpr.cast(node)) {
        dotCompletions(
            db,
            file,
            defAround(db, file, realRoot, offset) ?? return None,
            realRoot,
            access
        )
    } else if (RefExpr.canCast(node.kind)) {
        scopeCompletions(
            db,
            file,
            defAround(db, file, realRoot, offset) ?? return None,
            realRoot,
            node
        )
    } else if (
        node.kind == SyntaxKind.PathSegment &&
            (node.parent?.kind ?? SyntaxKind.ErrorNode) == SyntaxKind.PathType
    ) {
        typeCompletions(db, file, defAround(db, file, realRoot, offset), node)
    } else if (node.kind == SyntaxKind.ImportTree) {
        importCompletions(db, file, nameRef, node)
    } else {
        None
    }
}

/**
 * The declarations of `item`, one of the completions at `offset` of `fileId`, as hover shows
 * them, with their paths and doc comments; members as members of the values they were listed
 * on. An overload group resolves every declaration, in list order. Empty if none can be shown.
 * Asked for one item at a time, when the client shows it.
 */
public func completionDetails(
    db: AnalysisDatabase,
    fileId: FileId,
    offset: Int64,
    item: CompletionItem
): Array<HoverItem> {
    let file = db.sourceFile(fileId) ?? return []
    let def = defAround(db, file, parse(db, file).syntaxNode(), offset) ?? return []
    let hovers = Hovers(db, def, None)
    if (let OverloadSource(decls) <- item.source) {
        let details = ArrayList<HoverItem>()
        for (decl in decls) {
            if (let Some(detail) <- hovers.declItem(decl.id, decl.receiver)) {
                details.add(detail)
            }
        }
        return details.toArray()
    }
    let detail: ?HoverItem =
        match (item.source) {
            case DeclSource(id, recv) => hovers.declItem(id, recv)
            case LocalSource(owner, local) => hovers.localItem(owner, local)
            case MemberParamSource(ctor, local, recv) => hovers.memberParamItem(ctor, local, recv)
            case _ => None
        }
    detail.map { one => [one] } ?? []
}

/**
 * The token starting at `offset`, or the one around it.
 */
func rightTokenAt(root: CjSyntaxNode, offset: Int64): ?CjSyntaxToken {
    match (root.tokenAtOffset(offset)) {
        case Single(token) => Some(token)
        case Between(_, right) => Some(right)
        case NoToken => None
    }
}

/**
 * The item the cursor at `offset` is in, of the file's own tree.
 */
func defAround(db: AnalysisDatabase, file: SourceFile, root: CjSyntaxNode, offset: Int64): ?DefId {
    let token =
        match (root.tokenAtOffset(offset)) {
            case Single(token) => token
            case Between(left, _) => left
            case NoToken => return None
        }
    itemAround(db, ItemFile.Source(file), token.parent)
}

/**
 * The node of the file's own tree that `range` and `kind` name: the one the speculative tree has
 * before the cursor, where the two trees are the same text.
 */
func realNodeAt(root: CjSyntaxNode, range: TextRange, kind: SyntaxKind): ?CjSyntaxNode {
    if (!root.textRange.containsRange(range)) {
        return None
    }
    var node =
        match (root.coveringElement(range)) {
            case SyntaxElement.Node(n) => Some(n)
            case SyntaxElement.Token(t) => Some(t.parent)
        }
    while (let Some(n) <- node) {
        if (n.textRange == range && n.kind == kind) {
            return n
        }
        if (n.textRange.start < range.start || n.textRange.end > range.end) {
            return None
        }
        node = n.parent
    }
    None
}

/**
 * The completions after the `.` of `access`, of the speculative tree: of what its receiver, which
 * the file's own tree has too, stands for (D52).
 */
func dotCompletions(
    db: AnalysisDatabase,
    file: SourceFile,
    def: DefId,
    realRoot: CjSyntaxNode,
    access: MemberAccessExpr
): Array<CompletionItem> {
    let receiver = (access.receiver() ?? return []).syntax
    let real = realNodeAt(realRoot, receiver.textRange, receiver.kind) ?? return []
    let expr = bodyWithSourceMap(db, def).sourceMap.exprAt(SyntaxNodePtr(real)) ?? return []
    let from = scopeFileOf(db, ItemFile.Source(file))
    // `this` and `super` name the type around (N79) but are values of it: its instance members
    let isObject =
        match (body(db, def)[expr]) {
            case ThisExpr | SuperExpr => true
            case _ => false
        }
    match (receiverOf(db, def, expr)) {
        case PackageReceiver(pkg) => packageMembers(db, file, pkg)
        case TypesReceiver(types) =>
            let on = receiverTyOf(db, def, expr)
            allMembers(db, types, from: from, on: on) |>
                filter { target: MemberTarget => isStaticMember(db, target) != isObject } |>
                filterMap { target: MemberTarget => memberItem(db, def, target, on, 80) } |>
                collectArray
        case ValueReceiver =>
            let ty = inferBody(db, def)[expr] ?? return []
            valueMembers(db, file, def, ty)
        case NoReceiver => []
    }
}

/**
 * The members of a value of the type `ty`: those of its heads, a type parameter's bounds', that
 * are not static (cjc: `object cannot access static member`).
 */
func valueMembers(
    db: AnalysisDatabase,
    file: SourceFile,
    def: DefId,
    ty: Ty
): Array<CompletionItem> {
    let from = scopeFileOf(db, ItemFile.Source(file))
    let found = ArrayList<CompletionItem>()
    for (head in headTysOf(db, ty)) {
        let start =
            match (head.kind(db)) {
                case DeclTy(id, _) => ExtendedType.DeclType(id)
                case PrimTy(name) => ExtendedType.PrimType(name)
                case BuiltInTy(kind, _) => ExtendedType.BuiltInHead(kind)
                case _ => continue
            }
        for (
            target in allMembers(db, [start], from: from, on: head) where !isStaticMember(
                db,
                target
            )
        ) {
            if (let Some(item) <- memberItem(db, def, target, head, 80)) {
                found.add(item)
            }
        }
    }
    found.toArray()
}

/**
 * The declarations of `pkg` after its name and a `.`, those the file's package sees (N76): no
 * constructor, no package under it; its types alone with `typesOnly`.
 */
func packageMembers(
    db: AnalysisDatabase,
    file: SourceFile,
    pkg: PackageRef,
    typesOnly!: Bool = false
): Array<CompletionItem> {
    let from = packageOfFile(db, file) ?? return []
    let relation = relationOf(from.name(db), nameOf(db, pkg))
    let found = ArrayList<CompletionItem>()
    for ((name, defs) in packageExports(db, pkg).names) {
        for (
            id in visibleOf(defs, relation, Visibility.Private) where !typesOnly ||
                isTypeItem(id.item(db).kind)
        ) {
            if (let Some(item) <- declCompletion(db, id, name, 80)) {
                found.add(item)
            }
        }
    }
    found.toArray()
}

/**
 * Whether `target` is reached through its type rather than a value of it: a static member, or an
 * enum's constructor.
 */
func isStaticMember(db: AnalysisDatabase, target: MemberTarget): Bool {
    match (target) {
        case MemberDecl(id) =>
            id.item(db).kind == ItemKind.EnumCtor || (itemOf(db, id)?.has(Modifier.Static) ?? false)
        case MemberParam(_, _) => false
    }
}

/**
 * The member `target` as an item, seen on the type `recv` if one's, if it is no operator function
 * (called by its operator, never by name) and the body of `def` may access it (N80: what the
 * lookup finds whatever its modifiers, the use checks): a `private` member inside its type, a
 * `protected` one in its package or a subtype, an `internal` one as its package is seen.
 */
func memberItem(
    db: AnalysisDatabase,
    def: DefId,
    target: MemberTarget,
    recv: ?Ty,
    relevance: Int64
): ?CompletionItem {
    match (target) {
        case MemberDecl(id) =>
            let item = itemOf(db, id) ?? return None
            if (item.has(Modifier.Operator) || !isAccessibleMember(db, def, id, item)) {
                return None
            }
            let kind = kindOfItem(item.kind) ?? return None
            CompletionItem(item.names.get(0) ?? return None, kind, relevance, DeclSource(id, recv))
        case MemberParam(ctor, local) =>
            let name = body(db, ctor).locals.get(local.index)?.name ?? return None
            CompletionItem(name, VarItem, relevance, MemberParamSource(ctor, local, recv))
    }
}

/**
 * Whether the body of `def` may access the member `id`, by its modifiers: `private` only in the
 * type or `extend` declaring it, `protected` in its package or a subtype of it, `internal` and
 * `public` as the member's package is seen from the body's.
 */
func isAccessibleMember(db: AnalysisDatabase, def: DefId, id: DefId, item: Item): Bool {
    let owner = parentOf(db, id)
    let ownerType = owner.flatMap { one => ownerTypeOf(db, one) }
    let around = enclosingTypeOf(db, def)
    match (visibilityOf(item)) {
        case Visibility.Private => owner.isSome() && owner == parentOf(db, def)
        case Visibility.Protected =>
            samePackage(db, def, id) ||
                (
                    ownerType.isSome() && around.isSome() &&
                        isSubtypeOf(db, around.getOrThrow(), ownerType.getOrThrow())
                )
        case level =>
            level
                .isSeen(
                    by: relationOf(
                        packageNameOf(db, def) ?? return false,
                        packageNameOf(db, id) ?? return false
                    )
                )
    }
}

/**
 * The type `owner`, a type or an `extend`, declares the members of.
 */
func ownerTypeOf(db: AnalysisDatabase, owner: DefId): ?ExtendedType {
    match (owner.item(db).kind) {
        case Extend => extendedTypeOf(db, owner)
        case BuiltIn => compilerTypeOf(db, owner).map { kind => ExtendedType.BuiltInHead(kind) }
        case Class | Interface | Struct | Enum => ExtendedType.DeclType(owner)
        case _ => None
    }
}

/**
 * Whether `ty` is `other` or inherits from it, through its `extend`s' supertypes too.
 */
func isSubtypeOf(db: AnalysisDatabase, ty: ExtendedType, other: ExtendedType): Bool {
    let seen = HashSet<ExtendedType>([ty])
    var level = [ty]
    while (!level.isEmpty()) {
        if (level.contains(other)) {
            return true
        }
        let next = ArrayList<ExtendedType>()
        for (one in level) {
            let supers =
                match (one) {
                    case DeclType(id) => supertypes(db, id)
                    case PrimType(_) | BuiltInHead(_) => Array<ExtendedType>()
                }
            for (sup in supers where seen.add(sup)) {
                next.add(sup)
            }
        }
        level = next.toArray()
    }
    false
}

func samePackage(db: AnalysisDatabase, a: DefId, b: DefId): Bool {
    match ((packageNameOf(db, a), packageNameOf(db, b))) {
        case (Some(x), Some(y)) => x == y
        case _ => false
    }
}

/**
 * The name of the package declaring `id`.
 */
func packageNameOf(db: AnalysisDatabase, id: DefId): ?String {
    match (id.file(db)) {
        case Binary(binary, _) => binary.name(db)
        case CompilerBuiltIns(pkg) => pkg.name(db)
        case file => scopeFileOf(db, file).flatMap { one => packageOfFile(db, one) }?.name(db)
    }
}

/**
 * The declaration `id` as the item named `name`, of a scope, at `relevance`; `None` for what is
 * never completed, an import or a macro call.
 */
func declCompletion(
    db: AnalysisDatabase,
    id: DefId,
    name: String,
    relevance: Int64
): ?CompletionItem {
    let kind = kindOfItem(id.item(db).kind) ?? return None
    CompletionItem(name, kind, relevance, DeclSource(id, None))
}

func kindOfItem(kind: ItemKind): ?CompletionKind {
    match (kind) {
        case Func | Main | Macro => Some(FuncItem)
        case Var => Some(VarItem)
        case Prop => Some(PropItem)
        case EnumCtor | Init | PrimaryInit => Some(CtorItem)
        case Class => Some(ClassItem)
        case Interface => Some(InterfaceItem)
        case Struct => Some(StructItem)
        case Enum => Some(EnumItem)
        case TypeAlias | BuiltIn => Some(TypeAliasItem)
        case Import | Extend | Finalizer | MacroCall => None
    }
}

/**
 * The completions at the name `nameRef`, a `RefExpr` of the speculative tree, in the body of `def`:
 * the locals in scope there, from the speculative body's scopes (the file's own has no expression
 * at the cursor); the type parameters; the members of the type around, those a static body may
 * use in one; the file's scope, its package's declarations, its imports and their globs, the
 * prelude last; and the keywords.
 */
func scopeCompletions(
    db: AnalysisDatabase,
    file: SourceFile,
    def: DefId,
    realRoot: CjSyntaxNode,
    nameRef: CjSyntaxNode
): Array<CompletionItem> {
    let found = ArrayList<CompletionItem>()
    let own = ItemFile.Source(file)
    localCompletions(db, file, def, realRoot, nameRef, found)
    for (generic in signature(db, def).generics) {
        found.add(CompletionItem(generic, TypeParamItem, 85, NoSource))
    }
    if (let Some(around) <- enclosingTypeOf(db, def)) {
        let inStatic = itemOf(db, def)?.has(Modifier.Static) ?? false
        let selfTy = selfTyAround(db, def)
        for (target in allMembers(db, [around], from: scopeFileOf(db, own), on: selfTy)) {
            if (inStatic && !isStaticMember(db, target)) {
                continue
            }
            if (let Some(item) <- memberItem(db, def, target, selfTy, 80)) {
                found.add(item)
            }
        }
        if (let Some(parent) <- parentOf(db, def)) {
            for (generic in signature(db, parent).generics) {
                found.add(CompletionItem(generic, TypeParamItem, 75, NoSource))
            }
        }
    }
    fileScopeCompletions(db, file, found, typesOnly: false)
    for (keyword in EXPRESSION_KEYWORDS) {
        found.add(CompletionItem(keyword, KeywordItem, 10, NoSource))
    }
    found.toArray()
}

/**
 * The file's scope as items, into `found`: its package's declarations, its imports, the
 * constructors its package imports (N73), its globs' exports, the prelude's last. With `typesOnly`,
 * the types and the packages it imports alone, what a type's path may start with.
 */
func fileScopeCompletions(
    db: AnalysisDatabase,
    file: SourceFile,
    found: ArrayList<CompletionItem>,
    typesOnly!: Bool
): Unit {
    let own = ItemFile.Source(file)
    let wanted = { id: DefId => !typesOnly || isTypeItem(id.item(db).kind) }
    let pkg = packageOfFile(db, file) ?? return
    let declared = defMap(db, PackageRef.Source(pkg))
    for ((name, defs) in declared.names) {
        for (
            one in defs where (one.visibility != Visibility.Private || one.id.file(db) == own) &&
                wanted(one.id)
        ) {
            if (let Some(item) <- declCompletion(db, one.id, name, 60)) {
                found.add(item)
            }
        }
    }
    let imports = fileImports(db, pkg, file)
    for ((name, imported) in imports.names) {
        for (one in imported) {
            match (one.target) {
                case OfDecl(id) =>
                    if (wanted(id)) {
                        if (let Some(item) <- declCompletion(db, id, name, 50)) {
                            found.add(item)
                        }
                    }
                case OfPackage(_) => found.add(CompletionItem(name, PkgItem, 50, NoSource))
            }
        }
    }
    let prelude = preludeOf(db, pkg)
    let relevanceOf =
        {
            glob: Glob =>
            if (prelude.map { one => one.pkg == glob.pkg } ?? false) { 30 } else { 40 }
        }
    for (glob in imports.globs) {
        for ((name, defs) in packageExports(db, glob.pkg).names) {
            for (id in visibleOf(defs, glob.relation, glob.level) where wanted(id)) {
                if (let Some(item) <- declCompletion(db, id, name, relevanceOf(glob))) {
                    found.add(item)
                }
            }
        }
    }
    if (typesOnly) {
        return
    }
    for ((name, defs) in declared.ctors) {
        for (one in defs where one.visibility != Visibility.Private || one.id.file(db) == own) {
            found.add(CompletionItem(name, CtorItem, 60, DeclSource(one.id, None)))
        }
    }
    // the constructors of the enums any file of the package imports (N73)
    let ctorImports = ctorImportsOf(db, pkg, file)
    for ((name, ids) in ctorImports.ctors) {
        for (id in ids) {
            found.add(CompletionItem(name, CtorItem, 50, DeclSource(id, None)))
        }
    }
    for (glob in ctorImports.globs) {
        for ((name, defs) in packageExports(db, glob.pkg).ctors) {
            for (id in visibleOf(defs, glob.relation, glob.level)) {
                found.add(CompletionItem(name, CtorItem, relevanceOf(glob), DeclSource(id, None)))
            }
        }
    }
}

func isTypeItem(kind: ItemKind): Bool {
    match (kind) {
        case Class | Interface | Struct | Enum | TypeAlias | BuiltIn => true
        case _ => false
    }
}

/**
 * The locals in scope at `nameRef` of the speculative tree, and the type parameters of the local
 * functions around it: the body of the item at the cursor lowered from that tree, its scopes
 * walked from the expression the name is (D50); each local the file's own body has it as, by the
 * node declaring it, which is before the cursor and so the same in both trees.
 */
func localCompletions(
    db: AnalysisDatabase,
    file: SourceFile,
    def: DefId,
    realRoot: CjSyntaxNode,
    nameRef: CjSyntaxNode,
    into: ArrayList<CompletionItem>
): Unit {
    let (_, ids) = syntaxOf(db, ItemFile.Source(file)) ?? return
    let start = (ids.node(def.item(db), realRoot) ?? return).textRange.start
    let decl =
        (
            nameRef.ancestors() |> filter { one: CjSyntaxNode => one.textRange.start == start } |>
                filterMap { one: CjSyntaxNode => Decl.cast(one) } |>
                first
        ) ??
            return
    let speculative = lowerBody(decl, active: ActiveFilter.of(db, file))
    let real = bodyWithSourceMap(db, def).sourceMap
    let scopes = scopesOf(speculative.body)
    let expr = speculative.sourceMap.exprAt(SyntaxNodePtr(nameRef)) ?? return
    let chain = scopes.chain(scopes.scopeOf(expr))
    let seen = HashSet<String>()
    for (depth in 0..chain.size) {
        let scope = scopes[chain[depth]]
        for (local in scope.entries) {
            let declared = speculative.body[local]
            if (!seen.add(declared.name)) {
                continue
            }
            let kind =
                match (declared.kind) {
                    case ParamLocal | LambdaParamLocal => ParamItem
                    case FuncLocal => FuncItem
                    case _ => LocalItem
                }
            let source =
                match (speculative.sourceMap.locals.get(local.index)) {
                    case Some(WrittenSource(source)) =>
                        match (real.localAtSource(source)) {
                            case Some(one) => LocalSource(def, one)
                            case None => NoSource
                        }
                    case _ => NoSource
                }
            into.add(CompletionItem(declared.name, kind, 100 - depth, source))
        }
        for (generic in scope.generics) {
            into.add(CompletionItem(generic, TypeParamItem, 90 - depth, NoSource))
        }
    }
}

/**
 * The completions at the segment `segment` of a type's path of the speculative tree, in `def` if
 * the cursor is in an item: the first, the type parameters of `def` and of the type around it, the
 * types of the file's scope, the packages it imports, the primitive types; after a package's name
 * and a `.`, the types it exports (N51, N52: a path's qualifier is an imported package).
 */
func typeCompletions(
    db: AnalysisDatabase,
    file: SourceFile,
    def: ?DefId,
    segment: CjSyntaxNode
): ?Array<CompletionItem> {
    let path = segment.parent ?? return None
    let before =
        path.children() |>
            filter {
                one: CjSyntaxNode =>
                one.kind == SyntaxKind.PathSegment && one.textRange.end <= segment.textRange.start
            } |>
            collectArray
    let found = ArrayList<CompletionItem>()
    if (before.size == 1) {
        let qualifier = before[0].firstToken()?.text() ?? return None
        let pkg = packageOfFile(db, file) ?? return None
        for (one in fileImports(db, pkg, file).names.get(qualifier) ?? []) {
            if (let OfPackage(ref) <- one.target) {
                found.add(all: packageMembers(db, file, ref, typesOnly: true))
            }
        }
        return found.toArray()
    }
    if (before.size > 1) {
        return None
    }
    if (let Some(scope) <- def.flatMap { one => typeScopeOf(db, one) }) {
        for (i in 0..scope.generics.size) {
            for (name in scope.generics[i].names) {
                found.add(CompletionItem(name, TypeParamItem, 85 - 10 * i, NoSource))
            }
        }
    }
    fileScopeCompletions(db, file, found, typesOnly: true)
    for (name in PRIM_TYPE_NAMES) {
        found.add(CompletionItem(name, KeywordItem, 20, NoSource))
    }
    found.toArray()
}

/**
 * The completions at the name `nameRef` of the import tree `tree`, of the speculative tree: the
 * next segment of each package the file's module may import (D46) whose name starts with what is
 * written before it, and after a package's full name and a `.`, what that package exports.
 */
func importCompletions(
    db: AnalysisDatabase,
    file: SourceFile,
    nameRef: CjSyntaxNode,
    tree: CjSyntaxNode
): ?Array<CompletionItem> {
    let prefix = importPrefix(nameRef, tree)
    let pkg = packageOfFile(db, file) ?? return None
    let from = PackageRef.Source(pkg)
    let index = packageIndex(db)
    let ofTests = isTestOf(db, pkg, file)
    let scope = index.scopeOf(from, ofTests: ofTests)
    let own = pkg.name(db)
    let found = ArrayList<CompletionItem>()
    for (
        (name, candidates) in index.packages where name != own && name.size > prefix.size &&
            name.startsWith(prefix)
    ) {
        if (candidates.iterator().any { one => scope.contains(one.owner) }) {
            found.add(CompletionItem(nextSegment(name[prefix.size..]), PkgItem, 70, NoSource))
        }
    }
    if (prefix.endsWith(".")) {
        if (
            let Some(ref) <- index.find(prefix[..prefix.size - 1], from: from, ofTests: ofTests) &&
                ref != from
        ) {
            found.add(all: packageMembers(db, file, ref))
        }
    }
    found.toArray()
}

/**
 * What an import writes before `nameRef`, without trivia: the segments of `tree` before it, after
 * those of the trees whose `{...}` it is in (`m.{lib.$0}` is `m.lib.`).
 */
func importPrefix(nameRef: CjSyntaxNode, tree: CjSyntaxNode): String {
    var prefix = textBefore(tree, nameRef.textRange.start)
    var inner = tree
    while (let Some(list) <- inner.parent && list.kind == SyntaxKind.ImportTreeList) {
        let outer = list.parent ?? break
        prefix = "${textBefore(outer, list.textRange.start)}${prefix}"
        inner = outer
    }
    prefix
}

/**
 * The tokens of `node` before `end`, without trivia.
 */
func textBefore(node: CjSyntaxNode, end: Int64): String {
    let parts = ArrayList<String>()
    var token = node.firstToken()
    while (let Some(one) <- token && one.textRange.end <= end) {
        if (!one.kind.isTrivia()) {
            parts.add(one.text())
        }
        token = one.nextToken()
    }
    String.join(parts.toArray())
}

/**
 * The first segment of `rest`, a package's name past a prefix: up to a `.`, or an organization's
 * `::`.
 */
func nextSegment(rest: String): String {
    var end = rest.size
    if (let Some(i) <- rest.indexOf(".")) {
        end = i
    }
    if (let Some(i) <- rest.indexOf("::") && i < end) {
        end = i
    }
    rest[..end]
}

/**
 * The keywords where `error`, a line the parser could not take as a declaration, starts with the
 * cursor's name and the cursor is at its end (inside a word, `str|uct`, it is no keyword typed):
 * between the members of a type, those starting a member; at the top level, those starting a
 * declaration, and `import` and `package` while only the preamble is before it.
 */
func keywordCompletions(error: CjSyntaxNode, marker: CjSyntaxToken): ?Array<CompletionItem> {
    if (!isKeywordTyped(error, marker)) {
        return None
    }
    let container = error.parent ?? return None
    let keywords =
        if (container.kind == SyntaxKind.DeclBody || container.kind == SyntaxKind.EnumBody) {
            MEMBER_KEYWORDS
        } else if (container.kind == SyntaxKind.SourceFile) {
            TOP_LEVEL_KEYWORDS.concat(preambleKeywords(container, error))
        } else {
            return None
        }
    keywords.map { keyword => CompletionItem(keyword, KeywordItem, 10, NoSource) }
}

/**
 * The keywords starting a member where `ctor`, an enum's constructor of the speculative tree, is
 * the cursor's name after the constructors with no `|` before it, which cjc takes as a member
 * ("expected declaration"); not the first, which needs no `|`: cjc starts an enum's body with a
 * constructor.
 */
func strayCtorCompletions(ctor: CjSyntaxNode, marker: CjSyntaxToken): ?Array<CompletionItem> {
    if (!isKeywordTyped(ctor, marker)) {
        return None
    }
    let before =
        ctor.siblingsWithTokens(Direction.Prev) |> skip(1) |>
            filter { element: SyntaxElement<SyntaxKind> => !element.kind.isTrivia() } |>
            first
    match (before) {
        case Some(element) where element.kind != SyntaxKind.Pipe &&
                element.kind != SyntaxKind.LBrace =>
            MEMBER_KEYWORDS.map { keyword => CompletionItem(keyword, KeywordItem, 10, NoSource) }
        case _ => None
    }
}

/**
 * Whether `node` starts with the cursor's name and the cursor is at its end: inside a word,
 * `str|uct`, it is no keyword typed.
 */
func isKeywordTyped(node: CjSyntaxNode, marker: CjSyntaxToken): Bool {
    (node.firstToken()?.textRange.start ?? -1) == marker.textRange.start &&
        marker.text().endsWith(COMPLETION_MARKER)
}

/**
 * `import`, and `package` before any import, while what is before `error` in `file` is its
 * preamble alone (cjc: a package header, then the imports, then the declarations).
 */
func preambleKeywords(file: CjSyntaxNode, error: CjSyntaxNode): Array<String> {
    var started = false
    var imported = false
    for (
        one in file.children() where one.textRange.end <= error.textRange.start &&
            one.kind != SyntaxKind.ErrorNode
    ) {
        if (one.kind == SyntaxKind.PackageHeader || one.kind == SyntaxKind.ImportDecl) {
            imported = true
        } else if (one.kind != SyntaxKind.FeaturesDirective) {
            started = true
        }
    }
    if (started) {
        []
    } else if (imported) {
        ["import"]
    } else {
        ["import", "package"]
    }
}

/**
 * The completions at the name `name` of a function or a property declared in a type's body, of
 * the speculative tree: the members of that kind of its supertypes a declaration there may
 * override or redefine, static ones after `static`, and not one the type declares already.
 */
func overrideCompletions(
    db: AnalysisDatabase,
    file: SourceFile,
    realRoot: CjSyntaxNode,
    offset: Int64,
    name: CjSyntaxNode
): ?Array<CompletionItem> {
    let decl = name.parent ?? return None
    let kind =
        if (decl.kind == SyntaxKind.FuncDecl) {
            ItemKind.Func
        } else if (decl.kind == SyntaxKind.PropDecl) {
            ItemKind.Prop
        } else {
            return None
        }
    if ((decl.parent?.kind ?? SyntaxKind.ErrorNode) != SyntaxKind.DeclBody) {
        return None
    }
    let around = typeDefOf(db, defAround(db, file, realRoot, offset) ?? return None) ?? return None
    let isStatic = hasModifier(decl, "static")
    let declared = HashSet<String>()
    for (member in itemOf(db, around)?.members ?? [] where member.kind == kind) {
        declared.add(all: member.names)
    }
    let from = scopeFileOf(db, ItemFile.Source(file))
    let found = ArrayList<CompletionItem>()
    for (target in allMembers(db, supertypes(db, around), from: from)) {
        let id =
            match (target) {
                case MemberDecl(id) => id
                case MemberParam(_, _) => continue
            }
        let item = itemOf(db, id) ?? continue
        let label = item.names.get(0) ?? continue
        if (
            item.kind != kind || item.has(Modifier.Static) != isStatic ||
                declared.contains(label) ||
                visibilityOf(item) == Visibility.Private ||
                !isOverridable(db, id, item)
        ) {
            continue
        }
        found.add(CompletionItem(label, kindOfItem(kind) ?? continue, 80, DeclSource(id, None)))
    }
    found.toArray()
}

/**
 * The type or `extend` `def` is, or is a member of.
 */
func typeDefOf(db: AnalysisDatabase, def: DefId): ?DefId {
    match (def.item(db).kind) {
        case Class | Interface | Struct | Enum | Extend => def
        case _ =>
            parentOf(db, def)
                .flatMap {
                    parent =>
                    match (parent.item(db).kind) {
                        case Class | Interface | Struct | Enum | Extend => Some(parent)
                        case _ => None
                    }
                }
    }
}

/**
 * Whether a subtype may override or redefine the member `id`: one of an interface, a static one,
 * one `open` or `abstract`, or one of an `abstract` class, whose members without a body are open.
 */
func isOverridable(db: AnalysisDatabase, id: DefId, item: Item): Bool {
    if (item.has(Modifier.Static) || item.has(Modifier.Open) || item.has(Modifier.Abstract)) {
        return true
    }
    let owner = itemOf(db, parentOf(db, id) ?? return false) ?? return false
    owner.kind == ItemKind.Interface || owner.has(Modifier.Abstract)
}

/**
 * Whether the declaration `decl` of the tree writes the modifier `text`.
 */
func hasModifier(decl: CjSyntaxNode, text: String): Bool {
    for (child in decl.children() where child.kind == SyntaxKind.Modifiers) {
        for (element in child.descendantsWithTokens()) {
            if (let Some(token) <- element.asToken() && token.text() == text) {
                return true
            }
        }
    }
    false
}

/**
 * `items` the most relevant first, then by name, each once: a name shadowed by a nearer one is
 * gone, but for functions and constructors, whose overloads share one item (D149).
 */
func ranked(items: Array<CompletionItem>): Array<CompletionItem> {
    let sorted = items.clone()
    sort(
        sorted,
        stable: true,
        by: {
            a: CompletionItem, b: CompletionItem =>
            match (b.relevance.compare(a.relevance)) {
                case Ordering.EQ => a.label.compare(b.label)
                case other => other
            }
        }
    )
    let seen = HashSet<String>()
    let kept = ArrayList<CompletionItem>()
    for (item in sorted) {
        let key =
            match ((item.kind, item.source)) {
                case (FuncItem, DeclSource(id, _)) => "${item.label}#${id.hashCode()}"
                case (CtorItem, DeclSource(id, _)) => "${item.label}#${id.hashCode()}"
                case _ => "${item.label}#${item.kind}"
            }
        if (seen.add(key)) {
            kept.add(item)
        }
    }
    groupCompletionOverloads(kept.toArray())
}
