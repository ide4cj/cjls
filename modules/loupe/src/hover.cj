package loupe

import std.collection.*
import std.deriving.*
import ginkgo.{SyntaxNodePtr, TextRange}
import cjo.{DeclInfo, openCjo}
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{AnyHasDocComment, AnyHasName, BindPat, EnumPat, MemberAccessExpr, Param, ParamList, PathSegment,
    RefExpr, VarDecl}
import loupe.db.{AnalysisDatabase, BinaryPackageFile, Package, SourceFile}
import loupe.hir.*
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * What hovering a name shows, rust-analyzer's `HoverResult`: the name's range, and what it stands
 * for, each candidate of an ambiguity.
 */
@Derive[Equatable]
public struct HoverResult {
    public HoverResult(public let range: TextRange, public let items: Array<HoverItem>) {}
}

/**
 * One thing a name stands for, as Cangjie writes it; no markup, which is the server's to choose.
 */
@Derive[Equatable]
public struct HoverItem {
    public HoverItem(
        /**
         * Its declaration as one line of Cangjie, no body: `public func get(index: Int64): ?Int64`,
         * `let x: Int64`, `x: Int64` for a parameter; its types as inference gives them (D54, D55),
         * a member's as a member of the value it is used on (`T` an argument of the value's type).
         */
        public let code: String,
        /**
         * Where it is declared: its package, and the type it is a member of (`std.collection.ArrayList`);
         * `None` for a local.
         */
        public let path!: ?String = None,
        /**
         * Its doc comment, its text as written, the comment's own markers taken off (`docText`).
         */
        public let doc!: ?String = None
    ) {}
}

/**
 * What the name at `offset` of the file stands for: a declaration at its name, or where a type or a
 * body names it (the overload a call takes, a member as seen on its value); a local or a parameter
 * and its type. `None` where there is no name, a macro's name, or one nothing resolves.
 */
public func hoverAt(db: AnalysisDatabase, fileId: FileId, offset: Int64): ?HoverResult {
    let file = db.sourceFile(fileId) ?? return None
    let root = parse(db, file).syntaxNode()
    let token = tokenAt(root, offset) ?? return None
    // a macro's: later, with its expansion (#175)
    if (macroTargets(db, file, token).isSome()) {
        return None
    }
    let ids = itemIdMap(db, file)
    let item = token.parent.ancestors() |> filterMap {node: CjSyntaxNode => ids.idOf(SyntaxNodePtr(node))} |> first
    let def = DefId(db, ItemFile.Source(file), item ?? return None)
    let items = if (isDeclaredName(db, def, token)) {
        Hovers(db, def, token).ofDecl(def)
    } else if (let Some((typeNode, segment)) <- typeAt(token)) {
        Hovers(db, def, token).ofType(typeNode, segment)
    } else {
        Hovers(db, def, token).ofBody()
    }
    if (items.isEmpty()) {
        return None
    }
    HoverResult(token.textRange, items)
}

/**
 * Whether `token` is the name `def` declares, where it declares it.
 */
func isDeclaredName(db: AnalysisDatabase, def: DefId, token: CjSyntaxToken): Bool {
    let (_, node) = nodeOf(db, def) ?? return false
    if (let Some(name) <- AnyHasName.cast(node).flatMap {it => it.name()}) {
        return name.syntax.textRange == token.parent.textRange
    }
    // a name of a `let` of a pattern: a binding of its pattern, not of a body
    let decl = VarDecl.cast(node) ?? return false
    let pattern = decl.pattern() ?? return false
    let names = itemOf(db, def)?.names ?? []
    pattern.syntax.textRange.contains(token.textRange.start) && names.contains(token.text()) &&
        token.parent.kind == SyntaxKind.Name
}

/**
 * The items one hover finds, for the name `token` in the item `def`.
 */
class Hovers {
    Hovers(let db: AnalysisDatabase, let def: DefId, let token: CjSyntaxToken) {}

    private prop from: ?SourceFile {
        get() {
            scopeFileOf(db, def.file(db))
        }
    }

    func ofDecl(id: DefId): Array<HoverItem> {
        listOf(declItem(id, None))
    }

