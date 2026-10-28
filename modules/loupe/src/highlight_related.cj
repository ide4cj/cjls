package loupe

import std.collection.*
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{
    AnyHasName,
    BinExpr,
    MemberAccessExpr,
    Name,
    NameRef,
    Param,
    ParenExpr,
    Pattern,
    PostfixExpr,
    RefExpr,
    TupleExpr,
    TypeParam,
    TypeParamList,
    VarDecl,
    identText,
    isIdent
}
import ginkgo.{SyntaxElement, SyntaxNodePtr}
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.hir.{BodySource, DefId, ItemFile, LocalFunc, TypeTarget, bodyWithSourceMap, itemIdMap}
import loupe.syntax.parse
import loupe.vfs.FileId
import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * How a name reaches what it means: reads it, or gives it a value.
 */
@DerivePython
public enum ReferenceAccess <: ToString & Equatable<ReferenceAccess> {
    | ReadAccess
    | WriteAccess

    public func toString(): String {
        match (this) {
            case ReadAccess => "read"
            case WriteAccess => "write"
        }
    }

    public operator func ==(other: ReferenceAccess): Bool {
        match ((this, other)) {
            case (ReferenceAccess.ReadAccess, ReferenceAccess.ReadAccess) => true
            case (ReferenceAccess.WriteAccess, ReferenceAccess.WriteAccess) => true
            case _ => false
        }
    }

    public operator func !=(other: ReferenceAccess): Bool {
        !(this == other)
    }
}

/**
 * A name of the file meaning what the one asked about does, and how it reaches it; `None` for a name
 * that neither reads nor writes: a declaration but of a `var`, a name in a type or a pattern.
 */
@DerivePython
public struct RelatedHighlight <: Equatable<RelatedHighlight> {
    public RelatedHighlight(public let range: TextRange, public let access: ?ReferenceAccess) {}

    public operator func ==(other: RelatedHighlight): Bool {
        range == other.range && access == other.access
    }

    public operator func !=(other: RelatedHighlight): Bool {
        !(this == other)
    }
}

/**
 * Every name of the file meaning what the name at `offset` does, the declaration among them when in
 * the file, in the file's order: a local only in its own scope, a member only reached through its type,
 * of overloads only the one a call takes (`calleeOf`, as `definitionAt`); rust-analyzer's
 * `highlight_related`. Nothing for a name meaning nothing, nor for a name a macro declares (#175).
 */
public func highlightRelated(
    db: AnalysisDatabase,
    fileId: FileId,
    offset: Int64
): Array<RelatedHighlight> {
    let file = db.sourceFile(fileId) ?? return []
    let root = parse(db, file).syntaxNode()
    let token = tokenAt(root, offset) ?? return []
    if (!isIdent(token)) {
        return []
    }
    let meant = meaningsAt(db, file, token)
    if (meant.isEmpty()) {
        return []
    }
    namesMeaning(db, file, root, [identText(token)], meant)
        .map { one => RelatedHighlight(one.textRange, accessOf(one)) }
}

/**
 * The names of `file`, whose tree is `root`, spelled as one of `names` and meaning any of `meant`, in the file's
 * order: the names spelled so first, then those of them meaning it, as rust-analyzer's `FindUsages` searches.
 */
func namesMeaning(
    db: AnalysisDatabase,
    file: SourceFile,
    root: CjSyntaxNode,
    names: Array<String>,
    meant: Array<Definition>
): Array<CjSyntaxToken> {
    root.descendantsWithTokens() |>
        filterMap { element: SyntaxElement<SyntaxKind> => element.asToken() } |>
        filter { one: CjSyntaxToken => isIdent(one) && names.contains(identText(one)) } |>
        filter {
            one: CjSyntaxToken =>
            meaningsAt(db, file, one).any { definition: Definition => meant.contains(definition) }
        } |>
        collectArray
}

/**
 * What the name `token` means: the item or type parameter it is the name of at its declaration, what `classifyName`
 * says anywhere else; a parameter of a primary constructor as the local it is in the constructor's body, whether
 * named as that or as a member, and a package as nothing.
 */
func meaningsAt(db: AnalysisDatabase, file: SourceFile, token: CjSyntaxToken): Array<Definition> {
    if (let Some(name) <- Name.cast(token.parent)) {
        let decl = name.syntax.parent ?? return []
        if (let Some(param) <- TypeParam.cast(decl)) {
            return match (typeParamTarget(db, file, param)) {
                case Some(target) => [Definition.TypeParamDef(target)]
                case None => []
            }
        }
        if (
            let Some(item) <- itemIdMap(db, file).idOf(SyntaxNodePtr(decl)) &&
                (
                    AnyHasName
                        .cast(decl)
                        .flatMap { it => it.name() }
                        .map { it => it.syntax == name.syntax } ??
                        false
                )
        ) {
            return [Definition.DeclDef(DefId(db, ItemFile.Source(file), item))]
        }
    }
    let defs =
        classifyName(db, file, itemAround(db, ItemFile.Source(file), token.parent), token) ??
            return []
    defs |>
        filterMap {
            definition: Definition =>
            match (definition) {
                case MemberParamDef(ctor, local) => Some(Definition.LocalDef(ctor, local))
                case PackageDef(_) => None
                case _ => Some(definition)
            }
        } |>
        collectArray
}

