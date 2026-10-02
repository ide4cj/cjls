package cjsyntax.ast

import std.collection.*
import ginkgo.*
import cjsyntax.SyntaxKind

// The accessors `syntax_codegen` leaves out, of children the grammar cannot tell by position alone: each is found
// by the tokens around it instead.

let COLON = TokenSet<SyntaxKind>([SyntaxKind.Colon])
let L_PAREN = TokenSet<SyntaxKind>([SyntaxKind.LParen])
let R_PAREN = TokenSet<SyntaxKind>([SyntaxKind.RParen])
let ARROW = TokenSet<SyntaxKind>([SyntaxKind.Arrow])
let CASE = TokenSet<SyntaxKind>([SyntaxKind.CaseKw])
let FAT_ARROW = TokenSet<SyntaxKind>([SyntaxKind.FatArrow])
let VISIBILITY = TokenSet<SyntaxKind>([SyntaxKind.PublicKw, SyntaxKind.ProtectedKw, SyntaxKind.InternalKw,
    SyntaxKind.PrivateKw])

extend Name {
    /**
     * The name declared, without the backquotes of `` `foo` ``, which is the name `foo`: what tells it from
     * others. An operator's is its tokens, as `[]`.
     */
    public func text(): String {
        match (identToken()) {
            case Some(ident) => unquoted(ident.text())
            case None => compactText(node)
        }
    }
}

extend NameRef {
    /**
     * The name used, without the backquotes of `` `foo` ``.
     */
    public func text(): String {
        match (identToken()) {
            case Some(ident) => unquoted(ident.text())
            case None => ""
        }
    }
}

/**
 * An identifier without its backquotes; one left open, as while it is typed, without the first.
 */
func unquoted(ident: String): String {
    if (!ident.startsWith("`")) {
        return ident
    }
    if (ident.size >= 2 && ident.endsWith("`")) {
        ident[1..ident.size - 1]
    } else {
        ident[1..]
    }
}

/**
 * The tokens of `node` but whitespace and comments, one after another.
 */
func compactText(node: SyntaxNode<SyntaxKind>): String {
    let text = StringBuilder()
    for (element in node.childrenWithTokens()) {
        if (let SyntaxElement.Token(token) <- element && !token.kind.isTrivia()) {
            text.append(token.text())
        }
    }
    text.toString()
}

extend Modifiers {
    /**
     * Whether a modifier of `kind` is written.
     */
    public func has(kind: SyntaxKind): Bool {
        astToken(node, kind).isSome()
    }

    /**
     * `public`, `protected`, `internal` or `private`, if one is written; the first of them if several are.
     */
    public func visibility(): ?SyntaxToken<SyntaxKind> {
        astToken(node, VISIBILITY)
    }

    public func isStatic(): Bool {
        has(SyntaxKind.StaticKw)
    }

    public func isOpen(): Bool {
        has(SyntaxKind.OpenKw)
    }

    public func isConst(): Bool {
        has(SyntaxKind.ConstKw)
    }
}

/**
 * The comments among the trivia `node` starts with: those the parser gave it as its documentation.
 */
func docCommentsOf(node: SyntaxNode<SyntaxKind>): Array<SyntaxToken<SyntaxKind>> {
    let comments = ArrayList<SyntaxToken<SyntaxKind>>()
    for (element in node.childrenWithTokens()) {
        match (element) {
            case SyntaxElement.Token(token) where token.kind == SyntaxKind.LineComment ||
                token.kind == SyntaxKind.BlockComment => comments.add(token)
            case SyntaxElement.Token(token) where token.kind.isTrivia() => ()
            case _ => break
        }
    }
    comments.toArray()
}

extend RangeExpr {
    /**
     * What the range starts at: the expression before `..`, if there is one.
     */
    public func start(): ?Expr {
        childBetween<Expr>(node, None, RANGE_EXPR_OP)
    }

    /**
     * What the range ends at: the expression after `..`, if there is one.
     */
    public func end(): ?Expr {
        childBetween<Expr>(node, RANGE_EXPR_OP, COLON)
    }

    /**
     * The step after `:`.
     */
    public func step(): ?Expr {
        childBetween<Expr>(node, COLON, None)
    }
}

extend FuncType {
    /**
     * The types of the parameters, between the parentheses.
     */
    public func types(): Iterator<Type> {
        childrenBetween<Type>(node, L_PAREN, R_PAREN)
    }

    /**
     * The return type, after `->`.
     */
    public func ret(): ?Type {
        childBetween<Type>(node, ARROW, None)
    }
}

extend MatchCase {
    /**
     * The condition of a case in a `match` without a selector.
     */
    public func condition(): ?Expr {
        childBetween<Expr>(node, CASE, FAT_ARROW)
    }

    /**
     * What the case runs, after `=>`.
     */
    public func stmts(): Iterator<Stmt> {
        childrenBetween<Stmt>(node, FAT_ARROW, None)
    }
}

extend SpawnExpr {
    /**
     * The thread context between the parentheses of `spawn (context)`.
     */
    public func context(): ?Expr {
        childBetween<Expr>(node, L_PAREN, R_PAREN)
    }

    /**
     * The lambda the thread runs.
     */
    public func lambda(): ?LambdaExpr {
        if (lParenToken().isSome()) {
            childBetween<LambdaExpr>(node, R_PAREN, None)
        } else {
            astChild<SyntaxKind, LambdaExpr>(node)
        }
    }
}

/**
 * The first `T` among the children of `parent` after its first token in `from`, and before the next one in `to`
 * after that: `None` for the start or the end.
 */
func childBetween<T>(parent: SyntaxNode<SyntaxKind>, from: ?TokenSet<SyntaxKind>, to: ?TokenSet<SyntaxKind>): ?T where T <: AstNode<SyntaxKind,
    T> {
    childrenBetween<T>(parent, from, to).next()
}

/**
 * The `T`s among the children of `parent` after its first token in `from`, and before the next one in `to` after
 * that: `None` for the start or the end.
 */
func childrenBetween<T>(parent: SyntaxNode<SyntaxKind>, from: ?TokenSet<SyntaxKind>, to: ?TokenSet<SyntaxKind>): Iterator<T> where T <: AstNode<SyntaxKind,
    T> {
    Between(parent.childrenWithTokens(), from, to).filterMap {n => T.cast(n)}
}

class Between <: Iterator<SyntaxNode<SyntaxKind>> {
    var started: Bool
    var ended = false

    Between(
        let inner: Iterator<SyntaxElement<SyntaxKind>>,
        let from: ?TokenSet<SyntaxKind>,
        let to: ?TokenSet<SyntaxKind>
    ) {
        started = from.isNone()
    }

    public func next(): ?SyntaxNode<SyntaxKind> {
        while (!ended) {
            match (inner.next()) {
                case None => ended = true
                case Some(SyntaxElement.Token(t)) where !started => started = from?.contains(t.kind) ?? false
                case Some(SyntaxElement.Token(t)) => ended = to?.contains(t.kind) ?? false
                case Some(SyntaxElement.Node(n)) where started => return n
                case Some(SyntaxElement.Node(_)) => ()
            }
        }
        None
    }
}
