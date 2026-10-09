# ADR-0064: An operator of a type is a call of its member, the language's own tried first, as cjc

Status: accepted, 2026-10-08

## Context

- D55 typed an operator only between types of the language and an index only of a tuple; `a[i]` of an `Array`, `"a" + "b"`, `v == w` of a struct had an error type (#48 step 8e). Of 163 489 expressions of this repository at 1299c8d, 1 576 of 1 696 indices and 1 667 of 6 110 binary operators (`??`, `|>`, `~>` aside, 8f's) had none.
- cjc (R3) checks an operator first as the language's (`CheckBinaryExprCaseBuiltIn`, `SynBuiltinUnaryExpr`, a tuple's or a `VArray`'s index) with its diagnostics suppressed; failing that, an overloadable one is desugared in the check (`DesugarOperatorOverloadExpr`) into a call of the left's member named by the operator — `a.+(b)`, `a.-()`, `a.[](i)` — and checked as a call, the type expected its return type's, then put back (`RecoverToBinaryExpr`) if it fails. `a[i] = v` is `a.[](i, value: v)`; `x op= v` is `x = x.op(v)`, undone for the language's; `a[i] op= v` is `a.[](i, value: a.[](i) op v)`.
- R1 keeps an operator in its HIR and looks up the method of the trait of the operator (`Add::add`, `Index::index`) from the left's type, the primitives built in, and records it as the expression's method resolution, which goes to definition from `+`.
- cjc 1.3.0-alpha.20261002 (N122–N126, in #48 step 8e's PR): `a[0]` of `Array<Int64>` an `Int64`, `a[0..2]` an `Array<Int64>`, `s[0]` of a `String` a `UInt8`; `v + 1` of `+(V)`, `+(Int8): String` a `String`; `let a: Int64 = v * 1` takes `*(Int32): Int64` over `*(Int64): V`; `v != v` of a type declaring only `==` is an error; `3 * v` with an `extend Int8 { operator func *(o: V) }` is an error, its literal an `Int64`; `true & false` and `r'a' + r'b'` are errors, `() == ()` a `Bool`.

## Decision

- **A call of the left's member, as cjc** (option A of step 8e): HIR keeps the operator (a desugaring at the lowering, option B, knows no types to tell the language's from a declared one); inference looks up the members named `+`, `[]`, `-` of the left's type — its own, its `extend`s', its supertypes', a type parameter's bounds', as any member of a value — of as many parameters as operands, and chooses among them as among a call's candidates (D63), the right an argument, the type expected the return type's. The one taken is recorded as what the operator expression calls (`calleeOf`), and `definitionAt` goes to it from the operator or the bracket.
- **The language's tried first**: between numbers an arithmetic of the left's type, between types of the language a comparison, between tuples `==` and `!=`; tried and undone as a candidate is (A27), kept if its operands fit it whatever fails deeper in them (a check D57 misses there is no reason for a type's operator). Else the left is synthesized alone: a number on the left of a type's operator is an `Int64`.
- **`a[i] = v`** takes a `[]` whose last parameter is passed by name; which parameters are is now in the signature (`SignatureTypes.paramNames`, of a source or a `.cjo`'s `isNamedParam`). **`x op= v`** checks what the operator returns against `x`.
- The operators of a type are looked up once in a body, by the type and the name.

## Consequences

- On this repository's source at 1299c8d, inferred by both builds (this change's test binary run over master's source): of 163 489 expressions, those of an error type 20 768 → 14 915, those whose type holds one 1 423 → 1 253; 5 858 get a type (indices 1 421, names 1 284, members 982, `==` 656), 446 change from one type to another (246 literals, of the type of a byte indexed now: `UInt8`), 5 lose one: `tokens += if (c) { quote(…) } else { quote(…) }`, of `Tokens`'s several `+`, which an argument of no type (a `quote`) tells none apart, where the `if` was checked against `Tokens` before. Indices of no type 1 576 → 155; binary operators but `??`, `|>`, `~>` 1 667 → 370.
- A cold pass over every body, master's test binary then this change's in turns over master's source on this workstation (load 2.4–3.7): 13.86, 13.64, 13.37 s before, 14.49, 14.56, 14.46 s after, 6% more; 29% before a type's operators were looked up once per body and built once per candidate.
- An operator of one candidate is of its return type whatever its operand (`3 * v` an `Int64`'s `*(Duration)`: a `Duration`), as a call of one is (D55).
- Not yet: `a[i] op= v` checks no `[]` taking a value (only the one read and the operator); `a[i]++` and `x++` stay `Unit`, unchecked; the mismatches are not reported (8c′); `??`, `?.`, `|>` and `~>` are 8f's.
