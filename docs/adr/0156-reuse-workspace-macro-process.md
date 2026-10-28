# ADR-0156: Workspace macro libraries reuse one SDK process despite K28

Status: accepted, 2026-10-28
Amends ADR-0155: workspace library switches reuse the SDK process; K28 remains open

## Context

D155 restarted the workspace macro server whenever the selected library path
changed, isolating the conflicting package and helper code described by K28.
This makes alternating macro libraries pay process startup on every call, even
when their dependencies are compatible. `MacroLibrarySwitchBench` and PR #563
record the comparison; those approximate timings were collected under ambient
load and do not establish precise release performance.

The maintainer chose to remove that cost while retaining the SDK defect and its
reproduction as an explicit limitation.

## Decision

Reuse one workspace `LSPMacroServer` across library-path changes. Keep calls and
explicit workspace restarts serialized, retain restart-on-rebuild and failure
handling, and preserve the independent std macro process (D123).

Keep K28 open in the SDK issue registry. Test process reuse using the actual SDK
process ID, and retain the conflicting-library fixtures with explicit restarts
to show how to reproduce the defect without making its persistence a test contract.

## Consequences

Switching libraries no longer adds a cjls-initiated process restart. Compiler
artifacts and analysis outputs remain scoped as D155 requires, but conflicting
libraries in the shared process can still expand using previously loaded code.
Removing this workaround is a performance tradeoff, not evidence of an SDK fix.
