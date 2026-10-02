package ginkgo

/**
 * A typed view of a syntax node: a struct wrapping a node of one kind, or an enum of such
 * views for a node that may be one of several. Views are generated from the language's grammar; they only read
 * the tree, and a child missing from a tree with errors is `None`, never a failure.
 */
public interface AstNode<K, T> where K <: Kind<K> {
    /**
     * Whether a node of `kind` can be viewed as `T`.
     */
    @Frozen
    static func canCast(kind: K): Bool

    @Frozen
    static func cast(node: SyntaxNode<K>): ?T

    prop syntax: SyntaxNode<K>
}

/**
 * The first child of `parent` that is a `T`. What generated accessors are made of.
 */
@Frozen
public func astChild<K, T>(parent: SyntaxNode<K>): ?T where K <: Kind<K>, T <: AstNode<K, T> {
    // a loop over the green children, not `astChildren(parent).next()`: a red node is made only for a child
    // of the right kind, and no iterator is (#22)
    let green = parent.green
    for (i in 0..green.childCount) {
        if (let GreenElement.Node(n) <- green.child(i)) {
            if (T.canCast(n.kind)) {
                if (let Some(it) <- T.cast(SyntaxNode(n, parent, i, parent.offset + green.childOffset(i)))) {
                    return it
                }
            }
        }
    }
    None
}

/**
 * The children of `parent` that are `T`s, in order.
 */
@Frozen
public func astChildren<K, T>(parent: SyntaxNode<K>): Iterator<T> where K <: Kind<K>, T <: AstNode<K, T> {
    AstChildren<K, T>(parent, 0, None)
}

/**
 * Among the children of `parent` whose kind is in `counted`, the one at `n`, if it is a `T`: the second `Expr` of
 * a binary expression, its right side. `counted` holds the kinds of every child that can come before it in the
 * grammar and be taken for it.
 */
@Frozen
public func astNthChild<K, T>(parent: SyntaxNode<K>, n: Int64, counted: TokenSet<K>): ?T where K <: Kind<K>,
    T <: AstNode<K, T> {
    let green = parent.green
    var seen = 0
    for (i in 0..green.childCount) {
        if (let GreenElement.Node(node) <- green.child(i)) {
            if (counted.contains(node.kind)) {
                if (seen == n) {
                    return if (T.canCast(node.kind)) {
                        T.cast(SyntaxNode(node, parent, i, parent.offset + green.childOffset(i)))
                    } else {
                        None
                    }
                }
                seen++
            }
        }
    }
    None
}

/**
 * The children of `parent` that are `T`s, but for the first `n` of those whose kind is in `counted`: the
 * indices of an index expression, after the expression indexed.
 */
@Frozen
public func astChildrenFrom<K, T>(parent: SyntaxNode<K>, n: Int64, counted: TokenSet<K>): Iterator<T> where K <: Kind<K>,
    T <: AstNode<K, T> {
    AstChildren<K, T>(parent, n, counted)
}

/**
 * The children of `parent` that are `T`s, but for the first `toSkip` of those whose kind is in `counted`: a red
 * node is made only for a child of the right kind.
 */
class AstChildren<K, T> <: Iterator<T> where K <: Kind<K>, T <: AstNode<K, T> {
    var i = 0

    AstChildren(let parent: SyntaxNode<K>, var toSkip: Int64, let counted: ?TokenSet<K>) {}

    @Frozen
    public func next(): ?T {
        let green = parent.green
        while (i < green.childCount) {
            let at = i
            i++
            if (let GreenElement.Node(n) <- green.child(at)) {
                if (toSkip > 0 && (counted?.contains(n.kind) ?? false)) {
                    toSkip--
                } else if (T.canCast(n.kind)) {
                    if (let Some(it) <- T.cast(SyntaxNode(n, parent, at, parent.offset + green.childOffset(at)))) {
                        return it
                    }
                }
            }
        }
        None
    }
}

/**
 * The first token of `parent`, not counting those inside its children, whose kind is `kind`.
 */
@Frozen
public func astToken<K>(parent: SyntaxNode<K>, kind: K): ?SyntaxToken<K> where K <: Kind<K> {
    // as `astChild`, a loop that makes the token only once found
    let green = parent.green
    for (i in 0..green.childCount) {
        if (let GreenElement.Token(t) <- green.child(i)) {
            if (t.kind == kind) {
                return SyntaxToken(t, parent, i, parent.offset + green.childOffset(i))
            }
        }
    }
    None
}

/**
 * The first token of `parent`, not counting those inside its children, whose kind is in `kinds`: the operator
 * of a binary expression.
 */
@Frozen
public func astToken<K>(parent: SyntaxNode<K>, kinds: TokenSet<K>): ?SyntaxToken<K> where K <: Kind<K> {
    ownTokens(parent).filter {t => kinds.contains(t.kind)}.next()
}

/**
 * The tokens of `parent`, not counting those inside its children, whose kind is `kind`: every `.` of a path.
 */
@Frozen
public func astTokens<K>(parent: SyntaxNode<K>, kind: K): Iterator<SyntaxToken<K>> where K <: Kind<K> {
    ownTokens(parent).filter {t => t.kind == kind}
}

@Frozen
func ownTokens<K>(parent: SyntaxNode<K>): Iterator<SyntaxToken<K>> where K <: Kind<K> {
    parent.childrenWithTokens().filterMap {el => el.asToken()}
}