    /**
     * The segment `segment` of the type `typeNode` in the signature or the body of `def`: as
     * `typeTargets` finds where it is declared.
     */
    func ofType(typeNode: CjSyntaxNode, segment: Int64): Array<HoverItem> {
        let ptr = SyntaxNodePtr(typeNode)
        let lowered = signatureWithSourceMap(db, def)
        let (ty, resolve) = match (lowered.sourceMap.typeAt(ptr)) {
            case Some(ty) => (lowered.signature[ty], {
                path: Array<String> => resolveTypePath(db, typeScopeOf(db, def) ?? return Array<PathResolution>(), path)
            })
            case None =>
                let lowered = bodyWithSourceMap(db, def)
                let ty = lowered.sourceMap.typeAt(ptr) ?? return []
                (lowered.body.types[ty.index], {path: Array<String> => resolveBodyTypePath(db, def, ty, path)})
        }
        match (ty) {
            case PathRef(segments) => match (resolve(segments.map {one => one.name}).get(segment)) {
                case Some(Resolved(target)) => listOf(typeItem(target))
                case Some(AmbiguousPath(targets)) => targets |> filterMap {
                    target: ScopeTarget => match (target) {
                        case OfDecl(id) => declItem(id, None)
                        case OfPackage(_) => None
                    }
                } |> collectArray
                case _ => []
            }
            case ThisRef => match (parentOf(db, def)) {
                case Some(parent) where parent.item(db).kind == ItemKind.Class => ofDecl(parent)
                case _ => []
            }
            case _ => []
        }
    }

    /**
     * The name `token` in the body of `def`: as `bodyTargets` finds where it is declared, each
     * member of a value as a member of its type.
     */
    func ofBody(): Array<HoverItem> {
        let name = token.parent
        let node = name.parent ?? return []
        let lowered = bodyWithSourceMap(db, def)
        let sourceMap = lowered.sourceMap
        if (isOperator(token)) {
            let expr = sourceMap.exprAt(SyntaxNodePtr(token.parent)) ?? return []
            return match (inferBody(db, def).calleeOf(expr)) {
                case Some(decl) => ofDecl(decl)
                case None => []
            }
        }
        if (let Some(ref) <- RefExpr.cast(node)) {
            let expr = sourceMap.exprAt(SyntaxNodePtr(ref.syntax)) ?? return []
            if (let Some(decl) <- inferBody(db, def).calleeOf(expr)) {
                return ofDecl(decl)
            }
            return match (resolveBodyName(db, def, exprScopes(db, def).scopeOf(expr), token.text())) {
                case Values(targets) => targets |> filterMap {target: ValueTarget => valueItem(target, None)} |>
                    collectArray
                case InFile(resolution) => fileDecls(resolution) |> filterMap {id: DefId => declItem(id, None)} |>
                    collectArray
            }
        }
        if (let Some(access) <- MemberAccessExpr.cast(node)) {
            let expr = sourceMap.exprAt(SyntaxNodePtr(access.syntax)) ?? return []
            let inferred = inferBody(db, def)
            // the type of the value it is a member of, if it is one's
            let recv = match (lowered.body[expr]) {
                case FieldExpr(receiver, _, _) => inferred[receiver]
                case _ => Option<Ty>.None
            }
            if (let Some(decl) <- inferred.calleeOf(expr)) {
                return listOf(declItem(decl, recv))
            }
            return match (resolveField(db, def, expr)) {
                case PackageMembers(ids) => ids |> filterMap {id: DefId => declItem(id, None)} |> collectArray
                case TypeMembers(targets) => targets |> filterMap {
                    target: MemberTarget => valueItem(ValueTarget.MemberOf(target), None)
                } |> collectArray
                case OfValue => (inferred.fieldOf(expr) ?? []) |> filterMap {
                    target: MemberTarget => valueItem(ValueTarget.MemberOf(target), recv)
                } |> collectArray
                case NoField => []
            }
        }
        let pkg: ?Package = match (def.file(db)) {
            case Source(file) => packageOfFile(db, file)
            case _ => None
        }
        if (let Some(_) <- BindPat.cast(node)) {
            let local = sourceMap.localAt(SyntaxNodePtr(name)) ?? return []
            let ctors = match (pkg) {
                case Some(one) where lowered.body[local].lone => ctorsNamed(db, one, token.text())
                case _ => Array<DefId>()
            }
            return if (ctors.isEmpty()) {
                listOf(localItem(def, local))
            } else {
                ctors |> filterMap {id: DefId => declItem(id, None)} |> collectArray
            }
        }
        if (let Some(segment) <- PathSegment.cast(node)) {
            let pat = segment.syntax.parent.flatMap {one => EnumPat.cast(one)} ?? return []
            if ((pat.pathSegments() |> collectArray).size == 1 && let Some(one) <- pkg) {
                return ctorsNamed(db, one, token.text()) |> filterMap {id: DefId => declItem(id, None)} |> collectArray
            }
            return []
        }
        listOf(sourceMap.localAt(SyntaxNodePtr(name)).flatMap {local => localItem(def, local)})
    }

