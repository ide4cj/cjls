# ADR-0088: What inference finds wrong is reported by expression, only between types known wholly, held to zero on this repository and to a shrinking list on std's sources

Status: proposed

## Context

- Inference found mismatches only to compare candidates (D63); `loupe.diagnostics`, which the server publishes (pull and push, S8), gave the parser's errors alone, and `scopeDiagnostics` (D47) went nowhere. D77 split the type not known into an error and a gap, so that a mismatch between known types can be told from one the analysis cannot judge (#48's step 8c′, #53).
- Prior art (`docs/prior-art.md` § Semantic diagnostics): R1 keeps `type_mismatches` by `ExprOrPatId` and `InferenceDiagnostic::MismatchedArgCount { call_expr, … }` in `InferenceResult`, ranges found later through the source map, and skips a mismatch holding an unknown type; cjc tries a call's candidates under a `DiagSuppressor` and checks the one taken again with its diagnostics on.
- cjc 1.3.0-alpha.20261002 (N140–N153, in the PR): `mismatched types` on the expression, `expected 'X', found 'Y'`; `cannot convert an integer literal to type 'X'`; `missing argument for parameter list '(…)' in call` / `extra argument given …`, `expected n arguments, found m`, from the `(` to the end of the call, a trailing lambda one of them; a variadic `Array` parameter takes its elements, none, or the array; an import's error from the path's start to its last name, `conflicted` and `shadowed` warnings at that name.
- A first run over this repository with every mismatch between known types reported gave 530 diagnostics, none an error of the code: each was a gap of inference that counting had hidden.

## Decision

- **By expression, in `InferenceResult`** (`diagnostics: Array<InferenceDiagnostic>`, `TypeMismatch(ExprId, expected, found)`, `ArgCount(call, params, given)`), as R1: `inferBody` stays free of positions (A2), an edit above a body leaves it equal, and `loupe.diagnostics` finds the range through `bodyWithSourceMap`. A candidate tried writes them to the journal it undoes (A27): what is reported is what the call taken finds, checked again as cjc does.
- **Only what is certain**: both types known wholly (no `ErrorTy`, `TodoTy` or variable inside, D77), the expression written by the user (none a desugaring made, A29, R3's `ShouldDiagnose`), and none where the analysis does not match the arguments as cjc yet: a variadic call, an `inout` argument, a call of what a call returns (N131), a function or the constructors of a type a macro whose expansion is not read may change (#176). Those are still counted, so a candidate still fails; only the report is quiet. Names and members not found wait for #175 and #176.
- **The gate is a test of `cjpm test`, run always**: no diagnostic on this repository, and on std's sources (`.corpora/`, D65; `std.core` from its `.cjo`, #218) none but the lines of `modules/project_model/std_diagnostics_known.txt`, each with the issue of its gap. A line found that is not listed fails it, and so does one listed not found: the list only shrinks. Its heap (2 GB, as the server's, D31) is the root manifest's `[profile.test.env]`, so a `cjpm test` of no variable runs it, in CI and in `pre-push` alike.
- **The gaps the gate found are closed here, not quieted**, where cjc's rule was clear (N140–N151): `this` where `This` is expected, a `foreign` or `@C` function and a lambda as a `CFunc`, `Any` above every type, an interface implemented as several instances, `?T` joined with `T` (#249), a one-character string as a `Rune` or `Byte`, a shift's or power's number of the type expected, an array literal against an interface of `Array`, an `extend` of an alias (#277, of a source), a call's arguments matched to an overload by names and default values (#240, #254 but variadic), a tuple boxed into an `Option`.
- **`scopeDiagnostics` is published** with the rest, its warnings as `Severity.Warning`.

## Consequences

- A user sees a mismatch and a wrong count of arguments in the editor; a false one on code cjc accepts is a failed test of this repository or of std, before it reaches anyone.
- What is left on std's sources is 24 lines: `@When`'s twins (#149), `flatbuffers`, which the corpus lacks, and four groups of #287.
- A cold pass over every body (the gate) takes 11–12 s here; `cjpm test` runs two, this repository's and std's.
