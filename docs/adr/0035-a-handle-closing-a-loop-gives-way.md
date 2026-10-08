# ADR-0035: A handle closing a loop of waits gives way, and the owner computes the cycle; one memo per handle otherwise as D29

Status: accepted, 2026-10-02; supersedes ADR-0029

## Context

D29 made one handle compute a memo while the others wait, and a wait that would close a loop of handles a `CycleException` for the handle closing it, fallbacks or not. On one handle a cycle whose queries all have a fallback takes them (A14), so two requests entering one such cycle from both ends — a glob import cycle, a recursive type alias, met by semantic tokens and diagnostics on snapshots of one revision — answered differently by which got there first: one the fallback, the other an internal error (#99).

## Decision

- **D29 stands but for its cross-handle cycle**: a claim per key, the hot path without one, a waiter waking every 10 ms, handles numbered.
- **The handle closing a loop gives way.** `Runtime.startWaiting`, following `waitsFor` from the owner back to the waiter, records the wait all the same and throws `GiveWayException` naming the waiter's own query the loop waits for. The handle unwinds to where it claimed that query, lets go of every claim above it, waits until the query it was after is let go of, and fetches its own again.
- **The owner computes the whole cycle on its handle**, now unblocked, so it is a cycle of one handle: fallbacks if every query on it has one, else a `CycleException` there. The handle that gave way finds the memos left verified in the revision, or, if the owner threw, computes them itself and finds the same cycle. Either way every handle answers as one handle would.
- **A waiter waking to look for cancellation records nothing again** (`startWaiting` is idempotent for the same owner and key): it would otherwise find, through the edge of the handle giving way, a loop already broken.
- **The walk is bounded** by the number of edges: while a handle gives way the graph holds a loop that does not reach the waiter.

## Consequences

- A cycle across handles recovers by its fallbacks, as on one handle; `CycleException` is thrown only by a cycle found on one handle, its `participants` the whole path.
- The handle giving way loses what it computed above the query it unwinds to, which the owner computes once more; cycles across handles are rare enough.
- A handle giving way is cancelled as any waiter is, within 10 ms.
