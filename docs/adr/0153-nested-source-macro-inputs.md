# ADR-0153: Source macro inputs compose nested calls inside out, including token DSLs

Status: proposed
Amends ADR-0117: nested calls are found even when their enclosing input is not an expression (#371, #443)

## Context

D117 specifies inside-out expansion but initially defers every body call holding
another call forever. Item inputs also copy body calls without their outputs.
The argument parser rewinds invalid expression lists to balanced tokens, losing
calls in DSL inputs such as `@M(a.@N(b))` and `@M(@N(x) <- 1)`.

A probe on cjc 1.3.0-alpha.20261014001050 confirms that `N` runs before `M`
in both DSL inputs and in `@M(@N(1))`; `N` sees `M` as a parent, and `M`
receives `N`'s output and child message. A call in a member initializer runs
before the macro on its type, whose input contains the result. Generated calls
are expanded by cjc in a later step; D98's source-only keys still exclude them.

## Decision

- Keep nested expression calls as syntax nodes in the balanced-token fallback
  for parenthesized macro inputs. Preserve escapes and delimiters; unsuccessful
  speculative nested parses rewind to tokens. This reuses source pointers,
  stable call ordinals and the existing body walker instead of inventing a
  second token scanner with a separate identity and navigation model.
- Compose body slices with the same mapped-output contract as item chains.
  Wait until every nested served call has an output, substitute only outermost
  overlapping calls, and forward descendants' messages before their parent's.
  Unresolved calls remain source text. D98's retained successful outputs keep
  their existing role in composition after a failed rerun.
- Walk each served call's item once and memoize composed requests within one
  composer. Ancestors reuse their descendants' requests instead of recursively
  reconstructing them for every level. No syntax is retained in tracked results.

## Consequences

Expression and item inputs share substitution, source mapping and child-message
ordering. Syntax consumers can see calls inside otherwise opaque DSL tokens;
the ungrammar and generated views describe those nodes. Expansion output remains
outside source-call discovery, preserving D98 and D144's recursion limit.
