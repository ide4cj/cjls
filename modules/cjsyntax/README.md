# cjsyntax

The Cangjie lexer, grammar, recovery and typed tree views sit on
[`ginkgo`](../ginkgo/README.md). Trees retain every byte, including incomplete
input; diagnostics accompany the tree rather than replacing it. File,
expression and statement-fragment roots support source files and macro output
([D117](../../docs/adr/0117-expression-macros-are-asked-with-the-items-calls.md)).
Build and verification prerequisites are in [Development](../../docs/development.md).

## Compiler compatibility and recovery

The compiler parser (`cangjie_compiler/src/Parse`) is the grammar reference.
Important ambiguities live in the source and regression tests:

- Newlines normally end statements. A binary operator other than `-` and `?`,
  or a `.`, can continue an expression across one. Calls, indexing, trailing
  lambdas, `?`, `++` and `--` require the same line.
- `>` and `?` are lexed separately; the parser combines joint pieces into
  operators. Type arguments are speculative: failed parses rewind, and a
  comma-separated expression context applies the compiler's follower rule so
  `f(a < b, c > d)` remains two comparisons.
- Contextual keywords become identifiers where names are allowed. Builtin
  annotation names distinguish annotations from macro calls. String
  interpolations are lexed in pieces so their contents parse as code.

Structural restrictions belong in parsing; semantic checks such as conflicting
modifiers or annotation targets belong to later validation. Recovery deliberately
can differ from the compiler on invalid input: a line starting a top-level-only
declaration, behind annotations and modifiers, closes open bodies with an
`expected '}'` diagnostic so an unfinished body does not swallow the rest of the
file ([#102](https://github.com/ide4cj/cjls/issues/102)). Foreign blocks are exempt.
The implementation is `TOP_LEVEL_ONLY` and its recovery logic in
[grammar_items.cj](src/grammar_items.cj).

Cangjie trivia rules attach adjacent documentation comments to declarations and
parameters, stopping at a blank line. The language formats ginkgo's structured
expected-kind errors into messages; ginkgo does not know token spellings.

Block reparsing currently accepts `Block` alone. Declaration bodies depend on
surrounding context and are not independently reparseable. Rejected edits fall
back to a full parse; see [reparse.cj](src/reparse.cj) and
[D110](../../docs/adr/0110-a-speculative-tree-reparses-the-block-around-the-cursor.md).

## Generated tree views

[`syntax_kinds.toml`](syntax_kinds.toml) describes tokens, contextual keywords and
nodes without grammar rules. [`cangjie.ungram`](cangjie.ungram) describes tree
shape, **not the source-language grammar**. Together they generate kinds,
classification tables, lexer punctuation and typed AST views. Follow the
[generation procedure](../syntax_codegen/README.md#regenerate) when changing them.

Kinds and AST views live in separate packages because enum constructors share
their package namespace. Inside `cjsyntax.ast`, spell kinds as `SyntaxKind.X`.
New kinds must also avoid types used by `cjsyntax`: `ResourceDecl` avoids shadowing
`std.core.Resource`, and keyword kinds end in `Kw` so `Int64Kw` cannot hide
`Int64`. Generated union variants use `As<Member>` (or explicit grammar labels)
for the same reason.

Accessors must identify the intended child even in incomplete trees. The
generator uses surrounding separator tokens, including mutually exclusive
alternatives, rather than assuming that a missing child shifts its rival into
place ([D41](../../docs/adr/0041-accessors-are-told-by-tokens.md)). Position is safe
for the child a rule starts with and wraps. When neither is sufficient the
generator emits a note and leaves the accessor for
[node_ext.cj](src/ast/node_ext.cj), as with `SpawnExpr.lambda`. A labeled token
alternative yields one accessor; names colliding with Cangjie keywords need a
label (`ty` for a `Type` child).

Shared AST interfaces are derived from accessor availability; a union implements
one only when all variants do. Their definitions are in
[interfaces.cj](../syntax_codegen/src/interfaces.cj), rather than a separate
hand-maintained list. Canonical identifier text follows
[A20](../../docs/design/02-analysis.md#a20-canonical-name-text).

## Verification limits

Parser snapshots in [parser_test.cj](src/parser_test.cj) compare trees without
trivia plus errors. Generator checks separately enforce fresh output and tree
conformance; see [syntax_codegen verification](../syntax_codegen/README.md#verification).

The old module note reported a compiler-oracle comparison over about 98,000
`cangjie_test` files: lossless trees and no rejected file accepted by the compiler
parser (`std.ast.parseProgram`). Its harness, exact revision and SDK metadata are
not checked in. Treat it as historical evidence, not a result of the normal
suite or proof about the current grammar. Reproducible compiler-oracle integration
remains [#114](https://github.com/ide4cj/cjls/issues/114); conformance against the
ungrammar does not compare acceptance with the compiler.
