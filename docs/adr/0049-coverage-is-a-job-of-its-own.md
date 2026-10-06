# ADR-0049: Coverage is a job of its own, counted over source files, shown by an endpoint badge

Status: accepted, 2026-10-06

## Context

- CI runs `cjpm test` on three platforms and says nothing of how much code the tests reach. `cjpm test --coverage` and the SDK's `cjcov` do; the whole workspace passes with `--coverage`, the static stdx and `-O2` do not get in the way.
- `cjcov`'s `coverage.xml` counts the `*_test.cj` files too (72% where the sources alone are 64%), and `-e`/`-i` match a path prefix, so tests cannot be left out by suffix there.
- A badge needs a place to live that a PR cannot change and that holds no secret.

## Decision

- **A job of its own, Linux x64 only** (`coverage` in `ci.yml`), `cjpm test --coverage` in `--target-dir target/cov`. Instrumentation slows the tests, and `build`'s cache and this one would undo each other (D24, D27).
- **The percent is `hitLines` over `totalLines` of `coverage.json`**, summed over `modules/*/src/**` files not ending `_test.cj` and not in the `GENERATED` list of `.github/scripts/coverage.py` (runnable locally). Generated code is left out: the generator's own tests cover the generator, and its output has nothing to check. The list is explicit, by path, not read from a header: a new generated file is a line in a diff. Macro-expanded code (`stdxx`) stays in, though the instrumentation does not see it.
- **The badge is a shields.io endpoint**: a JSON committed to the `badges` branch by a push to master, read through `img.shields.io/endpoint`. No secret, no third-party service. The job alone has `contents: write`; a PR never publishes.
- **The HTML report is an artifact** of every run, PRs included.
- **No threshold, no gate**: shared runners are noisy (D23).

## Consequences

- The badge is as old as master's last push; a run that fails publishes nothing.
- Branch coverage (`-b`, experimental), the fuzz run, e2e, Windows and macOS are not counted.
- The `badges` branch holds one file and its history; it is never merged.
