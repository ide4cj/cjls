# ADR-0041: A generated accessor finds a child by the tokens between it and the children that could be taken for it

Status: accepted, 2026-10-04. Supersedes D10's accessor finding a child by its position (#139).

## Context

D10's accessor took a child by its position among the children that could be taken for it, as fixed when those before it are mandatory and, with some after it, when it is mandatory itself. That holds of a tree without errors only: while `if () {} else if (b) {}` is typed, `IfExpr.condition()` was the `else if`, and `then()` of `if (a) else { x }` the `else` block — what outline, highlighting and name resolution read. The parser could leave a node for every missing mandatory child, which changes the trees, `cangjie.ungram` and every consumer; rust-analyzer writes such accessors by hand (`IfExpr`'s), as `node_ext.cj` already did here for `RangeExpr`, `FuncType`, `MatchCase` and `SpawnExpr`, by the tokens around them.

## Decision

- **The generator finds those tokens itself.** A child with rivals before it is after the first token in between that a tree has whenever it has the child (`else` for `elseBlock`); one with rivals after it is before the next token in between that the tree has whenever it has those rivals, or whenever it has the tokens it starts after (`)` after `(` in `spawn (context)`). A token is one only where nothing else in the rule may be of its kind; never under a repetition. `ginkgo`'s `astChildBetween`/`astChildrenBetween` take them.
- **Position is kept for the child a rule starts with**: the parser makes the node around it once parsed (`TrailingLambdaExpr.callee`, `CompletedMarker.precede`), so it is always there, and the one rival after it is the next.
- **Anything else is written by hand** in `node_ext.cj`, the generator naming it: `SpawnExpr.lambda`, whose `)` is optional.

## Consequences

- A child missing from a tree with errors is `None`, not its rival, wherever the grammar has a token between them; `RangeExpr`, `FuncType`, `MatchCase` and `SpawnExpr.context` are generated.
- A token a child is found after takes the child with it when it is missing, as with the accessors written by hand before; one it is found before only bounds it, so the child is still found without it.
- A rule that puts two children of one kind side by side with no token between them, other than first, is written by hand.
