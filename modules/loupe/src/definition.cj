package loupe

import std.collection.*
import std.deriving.*
import ginkgo.{SyntaxNodePtr, TextRange, TokenAtOffset}
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{AnyHasName, AnyHasTypeParams, PathSegment, PathType}
import loupe.db.{AnalysisDatabase, SourceFile}
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
 * Where the name at `offset` of the file is declared, for now a name in a type of a signature (D48):
 * a type, a type parameter, the class of `This`; each candidate of an ambiguity. Nothing for a
 * package, nor yet for a declaration of a package compiled already, which has no source.
 */
public func definitionAt(db: AnalysisDatabase, fileId: FileId, offset: Int64): Array<NavigationTarget> {
    let file = db.sourceFile(fileId) ?? return []
    let root = parse(db, file).syntaxNode()
    let token = tokenAt(root, offset) ?? return []
    let (typeNode, segment) = typeAt(token) ?? return []
    let ids = itemIdMap(db, file)
    let item = typeNode.ancestors() |> filterMap {node: CjSyntaxNode => ids.idOf(SyntaxNodePtr(node))} |> first
    let def = DefId(db, ItemFile.Source(file), item ?? return [])
    let lowered = signatureWithSourceMap(db, def)
    let ty = lowered.sourceMap.typeAt(SyntaxNodePtr(typeNode)) ?? return []
    match (lowered.signature[ty]) {
        case PathRef(segments) =>
            let scope = typeScopeOf(db, def) ?? return []
            match (resolveTypePath(db, scope, segments.map {one => one.name})[segment]) {
                case Resolved(target) => listOf(targetOf(db, target))
                case AmbiguousPath(targets) => targets |> filterMap {
                    target: ScopeTarget => match (target) {
                        case OfDecl(id) => targetOf(db, TypeOf(id))
                        case OfPackage(_) => None
                    }
                } |> collectArray
                case _ => []
            }
        case ThisRef => match (parentOf(db, def)) {
            case Some(parent) where parent.item(db).kind == ItemKind.Class => listOf(targetOf(db, TypeOf(parent)))
            case _ => []
        }
        case _ => []
    }
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
    match (root.tokenAtOffset(offset)) {
        case Single(token) where isName(token) => token
        case Between(left, right) => if (isName(right)) {
            right
        } else if (isName(left)) {
            left
        } else {
            None
        }
        case _ => None
    }
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
        case TypeOf(id) =>
            let (file, node) = nodeOf(db, id) ?? return None
            let name = AnyHasName.cast(node).flatMap {it => it.name()}
            NavigationTarget(file.fileId(db), node.textRange, name?.syntax.textRange ?? node.textRange)
        case GenericOf(owner, index) =>
            let (file, node) = nodeOf(db, owner) ?? return None
            let params = AnyHasTypeParams.cast(node).flatMap {it => it.typeParamList()} ?? return None
            let param = (params.typeParams() |> skip(index) |> first) ?? return None
            let name = param.name()?.syntax.textRange ?? param.syntax.textRange
            NavigationTarget(file.fileId(db), param.syntax.textRange, name)
        case QualifierOf(_) => None
    }
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