    /**
     * What a name of a body stands for; a member as a member of a value of the type `recv`, if
     * one's.
     */
    private func valueItem(target: ValueTarget, recv: ?Ty): ?HoverItem {
        match (target) {
            case LocalOf(local) => localItem(def, local)
            case MemberOf(MemberDecl(id)) => declItem(id, recv)
            case MemberOf(MemberParam(ctor, local)) => memberParamItem(ctor, local, recv)
            case DeclOf(id) => declItem(id, None)
            case TypeParamOf(typeTarget) => typeItem(typeTarget)
        }
    }

    private func typeItem(target: TypeTarget): ?HoverItem {
        match (target) {
            case TypeOf(id) => declItem(id, None)
            case GenericOf(owner, index) => HoverItem(genericsOf(db, owner).get(index) ?? return None)
            case LocalGenericOf(owner, localFunc, index) =>
                HoverItem(bodyWithSourceMap(db, owner).body.funcs.get(localFunc).flatMap {one => one.generics.get(index)} ??
                    return None)
            // a package, which declares nothing
            case QualifierOf(_) => None
        }
    }

    /**
     * The local `local` of the body of `owner` and its type: `let x: Int64`, `x: Int64` for a
     * parameter or a binding of a pattern, a local function as a declaration.
     */
    private func localItem(owner: DefId, local: LocalId): ?HoverItem {
        let lowered = bodyWithSourceMap(db, owner)
        let declared = lowered.body.locals.get(local.index) ?? return None
        let ty = inferBody(db, owner)[local] ?? Ty(db, ErrorTy)
        let code = match (declared.kind) {
            case VarLocal => "${varKeyword(owner, local)}${declared.name}: ${ty.text(db)}"
            case FuncLocal => localFuncCode(lowered.body, local, ty)
            case _ => "${declared.name}: ${ty.text(db)}"
        }
        HoverItem(code)
    }

    /**
     * The keyword of the `let`, `var` or `const` declaring `local`, or of the member parameter it is,
     * and a space.
     */
    private func varKeyword(owner: DefId, local: LocalId): String {
        let file = match (owner.file(db)) {
            case Source(file) => file
            case _ => return ""
        }
        let ptr = bodyWithSourceMap(db, owner).sourceMap.locals.get(local.index) ?? return ""
        let name = (ptr ?? return "").tryToNode(parse(db, file).syntaxNode()) ?? return ""
        // a member parameter of a primary constructor
        if (let Some(param) <- name.parent.flatMap {node => Param.cast(node)}) {
            return if (param.varToken().isSome()) {
                "var "
            } else if (param.letToken().isSome()) {
                "let "
            } else {
                ""
            }
        }
        let decl = (name.ancestors() |> filterMap {node: CjSyntaxNode => VarDecl.cast(node)} |> first) ?? return ""
        keywordOf(decl)
    }

    private func localFuncCode(body: Body, local: LocalId, ty: Ty): String {
        let name = body[local].name
        let localFunc = (body.funcs |> filter {one: LocalFunc => one.local == local} |> first) ?? return "func ${name}"
        let (params, ret) = match (ty.kind(db)) {
            case FuncTy(params, ret, _) => (params, ret)
            case _ => return "func ${name}"
        }
        let names = localFunc.params.map {
            param => param.local.flatMap {one => body.locals.get(one.index)}.map {one => one.name} ?? "_"
        }
        let written = Array(params.size) {i => "${names.get(i) ?? "_"}: ${params[i].text(db)}"}
        "func ${name}${genericList(localFunc.generics)}(${String.join(written, delimiter: ", ")}): ${ret.text(db)}"
    }

