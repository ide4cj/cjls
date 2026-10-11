# ADR-0083: A member named through a type or alone is filtered by the type the names give, in the lookup

Status: proposed
Amends ADR-0052 and ADR-0053: their Consequences leave the filters to inference (step 8)

## Context

- D52 resolves a name after a type, `this` or `super`, and D50 a name alone in a type's body, by names, through `memberLookup`; D53 leaves two gaps to inference (#239): an override or implementation is found with what it overrides or implements (`C.e()`, `m()`, `Int64.parse` four), and an `extend` of another instance of the type is found too (`Box<S>.only()` finds `extend Box<Int64>`'s).
- Step 8b (#168) filters a member of a value in inference (`valueMembers`: N86, N107), and records what it keeps for go to definition.
- cjc 1.3.0-alpha.20260918: `C.e()`, `this.m()`, `m()` and `k(1)` in `class D <: J<Int64>` call the implementation or the override; `only()` in `extend Box<S>`, in `class Box<T>` itself, and `this.only()` there are "undeclared identifier" or "not a member"; `Box.only()` compiles (cjc infers `Box<Int64>`); and with a `func only()` in the package, `only()` in `extend Box<S>` calls the package's (N86).

## Decision

- **`memberLookup(on:)` takes the type the members are looked up on**, and drops the `extend`s of another instance of it (N86) and the functions a nearer one with the same parameters, seen on it, hides (N107). `membersNamed` passes the type around the body, its type parameters its arguments, or the type its `extend` extends; `resolveField` the type the receiver names: `this`'s, `super`'s as an instance, a type of the language, a type or alias with the type arguments written, lowered, else unknown ones, which match any `extend`. A type parameter's bounds are not filtered.
- **In the lookup, not in inference** (B: inference filters `TypeMembers` and the members of a name alone, and records what it keeps, as for a value). A name alone is resolved below inference (`resolveBodyName`, D50): a member level with only another instance's `extend`s must be empty for the lookup to go on to the package's functions, as cjc does; with B it stops at them. Go to definition, hover and the scope's diagnostics read the lookup, so each has one answer without asking inference.
- The types are only those names give: no type of a value is read (D52 holds).

## Consequences

- `C.e()`, `this.e()`, `super.f()`, `m()` go to the implementation or override alone; `Int64.parse` under `import std.convert.*` to the two `extend`s' `parse`.
- The type is found only when a filter needs it (`LookupTy`): an `extend` of a generic type met, or functions found on two levels, whose parameters are then compared; the others pay nothing (`BodyResolutionBench`, `FieldResolutionBench`).
- Inference's own filters of a value's members (`valueMembers`) and operators stay; `memberLookup(on:)` can replace them.
