# ADR-0143: Expand implied generic bounds in a separate bounded query

Status: proposed

## Context

#437: `T <: R<T>` implies `T <: Comparable<T>` when `R<X>` requires
`X <: Comparable<X>`. Member lookup, subtyping and call inference need the same
consequences. A24 keeps signature lowering independent of other non-alias
signatures, including mutually referring declarations.

R1 [rust-analyzer's trait environment](https://github.com/rust-lang/rust-analyzer/blob/394e7597ad8f8f022a98a143d7ec4f10896f7205/crates/hir-ty/src/lower.rs#L2746)
is a separate cached query elaborating generic predicates. R3's
`src/Sema/Assumption.cpp` records instantiated subtype relations, substitutes
arguments and expands constraints only on generic subjects. Reviewed upstream
`0829572a` through cjdev; behavior probes use the repository's pinned SDK.
R7 [Kotlin FIR](https://github.com/JetBrains/kotlin/blob/master/compiler/fir/resolve/src/org/jetbrains/kotlin/fir/resolve/transformers/FirTypeResolveTransformer.kt)
checks parameter-bound cycles separately. R9's
[extend assumptions](https://github.com/lin-qingying/cangjie/blob/main/cfir/resolve/src/org/cangnova/cangjie/cfir/resolve/transformers/CfirTypeResolveTransformer.kt#L726)
collect declaration constraints before substitution; its declaration-visit guard
belongs to that algorithm, not to traversal of instantiated relations.

## Decision

- Compute implied bounds in `genericBounds`, a calca query separate from
  `signatureTypes`. Expanding during signature lowering would break A24;
  independently expanding at each consumer would duplicate policy and work.
- Deduplicate the pair of instantiated subject and upper bound. Revisiting the
  same interface with different arguments can add facts: `R<A, B>` requiring
  `B <: R<B, A> & Comparable<B>` bounds both parameters after two steps.
- Expand only constraints on type parameters, as R3 does. Requirements on a
  concrete type are not assumptions about that type.
- Bound each query to 256 distinct relations. This is an implementation resource
  budget, not a language restriction. On overflow, discard partial results and
  give its parameters `UnknownTy(GenericBoundsLimit)` bounds, following A30.
- Amend D77: reserve `TodoTy` for unsupported analysis features. Use `UnknownTy`
  for missing or unreadable inputs, unfinished inference or exhausted resources;
  move `NoStd`, `BinaryType` and `NotInferred` from `Todo` to `UnknownReason`.
  An unreadable binary type alone is not evidence of an error in user source.
  Both analysis uncertainty categories propagate ahead of `ErrorTy` and suppress
  diagnostics.

## Consequences

All consumers share the closure and its incremental dependencies. Finite cycles
can reach a fixed point; growing constraints terminate conservatively. A finite
closure exceeding the budget is also unknown. Overflow suppresses diagnostics
and propagates unknown results through operators, members and generic calls;
partial member sets cannot select an apparently unique overload. Changing the
budget changes analysis completeness, not which programs the language accepts.
