package loupe

import std.collection.*
import std.deriving.*
import cjo.{openCjo, Position as CjoPosition}
import ginkgo.{SyntaxNodePtr, TextRange, TokenAtOffset}
import rope.{Encoding, LineColumn, Rope}
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{AnyHasName, AnyHasTypeParams, BinExpr, BindPat, EnumPat, IndexExpr, MacroExpandDecl, MacroExpandExpr,
    MemberAccessExpr, NameRef, PathSegment, PathType, RefExpr, UnaryExpr}
import loupe.db.{AnalysisDatabase, BinaryPackageFile, BinarySourceFile, SourceFile}
import loupe.hir.*
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * A declaration a request goes to: its file, its whole node, and its name, what an editor selects;
 * rust-analyzer's `NavigationTarget`.
 */
@Derive[Equatable]
public struct NavigationTarget {
    public NavigationTarget(
        public let fileId: FileId,
        public let fullRange: TextRange,
        public let focusRange: TextRange
    ) {}
}

/**
 * Where the name at `offset` of the file is declared: a name in a type of a signature (D48) or of a
 * body, a name a body uses, a constructor a pattern names (D50), a member after a `.` of a package,
 * a type (D52) or a value (D55), the macro of a call; the operator function an operator calls (8e);
 * each candidate of an ambiguity or of an overload. Nothing for a package, nor for a declaration of
 * a package compiled already whose binary's sources are not there (D65).
 */
public func definitionAt(db: AnalysisDatabase, fileId: FileId, offset: Int64): Array<NavigationTarget> {
    let file = db.sourceFile(fileId) ?? return []
    let root = parse(db, file).syntaxNode()
    let token = tokenAt(root, offset) ?? return []
    if (let Some(targets) <- macroTargets(db, file, token)) {
        return targets
    }
    let ids = itemIdMap(db, file)
    let item = token.parent.ancestors() |> filterMap {node: CjSyntaxNode => ids.idOf(SyntaxNodePtr(node))} |> first
    let def = DefId(db, ItemFile.Source(file), item ?? return [])
    if (let Some((typeNode, segment)) <- typeAt(token)) {
        return typeTargets(db, def, typeNode, segment)
    }
    bodyTargets(db, def, token)
}

/**
 * Where the macro a call names is declared, if `token` is a segment of the name of one: looked up in the file's
 * scope, a macro being no local, whatever item the call is on or in.
 */
func macroTargets(db: AnalysisDatabase, file: SourceFile, token: CjSyntaxToken): ?Array<NavigationTarget> {
    let name = NameRef.cast(token.parent) ?? return None
    let call = name.syntax.parent ?? return None
    let names = match ((MacroExpandDecl.cast(call), MacroExpandExpr.cast(call))) {
        case (Some(decl), _) => decl.nameRefs() |> collectArray
        case (_, Some(expr)) => expr.nameRefs() |> collectArray
        case _ => return None
    }
    // A segment of a macro's name is nothing else: a file of no package leaves it nowhere, not to the lookups below.
    let pkg = packageOfFile(db, file) ?? return []
    let segment = names.map {one => one.syntax.textRange}.indexOf(name.syntax.textRange) ?? return []
    let resolved = resolveMacroPath(db, pkg, file, names.map {one => one.text()})
    fileTargets(db, resolved[segment])
}

/**
 * Where the name of the segment `segment` of the type `typeNode`, in the signature or the body of
 * `def`, is declared.
 */
func typeTargets(db: AnalysisDatabase, def: DefId, typeNode: CjSyntaxNode, segment: Int64): Array<NavigationTarget> {
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
            case Some(Resolved(target)) => listOf(targetOf(db, target))
            case Some(AmbiguousPath(targets)) => declTargets(db, targets |> filterMap {
                target: ScopeTarget => match (target) {
                    case OfDecl(id) => id
                    case OfPackage(_) => None
                }
            } |> collectArray)
            case _ => []
        }
        case ThisRef => match (parentOf(db, def)) {
            case Some(parent) where parent.item(db).kind == ItemKind.Class => listOf(targetOf(db, TypeOf(parent)))
            case _ => []
        }
        case _ => []
    }
}

/**
 * Where the name `token`, in the body of `def`, is declared: what a name used there means (N59–N71),
 * what a name after a `.` does (N75–N79), the constructor a pattern names (N72), a local itself at
 * its declaration.
 */
