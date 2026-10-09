# ADR-0066: Coalescing, pipelines and compositions are typed as what cjc desugars them to, std.core named through lang items

Status: proposed

## Context

- D64 left `??`, `|>` and `~>` of an error type (#48 step 8f); of 166 080 expressions of this repository at 4894060, all 491 `??` and 159 `|>` had none. `?.` is 8g's.
- cjc (R3) types `a ?? b` as a binary expression (`ChkCoalescingExpr`) and desugars it into a `match` only after the check; `x |> f` is desugared in the check into the call `f(x)` (`DesugarPipelineExpr`), `f ~> g` into a call of `std.core`'s `composition(f, g)` (`DesugarCompositionExpr`), a function not `public`, which a file cannot name. The declarations its desugarings need it finds in `std.core` by name, past the file's scope (`GetCoreDecl`, `IN_CORE`). R1 names them as lang items: an enum of them, a query from one to its definition, a path in its HIR that is one.
- cjc 1.3.0-alpha.20261002 (N127–N132, in #48 step 8f's PR):
  - `??`: the left is synthesized alone and must be an `Option<T>` ("coalescing is only valid for 'Option'"). The right is checked against `T`, or, given a type expected, against that type, of which `T` must be a subtype. There is no join: `d ?? b` of a `?Derived` and a `Base` is an error, `let x: Base = d ?? b` is not. It is right-associative.
  - `x |> f` is `f(x)`: `1 |> g` takes the overload `g(Int64)`, `1 |> h8` makes its literal an `Int8`, and `1 |> k` calls `k`'s `operator ()`.
  - `f ~> g` is `(T1) -> T3`. Its operands are synthesized alone first: `id ~> f` and `f ~> {x => x.size}` are errors, `f ~> g` of an overloaded `g` is not.
  - The type arguments of a callee that is itself a generic call are solved with the outer call's arguments: `first("x")([1, 2])` and `[1, 2] |> first("x")` are an `Int64`, `first("x")` alone a `ToString`, of its bound (N131).
  - A lambda checked against a return type holding a type argument not solved yet tells it by its body: `list.filterMap {d => d as T}` is an `ArrayList<T>` (N132).

## Decision

- **Typed as what cjc desugars them to, in inference, the HIR kept** (option A of step 8f, as D64).
  - `??` is checked as `ChkCoalescingExpr` checks it, not lowered into a `match`, whose branches would join.
  - `x |> f` is a call of `f` with the argument `x`, the overload it takes `f`'s callee.
  - `f ~> g` is a call of `composition` with `f` and `g`, an operand a lambda of a parameter not written an error.
- **The declarations the language means are lang items** (option A, as R1): `LangItem` names them, and `langItem(db, from, item)` finds each in `std.core`, its visibility aside.
  - It names `Option` (`?T`, `??`, `as`, boxing), `composition` (`~>`), `Object` (the superclass of a class of none), `String` (a string literal), `Future` (`spawn`), `Iterable` (`for-in`), `Range` (`a..b`) and `Array` (`[a, b]`). Nothing else looks up a declaration of `std.core` by name.
  - 8g adds `Some` and `None`, for `?.` lowered into `match`es in the HIR.
- **The compiler's own types are no lang items.** These are `CPointer`, `CString`, `RawArray`, `VArray` and `CFunc`: a file names them, through its scope, and the syntax means none of them.
  - cjc has no declaration of them in `std.core`'s source, only `extend`s; it adds a `BuiltInDecl` of each to the package when it compiles it (`AddBuiltInPointerDecl`), which its `.cjo` carries.
  - They are to be types of their own (option 2B of step 8f, as R1's `TyKind::Raw`), their `extend`s found by the type, not by a declaration: `std.core` developed from its source has no `.cjo` and so no `BuiltInDecl`, and loupe must analyze it. That is a step of its own (#218); until then they are the `.cjo`'s `BuiltInDecl`s.
- A value of a type that has an `operator func ()` is called through it (`k(1)`, `1 |> k`).
- A lambda checked against a return type holding an unsolved type argument is checked against it as far as it is known, and returns what its body gives (N132).

## Consequences

- On this repository's source at 4894060, this change's test binary and master's run over it:
  - Of 166 080 expressions, those of an error type went 15 203 → 12 636, and those whose type holds one 1 279 → 849. 2 567 get a type, none loses one.
  - `??` without a type went 491 → 56: 51 have a left of no type (calls 33, members 11), and 5 an `Option` of one. `|>` without a type went 159 → 0.
  - Of the types changed, six literals take the type of what they are compared with, typed now (`x >= 0` of an `Int32`), and a lambda of a `flatMap` returns an `Option<Type>` where it returned an `Option<ToString>`.
  - Two are cjc's no more:
    - `….map {kv => "…"} |> collectString(…)` returns an `Iterator<ToString>` where it returned an `Iterator<String>`: the right is solved alone, of its bound (A26 against N131).
    - `….concat([packageImports(…)])`'s array is checked against the `Array<{unknown}>` `concat` now takes.
- A cold pass over every body, on this workstation (load 5), master's binary then this change's in turns: 13.72, 15.33, 13.71 s before, 14.13, 14.54, 14.22 s after, about 3% more for 1.5% more expressions typed. `InferenceBench` (the memos read; load 11–15) 19.91 and 20.96 ms before, 19.61 and 20.16 ms after: unchanged within noise.
- Not yet: the type arguments of a callee that is a generic call are solved alone (N131); an operand of `~>` is not called through its `operator ()`; a lambda of a parameter not written whose body alone tells it (`{x => x + 1}(1)`, an `Int64` to cjc) is an error; the mismatches are not reported (8c′).
