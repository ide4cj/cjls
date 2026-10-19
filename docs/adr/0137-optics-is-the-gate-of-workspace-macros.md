# ADR-0137: A workspace of others' on its own macros, Optics, is expanded and analyzed as a gate

Status: proposed
Amends ADR-0026: the suites fetched

## Context

- The workspace's macros are built by the SDK's cjc and run in its macro server (D104), and what they answer replaces or stands for the call (D98, D117). Every test of it is a fixture of a toy macro this repository wrote, or std's (`StdExpansionDriftTest`): nothing holds the round to a macro written by someone else, on inputs written for cjc alone.
- [BonZirka/Optics](https://github.com/BonZirka/Optics) (MIT) is a workspace of three modules whose macro package `lucida.macrodsl` is a DSL: `@Optic[...]` and `@Lens[...]` on declarations, with fields on lines of their own; `@DeriveOptics`; `@f(...)` in bodies, holding `@use`, `@typeof` and `@ty`, which check `insideParentContext("f")`. The pinned nightly builds it clean. It changes without us, and its own harness (`check_codegen.sh`) holds its expansions to a baseline.
- Run first, loaded by `findProject`, built by `buildPlan`, expanded round by round as `MacroHost` does (9 s on Linux), it found 21 failed calls on code cjc compiles, none of which a fixture had shown: 7 because cjls sent an attribute's or an input's leading line breaks, which cjc drops (checked with a probe macro printing `attr`'s kinds), fixed in this change; 14 `@f` calls sent with an `@use` unexpanded, in an input that is no expression (#443). Counting a call never sent, too, found 14 `@f`s holding calls (#371).

## Decision

- **Optics is a suite of `tests/corpora/fetch.py`** (D26), at a pinned commit: its sources and manifests only. Moving the pin is a change of its own, which updates the list below.
- **`OpticsGateTest` (`macro_host`, `@Tag[gate]`, D120) loads it, builds its macro packages into a fresh directory, and expands every call the server runs until none is left to send**, then holds what it finds to `modules/macro_host/optics_diagnostics_known.txt`, as `DiagnosticsGateTest` does std's sources (D90): each diagnostic of its files, a failed call's among them, and each call the server runs that was never sent, a line naming its gap's issue; a new line fails, so does one gone, and `UPDATE_EXPECT=1` writes it. On every platform, under the host's cfg.
- What a gap is gets a fixture where it is fixed (C7): the gate finds, it does not stand for a test.

## Consequences

- `cjpm test` builds Optics's macro package with the SDK's cjc once a run, into a temporary directory: seconds, and the SDK is needed, as `GuardedServerTest`'s already is.
- A nightly that builds Optics otherwise, or a new commit of it, can fail the gate on lines that are not cjls's: the pin moves deliberately, and a line of Optics's own (a macro that fails under cjc too) is written as such, not fixed.
- The gate reads what the server would show: an expansion cjls accepts but which differs from cjc's in what it declares is not seen; comparing the output to Optics's `expected_expansions.txt` is not done.