/**
 * The type parameter `param` of `file` declares, as its uses name it: of the item it is of, or of a function a body
 * declares (N68).
 */
func typeParamTarget(db: AnalysisDatabase, file: SourceFile, param: TypeParam): ?TypeTarget {
    let list = param.syntax.parent.flatMap { node => TypeParamList.cast(node) } ?? return None
    let decl = list.syntax.parent ?? return None
    let index =
        (
            list.typeParams() |> enumerate |>
                filter { pair: (Int64, TypeParam) => pair[1] == param } |>
                map { pair: (Int64, TypeParam) => pair[0] } |>
                first
        ) ??
            return None
    if (let Some(item) <- itemIdMap(db, file).idOf(SyntaxNodePtr(decl))) {
        return TypeTarget.GenericOf(DefId(db, ItemFile.Source(file), item), index)
    }
    let name = AnyHasName.cast(decl).flatMap { it => it.name() } ?? return None
    let owner = itemAround(db, ItemFile.Source(file), decl) ?? return None
    let lowered = bodyWithSourceMap(db, owner)
    let ptr = SyntaxNodePtr(name.syntax)
    let localFunc =
        (
            lowered.body.funcs |> enumerate |>
                filter {
                    pair: (Int64, LocalFunc) =>
                    lowered.sourceMap.locals.get(pair[1].local.index) ==
                        Some(WrittenSource(BodySource(ptr)))
                } |>
                map { pair: (Int64, LocalFunc) => pair[0] } |>
                first
        ) ??
            return None
    TypeTarget.LocalGenericOf(owner, localFunc, index)
}

/**
 * The operators of an assignment.
 */
let ASSIGNMENTS =
    [
        SyntaxKind.Eq,
        SyntaxKind.PlusEq,
        SyntaxKind.MinusEq,
        SyntaxKind.StarEq,
        SyntaxKind.StarStarEq,
        SyntaxKind.SlashEq,
        SyntaxKind.PercentEq,
        SyntaxKind.AmpAmpEq,
        SyntaxKind.PipePipeEq,
        SyntaxKind.AmpEq,
        SyntaxKind.PipeEq,
        SyntaxKind.CaretEq,
        SyntaxKind.LtLtEq,
        SyntaxKind.GtGtEq
    ]

/**
 * How the name `token` reaches what it means: an expression is written as the left side of an assignment, compound
 * ones included, a part of a tuple there, or by `++` and `--`, and read anywhere else; a declaration writes a `var`.
 */
func accessOf(token: CjSyntaxToken): ?ReferenceAccess {
    let parent = token.parent
    if (let Some(name) <- Name.cast(parent)) {
        return if (declaresVar(name)) { WriteAccess } else { None }
    }
    let ref = NameRef.cast(parent) ?? return None
    let used = ref.syntax.parent ?? return None
    if (!RefExpr.canCast(used.kind) && !MemberAccessExpr.canCast(used.kind)) {
        return None
    }
    // a part of a tuple assigned to, in parentheses or not
    let expr =
        (
            used.ancestors() |>
                filter {
                    node: CjSyntaxNode =>
                    !(node.parent.map { outer => groups(outer) } ?? false)
                } |>
                first
        ) ??
            used
    let outer = expr.parent ?? return ReadAccess
    if (let Some(assignment) <- BinExpr.cast(outer)) {
        let assigns = assignment.op().map { op => ASSIGNMENTS.contains(op.kind) } ?? false
        if (assigns && (assignment.lhs().map { lhs => lhs.syntax == expr } ?? false)) {
            return WriteAccess
        }
    }
    if (let Some(postfix) <- PostfixExpr.cast(outer)) {
        if (
            let Some(op) <- postfix.op() &&
                (op.kind == SyntaxKind.PlusPlus || op.kind == SyntaxKind.MinusMinus)
        ) {
            return WriteAccess
        }
    }
    ReadAccess
}

/**
 * Whether `node` only groups what it holds: parentheses, a tuple.
 */
func groups(node: CjSyntaxNode): Bool {
    ParenExpr.canCast(node.kind) || TupleExpr.canCast(node.kind)
}

/**
 * Whether `name` is declared by a `var`, a parameter of a primary constructor's included, through the patterns it is in.
 */
func declaresVar(name: Name): Bool {
    let decl =
        name.syntax.ancestors() |>
            filter {
                node: CjSyntaxNode =>
                !Name.canCast(node.kind) && !Pattern.canCast(node.kind)
            } |>
            first
    match (decl) {
        case Some(node) =>
            VarDecl.cast(node).flatMap { it => it.varToken() }.isSome() ||
                Param.cast(node).flatMap { it => it.varToken() }.isSome()
        case None => false
    }
}
