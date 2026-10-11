# ADR-0081: The perf threshold is on queries executed, not on time

Status: accepted, 2026-10-11
Amends ADR-0023: no threshold

## Context

D23 left `tests/perf` without a threshold: timings on shared runners move by 10–20%, and a history with thresholds needed metrics noise does not move, decided in #22. #115 named the two places one could live: a quiet machine (filaco.dev) running the suite nightly against the last release and opening an issue past a margin, or a threshold on counted work (queries executed per request, from calca).

The nightly needs a scheduler, credentials and a margin on a box outside the repository, finds a regression a day after the commit that made it, and still compares times, so its margin is a guess between flaking and missing. What a request costs the analysis is the queries it executes: calca executes a query only when no memo of it is current, so the count is the same in every run of the same requests on the same files, on any machine, and moves only when the analysis does more or less work. A lost memo, a query keyed too finely, an edit that invalidates more than it should — the regressions incrementality is for — multiply it.

## Decision

- **calca counts the bodies it runs**: `Storage.executions`, one atomic shared by every handle, added to as a tracked function executes.
- **cjls answers it**: `cjls/analysisStats` (`docs/lsp-extensions.md`), `queriesExecuted` since the start, advertised as `experimental.analysisStats`.
- **The driver reads it around each pass** of the navigation scenarios (`definition`, `hover`, `completion`): `cold_queries` straight after the open, `warm_queries` asking the same again, `edit_queries` after a declaration is added at the end of the file. The client pulls diagnostics, so nothing is computed behind the requests' back, and the requests go one at a time: the count is theirs.
- **`tests/perf/thresholds.toml` holds the ceilings**, per server, scenario and count, with the options they hold for; `cjls-perf check` fails a report over one, made with other options, or missing a scenario named. CI runs it after the report. A ceiling is the measured count with some headroom (warm stays at what it is: nothing to recompute); a change that does more work on purpose raises it in the same pull request, which says why.
- **Times stay reported, never failed on**, as D23 has it.

## Consequences

- A regression fails CI on its own commit, on any runner; one that only makes the same queries slower is not caught here, but by `@Bench` (C7) or the times read by hand.
- A scenario racing an edit against a request (`typing_hover`) is not counted: what a cancelled request had executed depends on when it was cancelled.
- A server without `cjls/analysisStats` is measured as before, without counts.
