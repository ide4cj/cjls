# ADR-0060: The formatter is our own, on the syntax tree, and changes only the whitespace around the author's line breaks

Status: accepted, 2026-10-08

## Context

- #171 measured `cjfmt` (1.3.0-alpha.20261002, default configuration) on this repository: 185 of the files under `modules/` changed, and what it changes is no style to adopt (#172's comment): a macro's `[...]` and `(...)` reprinted token by token, losing their indentation and spaces; hand line breaks joined, then the line refilled to 120 and broken wherever it overflows, before the `.` of a member access included; a trailing space at a break in a type or an import. Its configuration has seven keys and no `off`. It reads no stdin and exits 0 on a syntax error.
- rust-analyzer (R1) runs `rustfmt`; the formatters on a lossless tree of its family (Biome's, Ruff's) lower the tree to a document of groups and soft breaks printed to a width (Wadler/Prettier). gofmt keeps the author's line breaks and decides only the whitespace around them.
- The tree is lossless (`ginkgo`): every comment and line break is a token, so a formatter on it changes nothing it does not mean to.

## Decision

- **A module of its own, `cjformat`**, on `cjsyntax`, knowing no LSP (D3, D5): `format(parse)` gives the edits, `formatText(text)` the text. The server answers `textDocument/formatting` through `loupe.formatting`, on the tree the database holds; `cjls fmt [--check] <path>...` formats files as the server reads a directory (`readRoots`).
- **gofmt's way, not a printer to a width**: only the whitespace where a line starts or ends changes; the line breaks are the author's, blank lines kept to one, trailing whitespace dropped, one line break at the end. A printer to a width was the other way: the style a line width forces is what made `cjfmt`'s output unusable here, and it is a project of its own (comments attached to nodes, every node kind laid out). Spaces inside a line are left as written.
- **The indent of a line** is that of the brackets open at its start: one level for all those opened on one line; a declaration's or a statement's `{}`, and what follows a `case`'s `=>`, from the line where it starts (`func f(a: A,` / `b: B) {` has its body one level in); a line carrying an element on (an operand, a `.` of a chain) one level more, unless the element started on its bracket's line (`if (a &&` / `b)`). Where this repository did both, the more common was taken: a lambda's statements at its parameters' level when those are on a line of their own (39 to 20), and at a bare `=>`'s (30 to 5).
- **What a macro reads as tokens keeps its layout**, moved as a whole with the line it starts on: `quote(...)`, a macro call's `(...)` and `[...]` (an `@TestCase` list), and a string's interpolations. A block comment's lines move with its first. What moves as a whole moves no further left than its least indented line can go, and keeps the alignment of its lines.
- **A file with syntax errors is not formatted** (`None`, `null` to the client, an error from `cjls fmt`): what it would make of them is a guess.
- **The client's `FormattingOptions` are ignored**: four spaces, as `cjls fmt` does, so a project formats alike in every editor.

## Consequences

- Two properties are tested over this repository and any corpus `CJFORMAT_CORPUS` names (`CorpusTest`): formatting changes only whitespace (comments but their whitespace), and formatting what it made changes nothing. Over the grammar corpus (ide4cj/tree-sitter-cangjie-testing, 6 029 files, those that parse formatted) they held too.
- On this repository (a902731), 22 files change, every one a normalization: the minority lambda styles, double blank lines, operands carried on inside brackets. What the generators write through `cjfmt` (`cjls.lsp_types`, `cjsyntax`'s views, `cjo`'s) is left as it is. The whole repository is checked in 1.6 s.
- A long line stays long: no width is enforced, and nothing is joined.
- `rangeFormatting` and `onTypeFormatting` are not served; a range would format the lines it covers with the indent computed from the file's start.
