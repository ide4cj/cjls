# ADR-0114: A std @Derive in a workspace macro's input is the declaration and cjls's own extends after it, and every call nested in the input is a child

Status: proposed
Amends ADR-0098: a call of std's macro nested in a workspace call's input stays as written; children deeper than one level not checked

## Context

- D98 sends a workspace macro the source with each nested call of a workspace macro replaced by its output. A call of std's macro stays as written until std's macros run in the macro server (#176's step 4).
- cjc expands `@Derive` before the calls around it. The outer macro is given the declaration with the `extend`s `@Derive` wrote after it, and `parseDecl` of that input returns the declaration (verified with cjc 1.3.0-alpha).
- So `@DeriveExt[ToJson] @Derive[Equatable] struct S {…}` sent as written makes `parseDecl` read a `MacroExpandDecl`. `@DeriveExt` then reports "only derives for a `struct`, a `class` or an `enum`" on every such type. A `@Serde` on the type, nested between the two, reads the same input and reports the type as an enum variant. In `stdxx`'s `deriving_ext_test.cj` that is 12 `@DeriveExt` calls, and 7 reports of `@Serde` on 6 types, none of them real. Its output then copies the unexpanded `@Derive`, which the analysis does not expand inside an expansion, so the type loses `Equatable`.
- The alternatives:
  - Running std's macros in the macro server (#176's step 4) gives cjc's own text, bodies included. That is the real fix, but it is a step of its own.
  - Leaving the head out without the `extend`s makes the outer macro's input parse. The `extend`s are then lost wherever the outer macro does not copy its input.
  - cjls's own expansion of `@Derive` (#175, signatures only) is the one the analysis already reads beside the item.
- D98 left open what `getChildMessages` gives an outer call deeper than one level. `stdxx`'s `@DeriveExt[ToJson, FromJson] @Serde[tag: "kind"] @Derive[Equatable] enum DerivedShape { | @Serde[rename: "circle", payload: ["radius"]] Circle(Int64) … }`, compiled by cjc, writes `{"kind":"rect","width":3,"height":4}` (`deriving_json_test.cj`). So `@DeriveExt` reads the variants' `@Serde` past the one on the enum. cjls gave it only that one, and it reported "a tagged enum needs `payload:`" on each such variant.

## Decision

- **In a workspace call's input, a std `@Derive` nested in it is expanded as cjc expands it.** Its head is left out, from its `@` to what follows it. Its `extend`s (`deriveExpansion`) go after what it is on, innermost `@Derive` first, each said to come from its head. Any other std macro stays as written.
- **A call's children are every workspace call nested in its input**, those nested in a nested call first, then that call (`MacroInputComposer.chainFrom`).
- **Once the outer call is answered, that `@Derive` is no longer expanded on its own** (`expandedCalls`). What it adds is read from the output of the call around it, which `macroCallAt` shows for it (`readCallOf`).

## Consequences

- An outer macro that copies its input copies `extend`s whose bodies are empty. The analysis lowers no body of an expansion (A34), so nothing reports them. A macro that reads the bodies of what it is given still sees none. Once #176's step 4 runs std's macros in the server, its output replaces cjls's here.
- A macro call on a primary constructor parameter (`@Serde[rename: …] let x`) is still sent as written: it is on no item, so it has no `MacroCallId` and is not asked of the server (#357).