    /**
     * A `let` or `var` parameter of the primary constructor `ctor`, a member of its type, as a
     * member of a value of the type `recv` if one's.
     */
    private func memberParamItem(ctor: DefId, local: LocalId, recv: ?Ty): ?HoverItem {
        let params = body(db, ctor).params
        let index = (0..params.size |> filter {i: Int64 => params[i].local == Some(local)} |> first) ?? return None
        let ty = seen(signatureTypes(db, ctor).params.get(index) ?? return None, ctor, recv)
        let name = body(db, ctor).locals.get(local.index)?.name ?? return None
        HoverItem("${varKeyword(ctor, local)}${name}: ${ty.text(db)}", path: pathOf(ctor))
    }

    /**
     * `ty`, written in the member `member`, as a member of a value of the type `recv`, if one's.
     */
    private func seen(ty: Ty, member: DefId, recv: ?Ty): Ty {
        match (recv) {
            case Some(one) => asMemberOf(db, ty, member, one, from) ?? ty
            case None => ty
        }
    }

    /**
     * The declaration `id`, a member as a member of a value of the type `recv` if one's: its
     * signature, its path, its doc comment.
     */
    private func declItem(id: DefId, recv: ?Ty): ?HoverItem {
        let item = declItemOf(db, id) ?? return None
        let sig = signatureTypes(db, id)
        let ty = {one: Ty => seen(one, id, recv).text(db)}
        let names = item.names
        let name = if (names.contains(token.text())) {
            token.text()
        } else {
            names.get(0) ?? "_"
        }
        let generics = genericList(sig.generics)
        let params = {=> "(${String.join(paramsOf(id, sig, ty), delimiter: ", ")})"}
        let declared = {=> ty(declaredTyOf(db, id))}
        let head = match (item.kind) {
            case Func => "func ${name}${generics}${params()}: ${declared()}"
            case Main => "main${params()}: ${declared()}"
            case Macro => "macro ${name}${params()}"
            case Init => "init${generics}${params()}"
            case PrimaryInit => "${name}${params()}"
            case Finalizer => "~init()"
            case Class => "class ${name}${generics}${supersOf(item, sig, ty)}"
            case Interface => "interface ${name}${generics}${supersOf(item, sig, ty)}"
            case Struct => "struct ${name}${generics}${supersOf(item, sig, ty)}"
            case Enum => "enum ${name}${generics}${supersOf(item, sig, ty)}"
            case BuiltIn => "type ${name}${generics}"
            case Extend => "extend${generics} ${sig.ty.map {one => ty(one)} ?? "_"}${supersOf(item, sig, ty)}"
            case TypeAlias => "type ${name}${generics} = ${sig.ty.map {one => ty(one)} ?? "_"}"
            case EnumCtor where sig.params.isEmpty() => name
            case EnumCtor => "${name}(${String.join(sig.params.map {one => ty(one)}, delimiter: ", ")})"
            // one name of several of a pattern: its type is the pattern's
            case Var where names.size > 1 => "${varKeyword(id)}${name}"
            case Var => "${varKeyword(id)}${name}: ${declared()}"
            case Prop => "prop ${name}: ${declared()}"
            case Import | MacroCall => return None
        }
        let bounds = if (sig.bounds.isEmpty()) {
            ""
        } else {
            " where " + String.join(sig.bounds.map {
                bound => "${ty(bound.ty)} <: ${String.join(bound.bounds.map {one => ty(one)}, delimiter: " & ")}"
            }, delimiter: ", ")
        }
        let modifiers = modifiersText(item)
        HoverItem("${modifiers}${head}${bounds}", path: pathOf(id), doc: docOf(id))
    }

    /**
     * The parameters of `id`, each `name: T`, `name!: T` if passed by name.
     */
    private func paramsOf(id: DefId, sig: SignatureTypes, ty: (Ty) -> String): Array<String> {
        let names = paramNamesOf(id)
        Array(sig.params.size) {
            i =>
            let byName = match (sig.paramNames.get(i)) {
                case Some(Some(_)) => "!"
                case _ => ""
            }
            "${names.get(i) ?? "_"}${byName}: ${ty(sig.params[i])}"
        }
    }

