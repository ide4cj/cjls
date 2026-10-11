# ADR-0076: A body's `{` on a line of its own joins the line before

Status: proposed
Amends ADR-0060: the line breaks are the author's

## Context

- D60 keeps every line break, and indents a line that does not start an element as one carrying the element on, one level in. A body's `{` moved to a line of its own (`if (a)` / `{`) was kept there one level in, its `}` at the statement's level: a stair no style writes, which formatting never undid.
- Cangjie's coding standard, which cjfmt implements, asks for K&R braces on every non-empty block, and cjfmt has no option for it: it joins such a `{` to the line before (checked with cjfmt 1.3.0-alpha.05).
- rustfmt, ktfmt and swift-format put the `{` of a body on the line its declaration or statement ends on; gofmt needs no rule, since Go's grammar refuses the break. This repository writes it so.

## Decision

- **A body's `{` (D60's: a `Block`'s, a declaration's, an enum's, a property's, a `match`'s, a `foreign` block's) starting a line joins the line before, after one space**, the blank lines between going too. The one line break the formatter takes away.
- **After a line comment it stays** on its own line, at the level of the element it belongs to, as its `}`: joining would put it in the comment.
- A lambda's `{` keeps its line: a lambda is a value, which an author breaks before on purpose.
- A range (D74) keeps the join whole, when it touches the line before or the brace's.

## Consequences

- Allman style is not kept: a body opens at the end of its declaration's or statement's line.
- Formatting still changes only whitespace, and what it made it leaves alone (`CorpusTest`); `cjls fmt --check` over this repository names the same files as before.
