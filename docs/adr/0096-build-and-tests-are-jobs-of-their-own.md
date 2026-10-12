# ADR-0096: CI builds the binary and runs the tests in two jobs side by side, each with the cache of its own target directory

Status: proposed
Amends ADR-0027: what CI caches, and in which job

## Context

- D27's cache works as it was meant to: an unchanged commit compiles no library package again, a PR the packages it changed and all that depend on them. Read from CI's logs on 2026-10-12, a PR restoring master's last build spent 90–135 s in `cjpm build` against 144–191 s for v0.5.0's, built clean; its `cjpm test` 190–380 s against 297–358 s: nothing to see.
- Most PRs change `loupe`, which every package above it depends on: `loupe`, `project_model` and `cjls` are compiled again, and they are the heaviest — once for `target/release`, once more for `target/test`, one after the other in one job.
- **`cjpm test` compiles every test package again on every run** (cjpm 1.3.0-alpha, `cjpm test -V`): a `cjc --test-only -p modules/<m>/src/<pkg>` and a link per package, 30 binaries, whatever changed; `-i` does not reach them, and cjpm has no option that does. Then the binaries run.
- e2e and perf needed the job that built the binary to finish its tests too, before they started.

## Decision

- **Two jobs per platform**: `Build (<os>)` runs `cjpm build` and uploads the binary, which e2e and perf need; `Build and test (<os>)`, the name the ruleset requires, runs `cjpm test`. Each restores and saves the cache of its own target directory (`target/release`, `target/test`, with `target/cjc-version`, build.cj's stamp, and `build-script-cache`), under a key naming it. The rest of D27 holds: master's pushes alone save, a tag builds clean.

## Consequences

- A PR's wall-clock is the longer of the tests and the build followed by e2e, not their sum; e2e and perf start once the binary is built. The checkout and the SDK are set up in one more job per platform.
- The first master build after this restores nothing: the keys are new.
- The tests' own compilation stays outside any cache, as long as cjpm compiles test packages again on every run.
