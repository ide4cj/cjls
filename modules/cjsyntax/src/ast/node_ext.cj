package cjsyntax.ast

import std.collection.*
import ginkgo.*
import cjsyntax.SyntaxKind

// The accessors `syntax_codegen` leaves out, of children the grammar tells neither by the tokens around them nor by
// position: each is found by the tokens around it as only this code knows them.

let R_PAREN = TokenSet<SyntaxKind>([SyntaxKind.RParen])
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
 * The text of `token`; an identifier's without its backquotes, as a name is (A20).
 */
public func identText(token: SyntaxToken<SyntaxKind>): String {
    if (token.kind == SyntaxKind.Ident) {
        unquoted(token.text())
    } else {
        token.text()
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
 * The comments the parser gave `node` as its documentation, among the trivia it starts with, after
 * those of the macro calls around it, outermost first: before `@M class C`, they go to the call.
 */
func docCommentsOf(node: SyntaxNode<SyntaxKind>): Array<SyntaxToken<SyntaxKind>> {
    let calls = ArrayList<SyntaxNode<SyntaxKind>>()
    var parent = node.parent
    while (let Some(one) <- parent && one.kind == SyntaxKind.MacroExpandDecl) {
        calls.add(one)
        parent = one.parent
    }
    calls.reverse()
    let comments = ArrayList<SyntaxToken<SyntaxKind>>()
    for (call in calls) {
        comments.add(all: leadingComments(call))
    }
    comments.add(all: leadingComments(node))
    comments.toArray()
}

private func leadingComments(node: SyntaxNode<SyntaxKind>): Array<SyntaxToken<SyntaxKind>> {
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

extend SpawnExpr {
    /**
     * The lambda the thread runs.
     */
    public func lambda(): ?LambdaExpr {
        if (lParenToken().isSome()) {
            astChildBetween<SyntaxKind, LambdaExpr>(node, R_PAREN, None)
        } else {
            astChild<SyntaxKind, LambdaExpr>(node)
        }
    }
}
