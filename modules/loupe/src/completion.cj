package loupe

import std.collection.*
import std.deriving.*
import std.sort.*
import ginkgo.{SyntaxElement, SyntaxNodePtr, TextRange, TokenAtOffset}
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
let COMPLETION_MARKER = "cjlsCompletionMarker"

/**
 * The keywords that start an expression or a statement, offered where a name would be.
 */
let EXPRESSION_KEYWORDS = ["if", "match", "for", "while", "do", "let", "var", "func", "return", "break", "continue",
    "this", "super", "true", "false", "spawn", "try", "throw", "unsafe"]

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
 * (`completionDetail`): a declaration, as a member of a value of a type if one's; a local of a
 * body; a member parameter of a primary constructor; nothing, for a keyword or a package.
 */
@Derive[Equatable]
public enum CompletionSource {
    | DeclSource(DefId, ?Ty)
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
    let nameRef = marker.parent
    if (nameRef.kind != SyntaxKind.NameRef) {
        return None
    }
    let node = nameRef.parent ?? return None
    let realRoot = before.syntaxNode()
    let def = defAround(db, file, realRoot, offset) ?? return None
    let items = if (let Some(access) <- MemberAccessExpr.cast(node)) {
        dotCompletions(db, file, def, realRoot, access)
    } else if (RefExpr.canCast(node.kind)) {
        scopeCompletions(db, file, def, realRoot, node)
    } else {
        return None
    }
    CompletionResult(TextRange(marker.textRange.start, offset), ranked(items))
}

/**
 * The detail of `item`, one of the completions at `offset` of `fileId`: its declaration as hover
 * shows it, with its path and its doc comment; a member as a member of the value it was listed
 * on. Asked for one item at a time, when the client shows it.
 */
