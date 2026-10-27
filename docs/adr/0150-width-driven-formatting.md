# ADR-0150: The formatter decides line breaks from syntax and a fixed width

Status: accepted, 2026-10-23

## Context

- #256 replaces D60's preservation of author line breaks: equivalent argument lists and expressions should have the same layout. D76 joined body braces but did not settle the layout of long expressions. D74's filtering edits by original lines cannot survive moving line breaks.
- A formatter must preserve Cangjie's newline-sensitive syntax, comments, strings and macro token trees. Reusing the SDK formatter would retain its different style and require a subprocess in generators.

## Decision

- **Supersede D60, D74 and D76 with syntax-driven printing at 100 Unicode scalar columns, four spaces per indent, no configuration.** Short groups flatten; long lists break between elements, chains before dots, binary expressions after operators. A leading dot makes each continuation recognizable as part of the receiver's chain; the whole chain shares one continuation indent. Indivisible names, strings, comments and macro token trees may exceed the width. Preserve commas rather than inserting or removing tokens.
- **Use an immutable document IR with cached flat widths.** Groups, indentation, soft/hard lines, conditional layout and line suffixes separate syntax from printing. Each group tests a cached width; the printer uses an explicit stack. No repeated scanning of suffixes to decide fit.
- **Nonempty declaration and control-flow bodies use lines.** Single-expression lambdas flatten when they fit; multiple statements stay on separate lines. Blank lines between statements/comments are capped at one. Preserve LF/CRLF, remove trailing whitespace outside protected text, and terminate a nonempty file with one newline.
- **Attach comments by source position, independently of parser trivia ownership.** Preserve token order, keep a same-line comment trailing, and print dangling comments inside their delimiters. Move multiline comments and macro whitespace together, bounded at the margin. Strings, including interpolation layout, remain verbatim. No `fmt: off`: macro test tables are already protected; ordinary constant tables use the list layout.
- **Refuse files with syntax errors.** For a range, select the smallest complete statement/declaration containing its non-whitespace bytes, or the enclosing body for several siblings, using structural indentation. The edit may extend beyond the selection. A selection inside a protected macro formats its containing statement.
- **All three generators link `cjformat` and format in memory.** They reject invalid output and run without an SDK environment. `syntax_codegen` bootstraps from checked-in `cjsyntax`: build before changing generated kinds; repair unbuildable output from git or by hand before rebuilding. No executable formatter subprocess.

## Consequences

- The CLI, LSP and generated files share one style. A separate repository-formatting PR supplies #171's single migration, with its formatting commit recorded in `.git-blame-ignore-revs`.
- Unit tests specify layouts. Corpus checks require identical significant tokens and syntax structure, successful reparsing and idempotence; benchmarks cover large files and nested document groups. These checks are stronger than D60's whitespace-only comparison.
- Quiet measurements of large-file and nested-group scaling are tracked in #507; benchmark compilation alone is not measured performance evidence.
- Range formatting deliberately has a wider scope than D74; an editor must apply the returned ranges. Existing protected macro layouts can still differ, and long indivisible text is not a width violation that the formatter can repair.
