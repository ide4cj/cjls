# ADR-0049: Coverage is a workflow of its own, counted over source files, shown by an endpoint badge

Status: accepted, 2026-10-06

## Context

- CI runs `cjpm test` on three platforms and says nothing of how much code the tests reach. `cjpm test --coverage` and the SDK's `cjcov` do; the whole workspace passes with `--coverage`, the static stdx and `-O2` do not get in the way.
- `cjcov`'s `coverage.xml` counts the `*_test.cj` files too (72% where the sources alone are 64%), and `-e`/`-i` match a path prefix, so tests cannot be left out by suffix there.
- `ci.yml`'s success is a gate: `bump.yml` (D21), `nightly.yml` (D39), the editors' paired branches (D32) and `release.yml` read it, and `release.yml` calls it with `contents: read`, which a called workflow can only lower.
- A badge needs a place to live that a PR cannot change and that holds no secret.

## Decision

- **A workflow of its own, Linux x64 only** (`coverage.yml`, on a push to master and on a PR), `cjpm test --coverage` in `--target-dir target/cov`. Not a job of `ci.yml`: a slow or failing instrumented run would hold back the nightly, the weekly release and the paired branches. Instrumentation slows the tests, and `build`'s cache and this one would undo each other (D24, D27).
- **The percent is `hitLines` over `totalLines` of `coverage.json`**, summed over `modules/*/src/**` files not ending `_test.cj` and in none of the lists of `.github/scripts/coverage.py` (runnable locally):
  - `GENERATED`: the generator's own tests cover the generator, and its output has nothing to check. By path, not read from a header: a new generated file is a line in a diff.
  - `MACROS`, the macro packages: they run at compile time, where the instrumentation does not see them, and `cjpm test` skips a macro package altogether (`isMacroPackage` in cjpm's `implement/test.cj`: a `*_test.cj` put in one is neither built nor run, checked), so they can be neither tested nor covered as they are.
  - `TEST_SUPPORT`, packages only tests import: their lines are run by tests alone, as a `*_test.cj`'s are.
- **The badge is a shields.io endpoint**: a JSON committed to the `badges` branch, read through `img.shields.io/endpoint`. No secret, no third-party service. The job that runs the tests reads only; a job of its own, running none of the code under test, has `contents: write` and publishes, on a push to master alone and only while that commit is still master's head (a re-run of an older run leaves the badge be).
- **The HTML report is an artifact** of every run, PRs and failed tests included.
- **No threshold, no gate**: shared runners are noisy (D23).

## Consequences

- The badge is as old as master's last push; a run that fails publishes nothing.
- Branch coverage (`-b`, experimental), the fuzz run, e2e, Windows and macOS are not counted.
- The `badges` branch holds one file and its history; it is never merged.