func bodyTargets(db: AnalysisDatabase, def: DefId, token: CjSyntaxToken): Array<NavigationTarget> {
    let name = token.parent
    let node = name.parent ?? return []
    let lowered = bodyWithSourceMap(db, def)
    let sourceMap = lowered.sourceMap
    let pkg = match (def.file(db)) {
        case Source(file) => packageOfFile(db, file) ?? return []
        case Binary(_, _) => return []
    }
    // an operator: the operator function it calls (8e)
    if (isOperator(token)) {
        let expr = sourceMap.exprAt(SyntaxNodePtr(token.parent)) ?? return []
        return match (inferBody(db, def).calleeOf(expr)) {
            case Some(decl) => declTargets(db, [decl])
            case None => []
        }
    }
    if (let Some(ref) <- RefExpr.cast(node)) {
        let expr = sourceMap.exprAt(SyntaxNodePtr(ref.syntax)) ?? return []
        // of overloads, the one inference chose (8d)
        if (let Some(decl) <- inferBody(db, def).calleeOf(expr)) {
            return declTargets(db, [decl])
        }
        return match (resolveBodyName(db, def, exprScopes(db, def).scopeOf(expr), token.text())) {
            case Values(targets) => targets |> filterMap {target: ValueTarget => valueTarget(db, def, target)} |> collectArray
            case InFile(resolution) => fileTargets(db, resolution)
        }
    }
    if (let Some(access) <- MemberAccessExpr.cast(node)) {
        let expr = sourceMap.exprAt(SyntaxNodePtr(access.syntax)) ?? return []
        if (let Some(decl) <- inferBody(db, def).calleeOf(expr)) {
            return declTargets(db, [decl])
        }
        return match (resolveField(db, def, expr)) {
            case PackageMembers(ids) => declTargets(db, ids)
            case TypeMembers(targets) => targets |> filterMap {
                target: MemberTarget => valueTarget(db, def, ValueTarget.MemberOf(target))
            } |> collectArray
            // a member of a value: what its type has (D55)
            case OfValue => (inferBody(db, def).fieldOf(expr) ?? []) |> filterMap {
                target: MemberTarget => valueTarget(db, def, ValueTarget.MemberOf(target))
            } |> collectArray
            case NoField => []
        }
    }
    if (let Some(bind) <- BindPat.cast(node)) {
        let local = sourceMap.localAt(SyntaxNodePtr(name)) ?? return []
        let ctors = if (lowered.body[local].lone) {
            ctorsNamed(db, pkg, token.text())
        } else {
            Array<DefId>()
        }
        return if (ctors.isEmpty()) {
            listOf(localTarget(db, def, local))
        } else {
            declTargets(db, ctors)
        }
    }
    if (let Some(segment) <- PathSegment.cast(node)) {
        let pat = segment.syntax.parent.flatMap {one => EnumPat.cast(one)} ?? return []
        let segments = pat.pathSegments() |> collectArray
        if (segments.size == 1) {
            return declTargets(db, ctorsNamed(db, pkg, token.text()))
        }
        return []
    }
    listOf(sourceMap.localAt(SyntaxNodePtr(name)).flatMap {local => localTarget(db, def, local)})
}

/**
 * Where what a name of a body stands for is declared.
 */
func valueTarget(db: AnalysisDatabase, def: DefId, target: ValueTarget): ?NavigationTarget {
    match (target) {
        case LocalOf(local) => localTarget(db, def, local)
        case MemberOf(MemberDecl(id)) => declTarget(db, id)
        case MemberOf(MemberParam(ctor, local)) => localTarget(db, ctor, local)
        case DeclOf(id) => declTarget(db, id)
        case TypeParamOf(typeTarget) => targetOf(db, typeTarget)
    }
}

/**
 * Where what the file's scope has is declared: its declarations, its constructors.
 */
func fileTargets(db: AnalysisDatabase, resolution: Resolution): Array<NavigationTarget> {
    match (resolution) {
        case Found(ids) => declTargets(db, ids)
        case Ambiguous(targets) => declTargets(db, targets |> filterMap {
            target: ScopeTarget => match (target) {
                case OfDecl(id) => id
                case OfPackage(_) => None
            }
        } |> collectArray)
        case Ctors(own, imported) => declTargets(db, own.concat(imported))
        case _ => []
    }
}

