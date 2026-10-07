package loupe

import std.collection.*
import std.deriving.*
import std.sort.*
import ginkgo.SyntaxElement
import rope.Rope
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase
import loupe.syntax.parse

/**
 * What a fold is: LSP names the first two, the others are for whoever tells folds apart.
 */
@Derive[Equatable]
public enum FoldKind <: ToString {
    // a block comment, or line comments one under the other
    | Comment
    // `import`s one under the other
    | Imports
    // a body, a block, a lambda, a `match`'s cases
    | Block
    // one case of a `match`
    | MatchArm
    // arguments, parameters, type arguments and parameters, the names of an `import`
    | ArgList
    // an array or a tuple literal
    | ArrayLiteral
    | StringLiteral

    public func toString(): String {
        match (this) {
            case Comment => "Comment"
            case Imports => "Imports"
            case Block => "Block"
            case MatchArm => "MatchArm"
            case ArgList => "ArgList"
            case ArrayLiteral => "ArrayLiteral"
            case StringLiteral => "StringLiteral"
        }
    }
}

/**
 * A part of a file over more than one line an editor may fold. `range` is in UTF-8 bytes (A6) and
 * covers the delimiters, `{` to `}`: what is left visible is the client's to choose.
 */
@Derive[Equatable]
public struct Fold <: ToString {
    public Fold(public let range: TextRange, public let kind: FoldKind) {}

    /**
     * `kind@start..end`.
     */
    public func toString(): String {
        "${kind}@${range.start}..${range.end}"
    }
}

/**
 * What of a file folds, by its tree, sorted by start, an outer fold before an inner one starting
 * with it; empty for a file the database does not know. A node inside an `ErrorNode` folds as well
 * as it parsed.
 *
 * Not a query: what it reads, `parse`, is one, and folding is a walk over its tree.
 */
public func foldingRanges(db: AnalysisDatabase, fileId: FileId): Array<Fold> {
    let file = db.sourceFile(fileId) ?? return []
    let folder = Folder(db, file.text(db))
    folder.walk(parse(db, file).syntaxNode())
    let result = folder.result
    sort(result, stable: true, by: {a: Fold, b: Fold => a.range.start.compare(b.range.start)})
    result.toArray()
}

/**
 * Nodes that fold over more than one line, and as what.
 */
func foldKindOf(kind: SyntaxKind): ?FoldKind {
    match (kind) {
        case SyntaxKind.DeclBody | SyntaxKind.EnumBody | SyntaxKind.PropBody | SyntaxKind.Block |
            SyntaxKind.LambdaExpr | SyntaxKind.MatchBody => FoldKind.Block
        case SyntaxKind.MatchCase => FoldKind.MatchArm
        case SyntaxKind.ArgList | SyntaxKind.ParamList | SyntaxKind.TypeArgList | SyntaxKind.TypeParamList |
            SyntaxKind.AnnotationArgList | SyntaxKind.MacroArgs | SyntaxKind.ImportTreeList => FoldKind.ArgList
        case SyntaxKind.ArrayExpr | SyntaxKind.TupleExpr => FoldKind.ArrayLiteral
        case SyntaxKind.StringLit => FoldKind.StringLiteral
        case _ => None
    }
}

class Folder {
    Folder(private let db: AnalysisDatabase, private let text: Rope) {}

    let result = ArrayList<Fold>()
    private var tokens = 0
    // the line comments one under the other so far, and the end of the last
    private var comments: ?TextRange = None

    func walk(root: CjSyntaxNode): Unit {
        imports(root)
        for (element in root.descendantsWithTokens()) {
            match (element) {
                case SyntaxElement.Node(node) => if (let Some(kind) <- foldKindOf(node.kind)) {
                    add(node.textRange, kind)
                }
                case SyntaxElement.Token(token) => visit(token)
            }
        }
        endComments()
    }

    /**
     * The `import`s of a file, a run each until a blank line, a comment or anything else.
     */
    private func imports(root: CjSyntaxNode): Unit {
        var run: ?TextRange = None
        for (element in root.childrenWithTokens()) {
            match (element) {
                case SyntaxElement.Node(node) where node.kind == SyntaxKind.ImportDecl => run = match (run) {
                    case Some(it) => TextRange(it.start, node.textRange.end)
                    case None => node.textRange
                }
                case SyntaxElement.Token(token) where isSpacing(token) || token.kind == SyntaxKind.Semicolon => ()
                case _ =>
                    if (let Some(it) <- run) {
                        add(it, FoldKind.Imports)
                    }
                    run = None
            }
        }
        if (let Some(it) <- run) {
            add(it, FoldKind.Imports)
        }
    }

    private func visit(token: CjSyntaxToken): Unit {
        tokens++
        if (tokens % TOKENS_BETWEEN_CHECKS == 0) {
            db.unwindIfCancelled()
        }
        match (token.kind) {
            case SyntaxKind.LineComment => comments = match (comments) {
                case Some(it) => TextRange(it.start, token.textRange.end)
                case None => token.textRange
            }
            case _ where isSpacing(token) => ()
            case _ =>
                endComments()
                if (token.kind == SyntaxKind.BlockComment) {
                    add(token.textRange, FoldKind.Comment)
                } else if (token.kind == SyntaxKind.RawStringLit) {
                    add(token.textRange, FoldKind.StringLiteral)
                }
        }
    }

    /**
     * What may stand between two comments, or two imports, of one fold: no blank line.
     */
    private func isSpacing(token: CjSyntaxToken): Bool {
        token.kind == SyntaxKind.Whitespace || token.kind == SyntaxKind.Newline && token.text().count("\n") <= 1
    }

    private func endComments(): Unit {
        if (let Some(it) <- comments) {
            add(it, FoldKind.Comment)
        }
        comments = None
    }

    /**
     * Only over more than one line.
     */
    private func add(range: TextRange, kind: FoldKind): Unit {
        if (text.lineOf(range.start) != text.lineOf(range.end)) {
            result.add(Fold(range, kind))
        }
    }
}
