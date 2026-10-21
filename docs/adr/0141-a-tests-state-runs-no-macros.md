# ADR-0141: A state runs no macros unless it is given what starts them

Status: accepted, 2026-10-20

## Context

- `startMacros` (D104) started a `MacroHost` at the end of every state's first load. Its thread waits for work or `stop()`, and holds the `Loop`, so the `ServerState`, its database and std's `.cjo` (52 MB on Linux x64) live as long as the process. The server stops it at `shutdown`; no unit test does.
- In `cjls.handlers`' test process every test that loads kept its state: with three more of them (#447) the 2 GB heap was spent, `LoadOffTheLoopTest` hung, then threw `OutOfMemoryError` under `--timeout-each` (#448). The hosts of those tests also built and expanded the workspace's macros in the background with the SDK on the machine, against the answers a test set itself (`macroWorkspace`).
- Weighed (#448):
  - the shared helpers, or each class's `@AfterEach`, stop the host: every test that loads, and every new one, has to;
  - the host holds the `Loop` weakly and stops once nothing else does: its thread waits on a condition, so it would wake on a timer to look, and a `WeakRef` is cleared only after a collection, at an unknown time (macOS clears some to reachable objects);
  - a state starts a host only if it is told how.

## Decision

- **`ServerState.startsMacros`**, `?(Loop, Logger) -> MacroWork`, is what `startMacros` calls at the end of the first load; `None`, as a state is made, starts nothing, and `wake`s nothing after a later load.
- **The server's is given in `main.cj`** (`runServer`): a `MacroHost`, started. A unit test's state runs no macros; a test of `startMacros` gives a `MacroWork` of its own (`StartMacrosTest`).

## Consequences

- `cjls.handlers`' test process peaks at about 0.3 GB instead of the 2 GB heap (186 tests, Linux x64, 1.3.0-alpha.20261014), and no longer grows with the tests that load; `stopMacros` of #447 is not needed.
- That the server starts the host is held end to end alone (`test_the_server_runs_stds_macro_once_the_workspace_is_loaded`, waiting for the server's answer of std's `@Derive` from refresh to refresh): a `router()` served in a unit test (`lifecycle_test.cj`) runs no macros, and the e2e test of `cjls/expandMacro` before it read cjls's own expansion.
- A unit test of the host's work through the handlers gives the state a `MacroHost` itself, and stops it.
