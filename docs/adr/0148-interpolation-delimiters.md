# ADR-0148: Highlight interpolation delimiters over editor grammars

Status: accepted, 2026-10-23
Amends ADR-0105: string interpolation delimiters are sent even when semantic tokens augment a grammar

## Context

In #499, `${}` looks like string text and has no diagnostic. cjc
1.3.0-alpha.20261014001050 rejects interpolation containing only trivia or
semicolons. The parser accepts an empty statement list. Separately, highlighting
omits `${` and `}`; TextMate scopes them as interpolation punctuation and the
tree-sitter queries use `@punctuation.special`. Those scopes need not distinguish
them from a string in an editor theme. Sending ordinary operator tokens alone
would still lose them to D105's augmentation filter.

## Decision

Classify `${` and its matching `}` as `InterpolationDelimiter` in loupe, and map
that tag to LSP's standard `operator`. Retain it when augmenting a base grammar.
Ordinary operators keep D105's filtering. Use no new legend type or modifier;
clients and themes can use their existing operator styling.

Only the delimiters get this tag. The expression keeps its normal code tags and
string contents keep theirs, with no overlapping ranges. Raw and escaped `${}`
remain string text. A whole-block color would hide the expression's semantic
classification. Changing three client grammars would leave server-only clients
without the distinction and require coordinating theme scopes.

## Consequences

The server supplies an explicit token for each interpolation boundary in full
and range requests, regardless of base-grammar support. Exact colors remain the
theme's choice. Empty interpolation is diagnosed by parsing; malformed strings
retain the lexer's recovery and missing interpolation closers get a parser error.