func declTargets(db: AnalysisDatabase, ids: Array<DefId>): Array<NavigationTarget> {
    ids |> filterMap {id: DefId => declTarget(db, id)} |> collectArray
}

/**
 * The local `local` of the body of `def`: its name, in the node declaring it.
 */
func localTarget(db: AnalysisDatabase, def: DefId, local: LocalId): ?NavigationTarget {
    let file = match (def.file(db)) {
        case Source(file) => file
        case Binary(_, _) => return None
    }
    let ptr = bodyWithSourceMap(db, def).sourceMap.locals.get(local.index) ?? return None
    let name = (ptr ?? return None).tryToNode(parse(db, file).syntaxNode()) ?? return None
    NavigationTarget(file.fileId(db), name.parent?.textRange ?? name.textRange, name.textRange)
}

func listOf(target: ?NavigationTarget): Array<NavigationTarget> {
    match (target) {
        case Some(one) => [one]
        case None => []
    }
}

/**
 * The identifier or `This` at `offset`, the one after it if it is between two.
 */
func tokenAt(root: CjSyntaxNode, offset: Int64): ?CjSyntaxToken {
    let isName = {token: CjSyntaxToken => token.kind == SyntaxKind.Ident || token.kind == SyntaxKind.ThisTypeKw}
    // a name before an operator it touches (`a|+b`)
    match (root.tokenAtOffset(offset)) {
        case Single(token) where isName(token) || isOperator(token) => token
        case Between(left, right) => if (isName(right)) {
            right
        } else if (isName(left)) {
            left
        } else if (isOperator(right)) {
            right
        } else if (isOperator(left)) {
            left
        } else {
            None
        }
        case _ => None
    }
}

/**
 * Whether `token` is an operator: the operator of a binary or unary expression, or a bracket of an index.
 */
func isOperator(token: CjSyntaxToken): Bool {
    let parent = token.parent
    if (IndexExpr.canCast(parent.kind)) {
        return token.kind == SyntaxKind.LBracket || token.kind == SyntaxKind.RBracket
    }
    let op = BinExpr.cast(parent).flatMap {expr => expr.op()} ?? UnaryExpr.cast(parent).flatMap {expr => expr.op()} ??
        return false
    op.textRange == token.textRange
}

/**
 * The type `token` is a name in, and the index of its segment: a `PathType`'s, or a `ThisType`.
 */
func typeAt(token: CjSyntaxToken): ?(CjSyntaxNode, Int64) {
    let parent = token.parent
    if (parent.kind == SyntaxKind.ThisType) {
        return (parent, 0)
    }
    let segment = parent.parent.flatMap {node => PathSegment.cast(node)} ?? return None
    let path = segment.syntax.parent.flatMap {node => PathType.cast(node)} ?? return None
    let index = path.pathSegments() |> enumerate |> filter {pair: (Int64, PathSegment) => pair[1] == segment} |>
        map {pair: (Int64, PathSegment) => pair[0]} |> first
    (path.syntax, index ?? return None)
}

/**
 * Where `target` is declared; `None` for a package, or a declaration with no source.
 */
func targetOf(db: AnalysisDatabase, target: TypeTarget): ?NavigationTarget {
    match (target) {
        case TypeOf(id) => declTarget(db, id)
        case GenericOf(owner, index) =>
            let (file, node) = nodeOf(db, owner) ?? return None
            genericTarget(db, file, node, index)
        case LocalGenericOf(owner, localFunc, index) =>
            let file = match (owner.file(db)) {
                case Source(file) => file
                case Binary(_, _) => return None
            }
            let lowered = bodyWithSourceMap(db, owner)
            let local = lowered.body.funcs.get(localFunc)?.local ?? return None
            let ptr = lowered.sourceMap.locals.get(local.index) ?? return None
            let name = (ptr ?? return None).tryToNode(parse(db, file).syntaxNode()) ?? return None
            genericTarget(db, file, name.parent ?? return None, index)
        case QualifierOf(_) => None
    }
}

/**
 * The type parameter at `index` of the declaration `node`.
 */
