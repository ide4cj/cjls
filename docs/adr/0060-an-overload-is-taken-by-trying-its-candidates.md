# ADR-0060: An overload is taken by trying its candidates, as cjc

Status: accepted, 2026-10-08

## Context

- D55 and D57 infer a call of one candidate; a call of several of as many parameters as it has arguments (`f(1)` of `f(Int64)` and `f(String)`) had an error type, its arguments inferred alone (#48 step 8d). A check against a type expected could not fail: nothing told whether an argument fits a parameter.
- cjc (R3, `MatchFunctionForCall`) orders the candidates by scope level and tries each of the nearest level first: every argument checked against its parameter, the return type against the type expected, with its diagnostics suppressed and its constraints reset after (`DiagSuppressor`, `PData::Reset`); the first level where any fits decides. Of several that fit, `ResolveOverload` keeps the most specific (`CompareFuncCandidates`: parameters subtypes, `Int64` first among the integers and an integer before a float, a generic one if its type arguments are inferred from the other's parameters); several enum constructors, or none most specific, are "ambiguous match". The one taken is checked again (`ReInferCallArgs`).
- R1 has no overloading, but tries a method candidate in `probe`, a snapshot of its inference table rolled back after. Roslyn (R6) binds an argument once and decides by conversions from its type, a lambda bound again per candidate; K2 (R7, R9) resolves each candidate in a constraint system of its own.
- cjc 1.3.0-alpha.20260918 (N115–N121, in #48 step 8d's PR): the expected type chooses (`let a: String = h(1)` takes `h(Int32): String` over `h(Int64): Int64`); a local function before a member, a member before the package's, the package's before an imported one, whatever fits better (`println(1)` takes the package's `println(Int8)` over the prelude's `println(Int64)`); a type's members and its supertypes' one level (`B().m(1)` takes `A.m(Int64)` over `B.m(Int8)`); a block of a function returning `Unit` takes any value (`g({ => 1})` of `() -> Unit`), though `let u: Unit = 1` is an error.

## Decision

- **Tried, as cjc** (option A of step 8d): each candidate of the nearest level first, its arguments checked against its parameters and its return type against the type expected; it fits if no check failed. Roslyn's way (B: arguments synthesized once, a literal or a lambda of a shape of its own, applicability by subtyping) was the other: no undoing and linear, but where an argument's own overload is chosen by the parameter around it (`k(f(1))` of `f(Int32): String`) it takes another than cjc.
- **A check can fail**: `infer` counts a type not assignable to the one expected (a subtype, or boxed into an `Option`); a candidate fits if the count did not grow. A call whose type arguments are not solved, or an argument synthesized of a type its parameter solved does not take, fails one too. The count is only compared, never reported: the mismatches are 8c′'s.
- **Undone, as R1's `probe`** (A27): while a candidate is tried, every write of inference goes to a journal, undone after it, fitting or not; the one taken is inferred again. A copy of the body's arrays per candidate was the other way: what a candidate writes is a few expressions, the body thousands.
- **An argument of one type whatever is expected** (a local, a variable, a member of a value, a string, `this`) is inferred once before the candidates and only compared by each: its answer is the same, and a call of many candidates (`StringBuilder.append`) no longer infers it once per candidate.
- **The overload taken is recorded** by its callee (`InferenceResult.calleeOf`), and `definitionAt` goes to it; a type called goes to the type, not to the constructor taken.

## Consequences

- On this repository's source at fc32f54 and this change's, inferred by both builds: of 141 912 expressions before and 143 302 after, those of an error type 14 795 → 11 171, those holding one 1 366 → 1 135.
- A check against a type expected that fails in this repository, which cjc compiles, is a false one: 231 are left, 201 of them calls whose type arguments 8c does not solve (`map` of a lambda, `RawJson.of`), 16 a trailing lambda given to a parameter of another place (named parameters, D57's gap); the rest single cases (`Token` for `Tokens`, an `inout` argument). Inside a candidate tried, each of them would reject one cjc takes.
- On filaco.dev's Ryzen 7 8845HS, a cold pass over every body: TBD.
- Not yet: an imported function renamed or re-exported is not of the package's level as cjc has it (`isReExportedOrRenamed`); a named argument is still inferred alone, telling no candidate apart; an overloaded function passed as an argument to overloads is not combined with them (cjc's `GetArgsCombination`), only chosen by a function type expected (N121).
