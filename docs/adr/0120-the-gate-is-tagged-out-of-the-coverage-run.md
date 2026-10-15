# ADR-0120: The diagnostics gate is tagged `gate` and left out of the coverage run

Status: accepted, 2026-10-15

## Context

- The coverage run (D49) is `cjpm test --coverage -g`: unoptimized and instrumented, 6–11 times slower than the `Test` job on the same tests. It went from 4–7 minutes to 20–23 between 2026-10-09 and 2026-10-14, as `DiagnosticsGateTest` (D90) and `ErrorRootsGateTest` (D108) came: the two infer every body of this repository and of std's sources, 536 s of the run's 16 minutes of tests (49 s in `Test`), and the std case at 283 s was 17 s short of the class's `@Timeout` of 5 minutes. cjpm runs the packages' tests one after another.
- The gate is a check of the analysis on real code, not a test of a line: what it alone reached was 69 lines, 0.3 of a point (91.6 → 91.3 %), 40 of them in `infer.cj`, and 14 only from std's sources; measured on filaco.dev, the same full run and one with `--exclude-tags gate`.
- rust-analyzer runs its whole-repository and sysroot `analysis-stats` as a job of its own, not under coverage, and gates its slow tests on `RUN_SLOW_TESTS`/`SKIP_SLOW_TESTS`; gopls skips its load of `GOROOT` under `-short`. The practice is one switch, two modes of one test set.
- `cjpm test --parallel N` runs the test classes in `N` worker processes, the packages overlapping; under `--coverage` the gcda files merge (the same percent). The gate's class alone would still be the critical path, `ErrorRootsGateTest` in another worker inferring the workspace again, and four processes of 2 GB of heap on the runner's 16: not taken now.

## Decision

- **Both gate classes carry `@Tag[gate]`, and the coverage run passes `--exclude-tags gate`.** They stay in `cjpm test` and the `Test` job on every platform, as they are. A test that checks the analysis over a corpus rather than a case takes the tag.
- **What the gate alone covered is covered by fixtures**: a construct no fixture had (`synchronized`, `VArray`, a range with a step, an alias called, an argument of a lambda against overloads of fewer or no function parameters, …) is a case in the test of its query, in the same change.
- `--parallel` for the coverage run is a change of its own, after this one has run for a while: it would show a race between classes of one package only there.

## Consequences

- The coverage job takes about 10 minutes, and its percent is of the unit tests alone; a gap only the gate would have reached shows as a lower percent, to be closed by a fixture.
- The gate's `@Timeout` is measured against the `Test` job's optimized run alone.
- A `@Tag` that `cjpm test --exclude-tags` reads is the one convention for a test the coverage run leaves out; no environment variable, no second test target.
