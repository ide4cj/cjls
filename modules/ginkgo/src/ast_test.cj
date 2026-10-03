package ginkgo

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * A view of `Inner` and `Leaf` nodes, as generated code would declare one.
 */
struct Nested <: AstNode<TestKind, Nested> {
    Nested(let node: SyntaxNode<TestKind>) {}

    public static func canCast(kind: TestKind): Bool {
        kind == Inner || kind == Leaf
    }

    public static func cast(node: SyntaxNode<TestKind>): ?Nested {
        if (canCast(node.kind)) {
            Nested(node)
        } else {
            None
        }
    }

    public prop syntax: SyntaxNode<TestKind> {
        get() {
            node
        }
    }
}

func kindsOf(nodes: Iterator<Nested>): Array<TestKind> {
    collectArray(nodes.map {n => n.syntax.kind})
}

@Test
class AstSupportTest {
    let root = sampleTree()

    @TestCase
    func childIsTheFirstChildOfTheViewedKinds() {
        // act
        let child = astChild<TestKind, Nested>(root)

        // assert
        @Expect(child.map {n => n.syntax.kind}, Some(Inner))
    }

    @TestCase
    func childrenAreEveryChildOfTheViewedKindsInOrder() {
        // act & assert
        @Expect(kindsOf(astChildren<TestKind, Nested>(root)), [Inner, Leaf])
    }

    @TestCase
    func nthChildCountsOnlyTheKindsItIsGiven() {
        // arrange
        let counted = TokenSet<TestKind>([Inner, Leaf])

        // act & assert
        @Expect(astNthChild<TestKind, Nested>(root, 1, counted).map {n => n.syntax.text()}, Some("d"))
        @Expect(astNthChild<TestKind, Nested>(root, 2, counted).isNone())
    }

    @TestCase
    func childrenFromSkipTheFirstCountedChildren() {
        // arrange
        let counted = TokenSet<TestKind>([Inner])

        // act & assert
        @Expect(kindsOf(astChildrenFrom<TestKind, Nested>(root, 1, counted)), [Leaf])
        @Expect(kindsOf(astChildrenFrom<TestKind, Nested>(root, 0, counted)), [Inner, Leaf])
    }

    @TestCase
    func childrenBetweenAreAfterTheFirstTokenOfStartAndBeforeTheNextOfEnd() {
        // arrange
        let spaces = TokenSet<TestKind>([Space])
        let words = TokenSet<TestKind>([Word])

        // act & assert
        @Expect(kindsOf(astChildrenBetween<TestKind, Nested>(root, spaces, spaces)), [Inner])
        @Expect(kindsOf(astChildrenBetween<TestKind, Nested>(root, words, None)), [Inner, Leaf])
        @Expect(kindsOf(astChildrenBetween<TestKind, Nested>(root, None, None)), [Inner, Leaf])
        @Expect(astChildBetween<TestKind, Nested>(root, spaces, None).map {n => n.syntax.kind}, Some(Inner))
    }

    @TestCase
    func aChildBetweenTokensThatAreNotThereIsNone() {
        // arrange
        let words = TokenSet<TestKind>([Word])
        let none = TokenSet<TestKind>([Root])

        // act & assert
        @Expect(astChildBetween<TestKind, Nested>(root, None, words).isNone())
        @Expect(astChildBetween<TestKind, Nested>(root, none, None).isNone())
    }

    @TestCase
    func tokenIsTheFirstOwnTokenOfAKind() {
        // arrange
        let inner = astChild<TestKind, Nested>(root).getOrThrow().syntax

        // act & assert
        @Expect(astToken(root, Space).map {t => t.textRange.start}, Some(1))
        @Expect(astToken(inner, Word).map {t => t.text()}, Some("b"))
        @Expect(astToken(inner, Space).isNone())
        @Expect(astToken(root, TokenSet<TestKind>([Space, Word])).map {t => t.text()}, Some("a"))
    }
}
