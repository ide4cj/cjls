package loupe

import std.collection.*
import std.deriving.*
import cjo.{openCjo, Position as CjoPosition}
import ginkgo.{SyntaxNodePtr, TextRange, TokenAtOffset}
import rope.{Encoding, LineColumn, Rope}
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{AnyHasName, AnyHasTypeParams, BinExpr, IndexExpr, PathSegment, PathType, UnaryExpr}
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
 * Where the name at `offset` of the file is declared: where what `classifyName` says it means is (rust-analyzer's
 * `goto_definition`); the operator function an operator calls (8e); a member `@Derive` adds, at the interface the
 * call names (#175). Nothing for a package, nor for a declaration of a package compiled already whose binary's
 * sources are not there (D65).
 */
public func definitionAt(db: AnalysisDatabase, fileId: FileId, offset: Int64): Array<NavigationTarget> {
    let file = db.sourceFile(fileId) ?? return []
    let root = parse(db, file).syntaxNode()
    let token = tokenAt(root, offset) ?? return []
    let defs = classifyName(db, file, itemAround(db, file, token.parent), token) ?? return []
    defs |> filterMap {one: Definition => targetOfDefinition(db, one)} |> collectArray
}

/**
 * The innermost item `node` is in, or is.
 */
func itemAround(db: AnalysisDatabase, file: SourceFile, node: CjSyntaxNode): ?DefId {
    let ids = itemIdMap(db, file)
    let item = node.ancestors() |> filterMap {one: CjSyntaxNode => ids.idOf(SyntaxNodePtr(one))} |> first
    DefId(db, ItemFile.Source(file), item ?? return None)
}

/**
 * Where `definition` is declared; `None` for a package.
 */
func targetOfDefinition(db: AnalysisDatabase, definition: Definition): ?NavigationTarget {
    match (definition) {
        case DeclDef(id) => declTarget(db, id)
        case LocalDef(def, local) => localTarget(db, def, local)
        case MemberParamDef(ctor, local) => localTarget(db, ctor, local)
        case TypeParamDef(target) => targetOf(db, target)
        case PackageDef(_) => None
    }
}

/**
 * The local `local` of the body of `def`: its name, in the node declaring it.
 */
func localTarget(db: AnalysisDatabase, def: DefId, local: LocalId): ?NavigationTarget {
    let (file, name) = localName(db, def, local) ?? return None
    NavigationTarget(file.fileId(db), name.parent?.textRange ?? name.textRange, name.textRange)
}

/**
 * The name of the local `local` of the body of `def`, and its file.
 */
func localName(db: AnalysisDatabase, def: DefId, local: LocalId): ?(SourceFile, CjSyntaxNode) {
    let file = match (def.file(db)) {
        case Source(file) => file
        case _ => return None
    }
    let ptr = bodyWithSourceMap(db, def).sourceMap.locals.get(local.index) ?? return None
    let name = (ptr ?? return None).tryToNode(parse(db, file).syntaxNode()) ?? return None
    (file, name)
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
                case _ => return None
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
 * its `.cjo` says it is in the sources of its binary; for one a macro call adds, what in the call
 * adds it, the interface of `@Derive[...]`.
 */
func declTarget(db: AnalysisDatabase, id: DefId): ?NavigationTarget {
    match (id.file(db)) {
        case Binary(pkg, file) => return binaryTarget(db, pkg, file, id.item(db))
        // what a macro call adds: where the call writes it (#175)
        case Expansion(call) =>
            let (focus, full) = expansionOrigin(db, call, id.item(db)) ?? return None
            return NavigationTarget(call.file(db).fileId(db), full, focus)
        case Source(_) => ()
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
        case _ => return None
    }
    let node = itemIdMap(db, file).node(id.item(db), parse(db, file).syntaxNode()) ?? return None
    (file, node)
}
