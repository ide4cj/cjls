# ADR-0097: The unused warnings are off in every module

Status: accepted, 2026-10-20

## Context

- The rule was "a build warns about nothing", `-Woff unused` only on the generated `cjls.lsp_types` and on the tests (`[profile.test.build]`, std.unittest's `@AssertThrows[E]`). std's `@Derive` on an enum whose constructors take parameters was the accepted exception: an unused `check_<Constructor>_<n>` per parameter, 176 warnings in a clean build, among which a real one does not show.
- Two days of merges brought 10 unused names in a clean build, unseen in CI, whose `target` is master's cache (D28): a package not compiled again prints nothing. Half were not dead code: the parameter of a default body, a function only `@When[os == "Windows"]` code calls, which on the other platforms only a visibility it does not need silences.

## Decision

- **`-Woff unused` is in every module's `compile-option`**, and the root's: not only the root's, since `cjpm build -m` reads the module's manifest alone (as `-O2`, D51). The silencing on `cjls.lsp_types` and in `[profile.test.build]` goes, the module's option covering both.
- Every other warning stays on.

## Consequences

- A dead import, variable or private function is left to review.
- A new module starts with the option in its manifest, or warns.