    /**
     * The names of the parameters of `id`, of every list in order: of its node, or of its `.cjo`.
     */
    private func paramNamesOf(id: DefId): Array<String> {
        match (id.file(db)) {
            case Binary(pkg, file) => binaryParamNames(pkg, BinaryItem(file, id.item(db)))
            case file =>
                let (root, ids) = syntaxOf(db, file) ?? return []
                let node = ids.node(id.item(db), root) ?? return []
                node.children() |> filterMap {child: CjSyntaxNode => ParamList.cast(child)} |> flatMap {
                    list: ParamList => list.params()
                } |> map {param: Param => param.name()?.text() ?? "_"} |> collectArray
        }
    }

    private func binaryParamNames(pkg: BinaryPackageFile, item: BinaryItem): Array<String> {
        let index = binaryExports(db, pkg).declIndex(item) ?? return []
        try {
            let cjo = openCjo(pkg.bytes(db))
            let lists = match (cjo.allDecls[index].info) {
                case Some(DeclInfo.AsFuncInfo(it)) => (it.funcBody ?? return []).paramLists.toArray()
                case _ => return []
            }
            let names = ArrayList<String>()
            for (list in lists) {
                for (param in list.params) {
                    let name = cjo.allDecls[Int64(param) - 1].identifier ?? ""
                    names.add(if (name.isEmpty()) {
                        "_"
                    } else {
                        name
                    })
                }
            }
            names.toArray()
        } catch (_: Exception) {
            []
        }
    }

    /**
     * The keyword of the variable `id`, and a space: none for a `const`, whose modifier says it.
     */
    private func varKeyword(id: DefId): String {
        match (id.file(db)) {
            case Source(_) | Expansion(_) =>
                let (root, ids) = syntaxOf(db, id.file(db)) ?? return ""
                keywordOf(VarDecl.cast(ids.node(id.item(db), root) ?? return "") ?? return "")
            case Binary(pkg, file) => match (binaryDecl(db, pkg, BinaryItem(file, id.item(db))).flatMap {decl => decl.info}) {
                case Some(DeclInfo.AsVarInfo(it)) where it.isConst => ""
                case Some(DeclInfo.AsVarInfo(it)) where it.isVar => "var "
                case Some(DeclInfo.AsVarWithPatternInfo(it)) where it.isConst => ""
                case Some(DeclInfo.AsVarWithPatternInfo(it)) where it.isVar => "var "
                case _ => "let "
            }
        }
    }

    /**
     * ` <: A & B`, the types `item` inherits from; not the `Object` cjc gives a class of no
     * superclass.
     */
    private func supersOf(item: Item, sig: SignatureTypes, ty: (Ty) -> String): String {
        let written = sig.supers.map {one => ty(one)}
        let shown = if (item.kind == ItemKind.Class && written.get(0) == Some("Object")) {
            written[1..]
        } else {
            written
        }
        if (shown.isEmpty()) {
            ""
        } else {
            " <: " + String.join(shown, delimiter: " & ")
        }
    }

    /**
     * Where `id` is declared: its package, and the type it is a member of, an `extend`'s type.
     */
    private func pathOf(id: DefId): ?String {
        let pkg = match (id.file(db)) {
            case Binary(binary, _) => binary.name(db)
            case file => scopeFileOf(db, file).flatMap {one => packageOfFile(db, one)}?.name(db)
        }
        let owner: ?String = match (parentOf(db, id)) {
            case Some(parent) where parent.item(db).kind == ItemKind.Extend => match (signatureTypes(db, parent).ty) {
                case Some(extended) => match (extended.kind(db)) {
                    case DeclTy(of, _) => declItemOf(db, of).flatMap {one => one.names.get(0)}
                    case _ => extended.text(db)
                }
                case None => None
            }
            case Some(parent) => declItemOf(db, parent).flatMap {one => one.names.get(0)}
            case None => None
        }
        match ((pkg, owner)) {
            case (Some(one), Some(name)) => "${one}.${name}"
            case (Some(one), None) => one
            case (None, Some(name)) => name
            case (None, None) => None
        }
    }

