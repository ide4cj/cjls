# ADR-0146: Prefer const for values known at compile time

Status: proposed

## Context

Review of #481 found `GENERIC_BOUNDS_LIMIT = 256` declared with `let`, like
several existing limits, masks and fixed strings. C23 preferred `let` over
`var` but did not distinguish immutable runtime bindings from compile-time
constants. C19 already specifies names for `const` declarations.

On Linux x86_64 with the pinned `1.3.0-alpha.20261014001050`, probes accept
numeric and string literals, raw and multiline strings, integer shifts, local
constants and `static const` members. The same compiler rejects `const XS =
[1, 2]` because `Array` is not a constant type, and rejects `const WAIT =
Duration.millisecond * 10` because that initializer is not a constant expression.

## Decision

- Prefer `const` over `let` when the initializer is a constant expression on the
  supported SDK and the declaration keeps its type, API and behavior. Apply this
  to package-level, static and named local constants. C23 states the current rule;
  C19 supplies their `UPPER_SNAKE_CASE` names.
- Use `let` for immutable values computed at runtime, including ordinary arrays,
  collections and calls without constant evaluation. Use `var` when reassignment
  is needed. Do not change a collection to `VArray`, add a constant-compatible
  constructor or change an API solely to replace `let` with `const`.
- Change generated declarations through their generator and verify a consumer.

Keeping `let` for every immutable binding would leave compile-time intent
unchecked. Restricting `const` to numeric limits would arbitrarily exclude fixed
strings and other supported constant expressions. Requiring `const` for every
immutable value would force unrelated type and API changes. The chosen rule
lets the compiler check constant evaluation where the existing representation
already supports it.

## Consequences

Review can distinguish fixed configuration from runtime initialization directly
at the declaration, and a later runtime dependency cannot silently enter a
`const` initializer. This is a code convention, not a performance claim.

The initial cleanup covers eligible package-level and static literals and the
FlatBuffers generator. Other existing code adopts the rule when touched; this
decision does not claim a completed audit of every local binding. Compiler
acceptance is checked with builds and existing tests; no new lint enforcement
is introduced.
