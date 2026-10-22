# ginkgo

`ginkgo` owns language-independent lossless trees and parser machinery;
[`cjsyntax`](../cjsyntax/README.md) owns the Cangjie grammar. It has no project
dependencies. Tree kinds stay generic over `K <: Kind<K>` rather than becoming a
language-specific or raw integer representation.

## Tree ownership

Green nodes are immutable and store kind, children and text length. The
[`NodeCache`](src/node_cache.cj) interns tokens and nodes with at most three
children; larger nodes rarely repeat and cost more to hash. Red nodes add parent,
index and offset on demand; values representing the same node compare equal.
Replacing a subtree rebuilds its ancestors and shares the rest.

A red node retains its tree. Analysis results use kind/range pointers under
[A13](../../docs/design/02-analysis.md#a13-do-not-retain-syntax-trees), resolved
against the tree they came from or one with the same text. Keep `AstPtr`'s
handwritten equality/hash: [K8](../../docs/sdk-issues.md#k8) records the nested
generic deriving compiler crash and the limits of the available evidence.
Keep pointer resolution's recursion in `resolveSyntaxNode`, with kind/range as
ordinary arguments: the recursive generic-struct receiver faults under the
pinned SDK's coverage build ([K26](../../docs/sdk-issues.md#k26)).

## Lossless parsing

Parsing separates lexing, grammar events and tree construction. Lexing covers the
text exactly, including trivia. Parser input excludes trivia but retains newline
and token-jointness information. Markers describe nodes; preceding a completed
marker wraps an earlier expression without rewriting the event stream.
[`buildTree`](src/parsing/tree_builder.cj) inserts trivia again. Leading trivia
belongs to the parent unless the language's trivia rules attach it to the node.
Unconsumed tokens become a trailing error node, preserving the whole text.

Speculative grammar branches can snapshot and rewind. Rewinding must not reset
the progress guard: a grammar repeatedly trying the same input must fail rather
than hang. Grammar exceptions are caught by `parseWith`, producing the tokens
under an error node and a diagnostic. Structured expected-kind errors stay
language-independent; spelling them for a user belongs to the language layer.
See the executable examples in [parser tests](src/parsing/parser_test.cj).

## Block reparsing

[`Reparser`](src/parsing/reparsing.cj) implements the block path of
[D110](../../docs/adr/0110-a-speculative-tree-reparses-the-block-around-the-cursor.md),
without token reparsing. It accepts an edit only when the enclosing block remains
balanced, its grammar consumes the whole block and the result has the expected
kind. Otherwise it returns `None` for the caller to perform a full parse.

A reparseable block must receive no attached trivia, and its grammar must work
without context outside the block. These preconditions preserve the full-parse
result when replacing only that subtree. The language supplies delimiter kinds
and eligible block grammars; ginkgo has no Cangjie-specific recovery rules.
