package loupe

import std.collection.*
import std.deriving.*
import ginkgo.{SyntaxElement, SyntaxNodePtr}
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{AnyHasName, BinExpr, MemberAccessExpr, Name, NameRef, Param, ParenExpr, Pattern, PostfixExpr,
    RefExpr, TupleExpr, VarDecl, identText}
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.hir.{DefId, ItemFile, itemIdMap}
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * How a name reaches what it means: reads it, or gives it a value.
 */
@Derive[Equatable]
public enum ReferenceAccess <: ToString {
    | ReadAccess
    | WriteAccess

    public func toString(): String {
        match (this) {
            case ReadAccess => "read"
            case WriteAccess => "write"
        }
    }
}

/**
 * A name of the file meaning what the one asked about does, and how it reaches it; `None` for a name
 * that neither reads nor writes: a declaration but of a `var`, a name in a type or a pattern.
 */
@Derive[Equatable]
public struct RelatedHighlight {
    public RelatedHighlight(public let range: TextRange, public let access: ?ReferenceAccess) {}
}

/**
 * Every name of the file meaning what the name at `offset` does, the declaration among them when in
 * the file, in the file's order: a local only in its own scope, a member only reached through its type,
 * of overloads only the one a call takes (`calleeOf`, as `definitionAt`); rust-analyzer's
 * `highlight_related`. Nothing for a name meaning nothing, nor for a name a macro declares (#175).
 */
public func highlightRelated(db: AnalysisDatabase, fileId: FileId, offset: Int64): Array<RelatedHighlight> {
    let file = db.sourceFile(fileId) ?? return []
    let root = parse(db, file).syntaxNode()
    let token = tokenAt(root, offset) ?? return []
    if (token.kind != SyntaxKind.Ident) {
        return []
    }
    let meant = meaningsAt(db, file, token)
    if (meant.isEmpty()) {
        return []
    }
    // the names spelled as it, then those of them meaning it, as rust-analyzer's `FindUsages` searches
    let name = identText(token)
    root.descendantsWithTokens() |> filterMap {element: SyntaxElement<SyntaxKind> => element.asToken()} |> filter {
        one: CjSyntaxToken => one.kind == SyntaxKind.Ident && identText(one) == name
    } |> filter {
        one: CjSyntaxToken => meaningsAt(db, file, one).any {symbol: Symbol => meant.contains(symbol)}
    } |> map {one: CjSyntaxToken => RelatedHighlight(one.textRange, accessOf(one))} |> collectArray
}

/**
 * What the name `token` means: the item it is the name of at its declaration, what `definitionAt` goes to anywhere
 * else.
 */
func meaningsAt(db: AnalysisDatabase, file: SourceFile, token: CjSyntaxToken): Array<Symbol> {
    if (let Some(name) <- Name.cast(token.parent)) {
        let decl = name.syntax.parent ?? return []
        if (let Some(item) <- itemIdMap(db, file).idOf(SyntaxNodePtr(decl)) &&
            (AnyHasName.cast(decl).flatMap {it => it.name()}.map {it => it.syntax == name.syntax} ?? false)) {
            return [DeclSymbol(DefId(db, ItemFile.Source(file), item))]
        }
    }
    symbolsAt(db, file, token)
}

/**
 * The operators of an assignment.
 */
let ASSIGNMENTS = [SyntaxKind.Eq, SyntaxKind.PlusEq, SyntaxKind.MinusEq, SyntaxKind.StarEq,
    SyntaxKind.StarStarEq, SyntaxKind.SlashEq, SyntaxKind.PercentEq, SyntaxKind.AmpAmpEq, SyntaxKind.PipePipeEq,
    SyntaxKind.AmpEq, SyntaxKind.PipeEq, SyntaxKind.CaretEq, SyntaxKind.LtLtEq, SyntaxKind.GtGtEq]

/**
 * How the name `token` reaches what it means: an expression is written as the left side of an assignment, compound
 * ones included, a part of a tuple there, or by `++` and `--`, and read anywhere else; a declaration writes a `var`.
 */
func accessOf(token: CjSyntaxToken): ?ReferenceAccess {
    let parent = token.parent
    if (let Some(name) <- Name.cast(parent)) {
        return if (declaresVar(name)) {
            WriteAccess
        } else {
            None
        }
    }
    let ref = NameRef.cast(parent) ?? return None
    let used = ref.syntax.parent ?? return None
    if (!RefExpr.canCast(used.kind) && !MemberAccessExpr.canCast(used.kind)) {
        return None
    }
    // a part of a tuple assigned to, in parentheses or not
    let expr = (used.ancestors() |> filter {
        node: CjSyntaxNode => !(node.parent.map {outer => groups(outer)} ?? false)
    } |> first) ?? used
    let outer = expr.parent ?? return ReadAccess
    if (let Some(assignment) <- BinExpr.cast(outer)) {
        let assigns = assignment.op().map {op => ASSIGNMENTS.contains(op.kind)} ?? false
        if (assigns && (assignment.lhs().map {lhs => lhs.syntax == expr} ?? false)) {
            return WriteAccess
        }
    }
    if (let Some(postfix) <- PostfixExpr.cast(outer)) {
        if (let Some(op) <- postfix.op() && (op.kind == SyntaxKind.PlusPlus || op.kind == SyntaxKind.MinusMinus)) {
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
    let decl = name.syntax.ancestors() |> filter {
        node: CjSyntaxNode => !Name.canCast(node.kind) && !Pattern.canCast(node.kind)
    } |> first
    match (decl) {
        case Some(node) => VarDecl.cast(node).flatMap {it => it.varToken()}.isSome() ||
            Param.cast(node).flatMap {it => it.varToken()}.isSome()
        case None => false
    }
}
