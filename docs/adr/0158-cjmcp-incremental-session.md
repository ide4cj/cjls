# ADR-0158: MCP scripts run on one synchronized workspace revision

Status: accepted, 2026-10-29

## Context

The MCP prototype reloaded a fresh database and expanded all macros to observe
agent edits. It retained state between calls, but reload discarded warmed query
caches and compiler artifacts. Agents need current analysis before a script and
consistent text, identities and expansion outputs throughout it. Automatically
retrying arbitrary Python could duplicate file writes and subprocess effects.

## Decision

Keep one incremental database and macro host per stdio MCP process. Poll disk
between calls, and synchronize again before each runPython. Rediscover project
membership, apply changed source/project/binary inputs, and finish required macro
builds and expansion rounds. Repeat the disk check after an observed change so
edits made during preparation are incorporated before Python starts.

Use one gate for preparation and the whole Python execution, including result
serialization. Defer database changes until the script finishes. reload inside a
script requests later preparation. Return the script's session-local revision
number with both successful and failed Python executions; preparation errors
have no executing revision. Do not replay Python automatically.

Retain build artifacts and SDK processes for the session, restarting workspace
macro processes when built libraries change. Hash compiler source contents in
build stamps: the SDK's FileInfo modification time has whole-second precision and
cannot distinguish rapid same-size edits. Stop the polling worker and close
SDK processes on transport shutdown. Native values and analysis identities keep
their producing revision; an AnalysisRevision used after a workspace update
reports ContentModified rather than querying new inputs with old identities.

## Consequences

Repeated calls reuse query and expansion caches, and agents do not need to call
reload after edits. A running script delays all database updates. A long initial
load, ongoing external edits or a slow macro build can still delay the next call.
The polling implementation reads sources and rediscovers membership even when
analysis inputs do not change; it is not a filesystem watcher or an atomic disk
snapshot. Binary freshness uses size/mtime stamps. Direct Python I/O can see disk
changes that the script's fixed analysis revision deliberately cannot see yet.

Retained AnalysisRevision handles no longer preserve historical databases across
updates. Native Python proxy retention remains an independent experimental
limitation. Persistent storage and sharing workspaces across chats are deferred.
