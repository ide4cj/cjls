# ADR-0051: `-O2` is a release option, and the coverage builds with `-g`

Status: accepted, 2026-10-06

## Context

- `-O2` was in every module's `compile-option`. `cjpm test --coverage` (D49) passes it to cjc, which warns `'--coverage' should be used without optimizations.` 60 times a run, against "a build warns about nothing". The percent is not what is wrong: the workspace with `-O0` covered 12419/13625 lines, with `-O2` 12418 (one line, calca's double-checked lock, which a race decides).
- cjpm puts a module's options on the cjc line in this order: `[profile.customized-option]`, `compile-option`, `[target.<triple>.release]` (no `-g`) or `.debug` (`-g`), `override-compile-option`; cjc keeps the last `-O`. A customized option (`cjpm test --coverage --cov`, `cov = "-O0"`) comes before `compile-option`, so it cannot take `-O2` away, and there is no profile of its own for `--coverage`.
- `override-compile-option` comes last but is on every build, and rewriting the manifests in the workflow leaves CI building something no manifest says.

## Decision

- **`-O2` is in each module's `[target.<triple>.release]`**, for the three triples the root names stdx for, and in no `compile-option`. A build without `-g` (`cjpm build`, `cjpm test`, `cjpm bench`, the releases) is `-O2` as before.
- **The coverage runs `cjpm test --coverage -g`**: the debug sections are empty, so it compiles unoptimized, with no warning.

## Consequences

- Each manifest holds three identical sections; a new triple is a section in every module, and a build for a triple without one is `-O0`, silently.
- A `-g` build is unoptimized everywhere, not only under coverage.
