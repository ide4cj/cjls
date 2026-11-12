# ADR-0165: Separate macro completion from structured diagnostics

Status: accepted, 2026-11-03

## Context

A false hasExpandedMacros conflates incomplete work and failures. String
preparation problems encode source coordinates into messages, forcing agents
to parse them, while native diagnostics require manual JSON projections.
The experimental API has no compatibility requirement for these fields.

## Decision

Replace problems/hasExpandedMacros with loadDiagnostics and macros. The latter
is a MacroStatus with pending/settled state and independent structured diagnostics.
Settled describes a finished attempt, including failure and projects without
macros; pending is not itself an error. Values describe the script's fixed
revision, not mutable worker progress. Scheduling and preparation gates do not
change, and no new mandatory waiting operation is introduced.

Use WorkspaceDiagnostic for loading, macro preparation and selected-file analysis
findings. Preserve native severity, known UTF-8 ranges, source paths and one-based
line/byte columns. Give preparation issues stable category codes; unknown source
locations remain absent instead of being guessed from SDK/compiler text. Retain
macro warnings and mapped error/hint text supplied by loupe.

The runPython JSON encoder handles these values, TextRange and Severity directly,
including nested lists/dictionaries. Encoding stays within the script revision
gate and response budget. Do not auto-query all workspace diagnostics: scripts
select files and limit lists with totals/omissions using existing APIs.

## Consequences

Existing scripts must use the new properties and WorkspaceDiagnostic return type.
Completion cannot serve as a success test: inspect severity independently.
SDK/build failures can have no source location. Per-file analysis and preparation
channels may both report the same macro finding. Saved rejected output contains
plain JSON values and can describe an older revision; inspect before reuse.