    /**
     * The doc comment of `id`: of its node, or of its declaration in the sources of its binary,
     * where they are (D65).
     */
    private func docOf(id: DefId): ?String {
        let node = match (id.file(db)) {
            case Source(_) => (nodeOf(db, id) ?? return None)[1]
            case Binary(pkg, file) =>
                let target = binaryTarget(db, pkg, file, id.item(db)) ?? return None
                let source = db.sourceFile(target.fileId) ?? return None
                let root = parse(db, source).syntaxNode()
                let at = match (root.tokenAtOffset(target.focusRange.start)) {
                    case Single(one) => one
                    case Between(_, right) => right
                    case _ => return None
                }
                (at.parent.ancestors() |> filter {one: CjSyntaxNode => AnyHasDocComment.canCast(one.kind)} |> first) ??
                    return None
            // what a macro call adds is generated, with no doc comment (#175)
            case Expansion(_) => return None
        }
        let comments = AnyHasDocComment.cast(node)?.docComments() ?? return None
        let doc = docText(comments.map {comment => comment.text()})
        if (doc.isEmpty()) {
            None
        } else {
            doc
        }
    }

    /**
     * The declarations of the file's scope a resolution finds.
     */
    private func fileDecls(resolution: Resolution): Array<DefId> {
        match (resolution) {
            case Found(ids) => ids
            case Ambiguous(targets) => targets |> filterMap {
                target: ScopeTarget => match (target) {
                    case OfDecl(id) => id
                    case OfPackage(_) => None
                }
            } |> collectArray
            case Ctors(own, imported) => own.concat(imported)
            case _ => []
        }
    }
}

func listOf(item: ?HoverItem): Array<HoverItem> {
    match (item) {
        case Some(one) => [one]
        case None => []
    }
}

/**
 * `let `, `var ` or none for a `const`, whose modifier says it.
 */
func keywordOf(decl: VarDecl): String {
    if (decl.varToken().isSome()) {
        "var "
    } else if (decl.letToken().isSome()) {
        "let "
    } else {
        ""
    }
}

func genericList(generics: Array<String>): String {
    if (generics.isEmpty()) {
        ""
    } else {
        "<${String.join(generics, delimiter: ", ")}>"
    }
}

/**
 * The modifiers of `item` as Cangjie orders them: who sees it first, then the others, each followed
 * by a space.
 */
func modifiersText(item: Item): String {
    let access = [Modifier.Public, Modifier.Protected, Modifier.Internal, Modifier.Private]
    let shown = item.modifiers.filter {one => access.contains(one)}.concat(
        item.modifiers.filter {one => !access.contains(one) && one != Modifier.Common && one != Modifier.Specific})
    String.join(shown.map {one => "${one} "}, delimiter: "")
}

/**
 * The text of the doc comments `comments`, each without its markers: those opening and closing a
 * block comment, a `*` starting a line and one space after it, the slashes of a line comment and one
 * space after them; blank lines around left out.
 */
func docText(comments: Array<String>): String {
    let lines = ArrayList<String>()
    for (comment in comments) {
        if (comment.startsWith("//")) {
            lines.add(dropSpace(comment.removePrefix("//")))
            continue
        }
        let inner = comment.removePrefix("/**").removePrefix("/*").removeSuffix("*/")
        let split = inner.split("\n")
        for (i in 0..split.size) {
            let trimmed = split[i].trimAsciiStart()
            lines.add(if (trimmed.startsWith("*")) {
                dropSpace(trimmed.removePrefix("*"))
            } else if (i == 0) {
                // the text after the opening, `/** text`
                trimmed
            } else {
                split[i]
            })
        }
    }
    let kept = lines.toArray().map {one => one.trimAsciiEnd()}
    let first = (0..kept.size |> filter {i: Int64 => !kept[i].isEmpty()} |> first) ?? return ""
    var last = kept.size - 1
    while (kept[last].isEmpty()) {
        last--
    }
    String.join(kept[first..=last], delimiter: "\n")
}

func dropSpace(text: String): String {
    if (text.startsWith(" ")) {
        text[1..]
    } else {
        text
    }
}
