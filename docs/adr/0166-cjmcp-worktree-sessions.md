# ADR-0166: Route MCP scripts to independent sessions by explicit root

Status: accepted, 2026-11-03

## Context

Agents create task worktrees after connecting MCP, and inherited connections can
still analyze the main checkout. One root per process (D161) requires reconnecting
or manually transporting calls to another stdio process. A shared active-root
switch would make correctness depend on interleaving between agents. D164 also
requires retained output to describe the workspace in which effects occurred.

## Decision

Add optional absolute root selection to runPython. Omission always selects the
startup default, never the previous call. Validate and canonicalize before code
execution; aliases reuse one session and invalid roots never fall back.

Keep independent database, VFS, macro host, revision and rejected-output state
for each canonical root. Retain at most four sessions by last use, closing the
least recently used worker and macro host before creating a fifth. Observed
root deletion retires its session. Close all sessions on transport shutdown.
Responses identify canonical root, connection-local sessionId and revision;
reopening a retired session assigns a new ID. Preparation and selection errors
have no executing revision. Python effects are never replayed automatically.

This supersedes D161's one-root-per-process restriction; synchronization and
fixed-revision execution remain unchanged. It specializes D164's session-local
last_output to a workspace session, including after a different root runs.

## Consequences

One tool connection supports multiple worktrees without reconfiguration. Calls
remain sequential and CPython/process state remains shared. Per-root SDK processes
and polling multiply resource use, bounded by four retained sessions. Eviction
loses warm caches and last_output; response identity makes that visible. Native
proxy retention is unchanged, so eviction is not a memory-reclamation guarantee.
Replacing a directory entirely between checks is input synchronization, not
filesystem-identity detection. Cross-connection caches, concurrent execution and
process isolation are deferred; a future broker can preserve this call contract.