public func completionDetail(db: AnalysisDatabase, fileId: FileId, offset: Int64, item: CompletionItem): ?HoverItem {
    let file = db.sourceFile(fileId) ?? return None
    let def = defAround(db, file, parse(db, file).syntaxNode(), offset) ?? return None
    let hovers = Hovers(db, def, None)
    match (item.source) {
        case DeclSource(id, recv) => hovers.declItem(id, recv)
        case LocalSource(owner, local) => hovers.localItem(owner, local)
        case MemberParamSource(ctor, local, recv) => hovers.memberParamItem(ctor, local, recv)
        case NoSource => None
    }
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
    let token = match (root.tokenAtOffset(offset)) {
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
    var node = match (root.coveringElement(range)) {
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
func dotCompletions(db: AnalysisDatabase, file: SourceFile, def: DefId, realRoot: CjSyntaxNode,
    access: MemberAccessExpr): Array<CompletionItem> {
    let receiver = (access.receiver() ?? return []).syntax
    let real = realNodeAt(realRoot, receiver.textRange, receiver.kind) ?? return []
    let expr = bodyWithSourceMap(db, def).sourceMap.exprAt(SyntaxNodePtr(real)) ?? return []
    let from = scopeFileOf(db, ItemFile.Source(file))
    match (receiverOf(db, def, expr)) {
        case PackageReceiver(pkg) => packageMembers(db, file, pkg)
        case TypesReceiver(types) =>
            let on = receiverTyOf(db, def, expr)
            allMembers(db, types, from: from, on: on) |> filter {target: MemberTarget => isStaticMember(db, target)} |>
                filterMap {target: MemberTarget => memberItem(db, def, target, on, 80)} |> collectArray
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
func valueMembers(db: AnalysisDatabase, file: SourceFile, def: DefId, ty: Ty): Array<CompletionItem> {
    let from = scopeFileOf(db, ItemFile.Source(file))
    let found = ArrayList<CompletionItem>()
    for (head in headTysOf(db, ty)) {
        let start = match (head.kind(db)) {
            case DeclTy(id, _) => ExtendedType.DeclType(id)
            case PrimTy(name) => ExtendedType.PrimType(name)
            case _ => continue
        }
        for (target in allMembers(db, [start], from: from, on: head) where !isStaticMember(db, target)) {
            if (let Some(item) <- memberItem(db, def, target, head, 80)) {
                found.add(item)
            }
        }
    }
    found.toArray()
}

/**
 * The declarations of `pkg` after its name and a `.`, those the file's package sees (N76): no
 * constructor, no package under it.
 */
func packageMembers(db: AnalysisDatabase, file: SourceFile, pkg: PackageRef): Array<CompletionItem> {
    let from = packageOfFile(db, file) ?? return []
    let relation = relationOf(from.name(db), nameOf(db, pkg))
    let found = ArrayList<CompletionItem>()
    for ((name, defs) in packageExports(db, pkg).names) {
        for (id in visibleOf(defs, relation, Visibility.Private)) {
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
            id.item(db).kind == ItemKind.EnumCtor || (declItemOf(db, id)?.has(Modifier.Static) ?? false)
        case MemberParam(_, _) => false
    }
}

/**
 * The member `target` as an item, seen on the type `recv` if one's, if the body of `def` may
 * access it (N80: what the lookup finds whatever its modifiers, the use checks): a `private`
 * member inside its type, a `protected` one in its package or a subtype, an `internal` one as
 * its package is seen.
 */
func memberItem(db: AnalysisDatabase, def: DefId, target: MemberTarget, recv: ?Ty, relevance: Int64): ?CompletionItem {
    match (target) {
        case MemberDecl(id) =>
            let item = declItemOf(db, id) ?? return None
            if (!isAccessibleMember(db, def, id, item)) {
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
    let ownerType = owner.flatMap {one => ownerTypeOf(db, one)}
    let around = enclosingTypeOf(db, def)
    match (visibilityOf(item)) {
        case Visibility.Private => owner.isSome() && owner == parentOf(db, def)
        case Visibility.Protected => samePackage(db, def, id) || (ownerType.isSome() && around.isSome() &&
            isSubtypeOf(db, around.getOrThrow(), ownerType.getOrThrow()))
        case level => level.isSeen(by: relationOf(packageNameOf(db, def) ?? return false,
            packageNameOf(db, id) ?? return false))
    }
}

/**
 * The type `owner`, a type or an `extend`, declares the members of.
 */
func ownerTypeOf(db: AnalysisDatabase, owner: DefId): ?ExtendedType {
    match (owner.item(db).kind) {
        case Extend => extendedTypeOf(db, owner)
        case Class | Interface | Struct | Enum | BuiltIn => ExtendedType.DeclType(owner)
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
            let supers = match (one) {
                case DeclType(id) => supertypes(db, id)
                case PrimType(_) => Array<ExtendedType>()
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
        case file => scopeFileOf(db, file).flatMap {one => packageOfFile(db, one)}?.name(db)
    }
}

/**
 * The declaration `id` as the item named `name`, of a scope, at `relevance`; `None` for what is
 * never completed, an import or a macro call.
 */
func declCompletion(db: AnalysisDatabase, id: DefId, name: String, relevance: Int64): ?CompletionItem {
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
func scopeCompletions(db: AnalysisDatabase, file: SourceFile, def: DefId, realRoot: CjSyntaxNode,
    nameRef: CjSyntaxNode): Array<CompletionItem> {
    let found = ArrayList<CompletionItem>()
    let own = ItemFile.Source(file)
    localCompletions(db, file, def, realRoot, nameRef, found)
    for (generic in signature(db, def).generics) {
        found.add(CompletionItem(generic, TypeParamItem, 85, NoSource))
    }
    if (let Some(around) <- enclosingTypeOf(db, def)) {
        let inStatic = declItemOf(db, def)?.has(Modifier.Static) ?? false
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
    let pkg = packageOfFile(db, file) ?? return found.toArray()
    let declared = defMap(db, PackageRef.Source(pkg))
    for ((name, defs) in declared.names) {
        for (one in defs where one.visibility != Visibility.Private || one.id.file(db) == own) {
            if (let Some(item) <- declCompletion(db, one.id, name, 60)) {
                found.add(item)
            }
        }
    }
    for ((name, defs) in declared.ctors) {
        for (one in defs where one.visibility != Visibility.Private || one.id.file(db) == own) {
            found.add(CompletionItem(name, CtorItem, 60, DeclSource(one.id, None)))
        }
    }
    let imports = fileImports(db, pkg, file)
    for ((name, imported) in imports.names) {
        for (one in imported) {
            match (one.target) {
                case OfDecl(id) => if (let Some(item) <- declCompletion(db, id, name, 50)) {
                    found.add(item)
                }
                case OfPackage(_) => found.add(CompletionItem(name, PkgItem, 50, NoSource))
            }
        }
    }
    // the constructors of the enums any file of the package imports (N73)
    let ctorImports = packageCtorImports(db, pkg)
    for ((name, ids) in ctorImports.ctors) {
        for (id in ids) {
            found.add(CompletionItem(name, CtorItem, 50, DeclSource(id, None)))
        }
    }
    let prelude = preludeOf(db, pkg)
    let relevanceOf = {glob: Glob => if (prelude.map {one => one.pkg == glob.pkg} ?? false) {
        30
    } else {
        40
    }}
    for (glob in imports.globs) {
        for ((name, defs) in packageExports(db, glob.pkg).names) {
            for (id in visibleOf(defs, glob.relation, glob.level)) {
                if (let Some(item) <- declCompletion(db, id, name, relevanceOf(glob))) {
                    found.add(item)
                }
            }
        }
    }
    for (glob in ctorImports.globs) {
        for ((name, defs) in packageExports(db, glob.pkg).ctors) {
            for (id in visibleOf(defs, glob.relation, glob.level)) {
                found.add(CompletionItem(name, CtorItem, relevanceOf(glob), DeclSource(id, None)))
            }
        }
    }
    for (keyword in EXPRESSION_KEYWORDS) {
        found.add(CompletionItem(keyword, KeywordItem, 10, NoSource))
    }
    found.toArray()
}

/**
 * The locals in scope at `nameRef` of the speculative tree, and the type parameters of the local
 * functions around it: the body of the item at the cursor lowered from that tree, its scopes
 * walked from the expression the name is (D50); each local the file's own body has it as, by the
 * node declaring it, which is before the cursor and so the same in both trees.
 */
func localCompletions(db: AnalysisDatabase, file: SourceFile, def: DefId, realRoot: CjSyntaxNode,
    nameRef: CjSyntaxNode, into: ArrayList<CompletionItem>): Unit {
    let (_, ids) = syntaxOf(db, ItemFile.Source(file)) ?? return
    let start = (ids.node(def.item(db), realRoot) ?? return).textRange.start
    let decl = (nameRef.ancestors() |> filter {one: CjSyntaxNode => one.textRange.start == start} |>
        filterMap {one: CjSyntaxNode => Decl.cast(one)} |> first) ?? return
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
            let kind = match (declared.kind) {
                case ParamLocal | LambdaParamLocal => ParamItem
                case FuncLocal => FuncItem
                case _ => LocalItem
            }
            let source = match (speculative.sourceMap.locals.get(local.index)) {
                case Some(Some(ptr)) => match (real.localAt(ptr)) {
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
 * `items` the most relevant first, then by name, each once: a name shadowed by a nearer one is
 * gone, but for the functions, which overload each other.
 */
func ranked(items: Array<CompletionItem>): Array<CompletionItem> {
    let sorted = items.clone()
    sort(sorted, stable: true, by: {
        a: CompletionItem, b: CompletionItem => match (b.relevance.compare(a.relevance)) {
            case Ordering.EQ => a.label.compare(b.label)
            case other => other
        }
    })
    let seen = HashSet<String>()
    let kept = ArrayList<CompletionItem>()
    for (item in sorted) {
        let key = match ((item.kind, item.source)) {
            case (FuncItem, DeclSource(id, _)) => "${item.label}#${id.hashCode()}"
            case (CtorItem, DeclSource(id, _)) => "${item.label}#${id.hashCode()}"
            case _ => "${item.label}#${item.kind}"
        }
        if (seen.add(key)) {
            kept.add(item)
        }
    }
    kept.toArray()
}