func genericTarget(db: AnalysisDatabase, file: SourceFile, node: CjSyntaxNode, index: Int64): ?NavigationTarget {
    let params = AnyHasTypeParams.cast(node).flatMap {it => it.typeParamList()} ?? return None
    let param = (params.typeParams() |> skip(index) |> first) ?? return None
    let name = param.name()?.syntax.textRange ?? param.syntax.textRange
    NavigationTarget(file.fileId(db), param.syntax.textRange, name)
}

/**
 * Where the declaration `id` is: its node and its name; for one of a package compiled already, where
 * its `.cjo` says it is in the sources of its binary.
 */
func declTarget(db: AnalysisDatabase, id: DefId): ?NavigationTarget {
    if (let Binary(pkg, file) <- id.file(db)) {
        return binaryTarget(db, pkg, file, id.item(db))
    }
    let (file, node) = nodeOf(db, id) ?? return None
    let name = AnyHasName.cast(node).flatMap {it => it.name()}
    NavigationTarget(file.fileId(db), node.textRange, name?.syntax.textRange ?? node.textRange)
}

/**
 * Where the item `id` of the file `file` of `pkg` is in the sources of its binary: from the start of
 * its declaration to the end, and its name, at the positions its `.cjo` gives, which are of the
 * sources it was compiled from (D65). `None` without the sources, and wherever its name is not
 * written at its position: sources of another version, or a declaration cjc made (a `BuiltInDecl`'s
 * position is none, a `let` of a pattern has no name).
 */
func binaryTarget(db: AnalysisDatabase, pkg: BinaryPackageFile, file: Int64, id: ItemId): ?NavigationTarget {
    let index = binaryExports(db, pkg).declIndex(BinaryItem(file, id)) ?? return None
    let name = (findItem(itemTreeOf(db, ItemFile.Binary(pkg, file)).items, id)?.names ?? []).get(0) ?? return None
    // the positions of cjc: lines and columns from 1, columns in bytes, the end past the declaration
    let (fileName, begin, end, at) = try {
        let cjo = openCjo(pkg.bytes(db))
        let decl = cjo.allDecls[index]
        let lineColumn = {position: ?CjoPosition => position.map {it => (Int64(it.line) - 1, Int64(it.column) - 1)}}
        (cjo.allFiles[file], lineColumn(decl.begin), lineColumn(decl.end), lineColumn(decl.identifierPos))
    } catch (_: Exception) {
        return None
    }
    let binary = pkg.binary(db)
    let sources = db.project()?.binarySources(db) ?? return None
    let fileId = (sources |> filter {source: BinarySourceFile => source.binary == binary && source.name == fileName} |>
        map {source: BinarySourceFile => source.fileId} |> first) ?? return None
    let text = (db.sourceFile(fileId) ?? return None).text(db)
    let offsetOf = {
        position: ?(Int64, Int64) => match (position) {
            case Some((line, column)) where line >= 0 && column >= 0 && line < text.lineCount =>
                Some(text.offsetOf(LineColumn(line, column), Encoding.Utf8))
            case _ => Option<Int64>.None
        }
    }
    // a name in backquotes is at the name, inside them
    let start = offsetOf(at) ?? return None
    if (!writes(text, start, name)) {
        return None
    }
    let focus = TextRange(start, start + name.size)
    let full = match ((offsetOf(begin), offsetOf(end))) {
        case (Some(from), Some(to)) where from <= focus.start && focus.end <= to => TextRange(from, to)
        case _ => focus
    }
    NavigationTarget(fileId, full, focus)
}

/**
 * The item `id` among `items` and their members.
 */
func findItem(items: Array<Item>, id: ItemId): ?Item {
    for (item in items) {
        if (item.id == id) {
            return item
        }
        if (let Some(member) <- findItem(item.members, id)) {
            return member
        }
    }
    None
}

/**
 * Whether `text` has `written` at `offset`.
 */
func writes(text: Rope, offset: Int64, written: String): Bool {
    offset + written.size <= text.size && text.slice(offset..offset + written.size).toString() == written
}

/**
 * The file and the node of `id`, if it is in a source file still.
 */
func nodeOf(db: AnalysisDatabase, id: DefId): ?(SourceFile, CjSyntaxNode) {
    let file = match (id.file(db)) {
        case Source(file) => file
        case Binary(_, _) => return None
    }
    let node = itemIdMap(db, file).node(id.item(db), parse(db, file).syntaxNode()) ?? return None
    (file, node)
}
