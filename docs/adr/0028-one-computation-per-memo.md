# ADR-0028: One handle computes a memo, the others wait; a wait that closes a loop is a cycle

Status: accepted, 2026-09-29

## Context

Two handles fetching one memo at once (the root and a snapshot, or two snapshots) both ran the body, and the last store won (#14 §5): correct, since stores happen only in the current revision, but `documentSymbol` and `semanticTokens` arriving together parsed a file twice. Nothing blocked, so neither a cross-thread cycle nor a deadlock could happen. salsa claims the memo and blocks the second thread; a thread blocked, through others, on itself is a cycle, found with a graph of which thread waits on which (D15).

## Decision

- **A claim per key**, in the `MemoTable`, under its lock: the handle verifying or computing a memo holds it, from before the memo is read to `finally`. Another handle waits on the table's `Condition`, then reads the memo again, verified or computed by the owner, or computes it itself if the owner failed — whatever the owner threw (its own `cancelledBy`, a bug) is not the waiter's.
- **The hot path takes no claim**: a memo holding a value and verified in the current revision is read as before.
- **A waiter wakes every 10 ms** (`CLAIM_WAIT`) and checks `unwindIfCancelled`, rather than `cancelledBy` becoming a hook that notifies (#14's open question): no change to `Storage.snapshot`, and a request cancelled while waiting stops within 10 ms. A write pending wakes it sooner: the owner throws `Cancelled` at its next calca call, and its claim goes in `finally`.
- **Cross-thread cycles**: `Runtime` keeps `waitsFor`, waiter handle → (owner handle, key), under one lock. Before waiting, the waiter follows it from the owner; reaching itself, it throws `CycleException` instead of waiting. A claim released drops the edges to it at once, so a waiter not yet awake is never taken for a loop. The thread that closes the loop throws; the others, released as it unwinds, find the cycle on their own handle.
- **Handles are numbered** (`Storage.handle`, per database): a claim and an edge name the handle, not the thread.

## Consequences

- A memo is computed once however many handles need it, and a waiter holds up a write no longer than its owner does.
- A cycle across threads is a `CycleException` on every handle in it, as a cycle on one is; recovering from either is #14 §6.
- A body that never reaches calca again (a long loop of one's own) keeps its waiters waiting as it keeps a write waiting: it calls `db.unwindIfCancelled()`.
- The claim costs nothing measurable on a hit (`ParallelFetchBench`).
