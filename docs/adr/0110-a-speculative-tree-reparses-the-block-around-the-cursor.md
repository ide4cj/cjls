# ADR-0110: A speculative tree is built by reparsing the block around the cursor

Status: accepted, 2026-10-20

## Context

- Completion ([#203](https://github.com/ide4cj/cjls/issues/203)) reads the syntax around the cursor from a file that is mid-edit: `x.` with nothing after, `let y = ` before a newline, `foo(` before the next statement. cjc's grammar takes a `.` on to the next line (`DOT NL* Identifier`), and `cjsyntax` follows it, so `x.⏎ foo()` is the call `x.foo()` and the statement after is gone from the tree. R1 inserts a name at the cursor (`raCompletionMarker`, `ide-completion/src/context.rs`) and classifies the position in that *speculative* tree, which the parser makes the shape the user means, and takes ranges, types and names from the real one. R4 does without: it walks the token stream back from the cursor and reads types from its last complete analysis (`DotCompleterByParse.cpp`). IntelliJ's `DUMMY_IDENTIFIER` is R1's model.
- A full parse of a file is the floor of every keystroke (D84: ~25 ms for `infer.cj`, 90 KB, the 99th percentile of this repository's sources; `nodes.cj`, 170 KB, twice that). A speculative tree made by a second full parse costs that again on every completion request, which follows its own `didChange`. R1 pays none of it: `SourceFile::reparse` replaces the token the edit is in, or parses again the nearest `{}` block around it (`syntax/src/parsing/reparsing.rs`), and falls back to a full parse; its callers are the completion marker, on-type formatting and join lines. Its `didChange` path parses the whole file, as `loupe.syntax.parse` does.

## Decision

- **The speculative tree is the real tree with the block around the cursor parsed again**, a marker inserted at the cursor: `cjsyntax.reparse(before, delete, insert)`, on `ginkgo.parsing.Reparser`, which is grammar-agnostic and takes the language's lexer, input, trivia rules, the open and close kinds and the grammar for a block of a kind. The nearest `Block` around the edit has its text, the edit applied, lexed and parsed with `block`; the new node takes the old one's place (`SyntaxNode.replaceWith`), everything else shared; errors outside the old block are kept, those after it shifted, the block's replaced by the new parse's.
- **It answers only when the result equals a full parse**: the edited text must still be one balanced block, `{` first and its `}` last, the grammar must consume it whole, and what it built must be a node of the block's kind. Else the next block up is tried, then the whole file is parsed. So the reparse never differs from `parse`, and a caller needs no second code path: `ReparseTest` holds a marker at six places in every source of this repository to a full parse of the edited text.
- **Only a `Block` is reparsed on its own.** A `DeclBody`'s grammar depends on the declaration around it (`declBody(p, scope)`), an `EnumBody`'s on nothing but is rarely where a cursor completes; a cursor at a class body's level, or at the top level, parses the file in full. A block kind must get no attached trivia (`TriviaRules.attachedTrivia`): parsed on its own, it has none before it.
- **No reparse of a single token** (R1's `reparse_token`): the marker is inserted next to a `.` or a name, where the block covers it, and an edit elsewhere is the full parse `didChange` makes anyway.
- **The speculative tree is no input of the database**: a plain function over the `Parse` of `loupe.syntax.parse`, built in the request, kept for its length (A13). The file's own parse, lowering and inference are the real tree's; what reads the speculative tree maps offsets back by the marker's length, as R1's `find_node_in_file_compensated` does.

## Consequences

- A completion request costs the parse of one body on top of the file's own, measured in `LexParseBench` (`reparseABlockWithAMarker` against `parseAFileWithAMarker`).
- `Reparser` can serve `didChange` later, if a keystroke's floor (D84) needs it: `loupe.syntax.parse` would take the edit and the previous parse, which calca's inputs do not pass today.
- A grammar change that makes a `Block` parse differently on its own than in its file fails `ReparseTest` on this repository's sources: the test is the contract.
