# ADR-0085: A dependency keeps the object it was read from, which answers for it without a lock when it can

Status: proposed
Amends ADR-0084: a memo verified in this revision answers a dependent through its entry, not its table

## Context

- D84 left a new revision's floor in verifying: an edit of `nodes.cj` verifies ~122 000 edges. Counted by kind on that edit: 78 000 lead to a memo verified in this revision already, 34 500 to an interned value (`Ty`, `DefId`), 9 000 to a memo still to verify, 136 to an input.
- Each edge was a `DatabaseKey` asked of its ingredient: the table's `Mutex`, its `Slab` searched by `Id`, then the memo — or, interned, the value marked used. The first two kinds, 92% of the edges, always answer the same: a verified memo its `changedAt`, an interned value used in this revision that it is still there.
- The `Slab` is not thread-safe (D18): reading it without the lock would need a concurrent one, with generations checked on every read. R1's salsa keeps a dependency as a `DatabaseKeyIndex` and asks its ingredient each time (`maybe_changed_after`).

## Decision

- **A dependency is its key and an `Edge`**, the object it was read from: a tracked function's `MemoEntry`, an interned value's `InternSlot`; an input has none (`ASK_THE_INGREDIENT`). Verifying asks the edge first: a memo verified in this revision with a value answers with its `changedAt`, an interned value whose last use is this revision answers unchanged, by atomics alone; anything else goes to the ingredient as before.
- An interned value used again in a revision is not touched again: its first use there ordered it for collection, and a value used in this revision is not collected before the next.
- A memo dropped with its key leaves its entry with no memo, so an edge to it asks the table, which finds it gone; a collected interned value is never used again, so its edge asks the table too.

## Consequences

- `VerifyBench` (calca: 1024 memos of 72 dependencies each, two to one memos and interned values, as `inferBody`'s): an unrelated edit 29.5 → 12.8 ms ±2%. `HighlightBench`: 214.5 → 192.9 ms ±9% after a space added in the last body of `nodes.cj`, unchanged with its bodies inferred.
- `tests/perf` (D84's files and runs, three each, interleaved, at load below 1.5): a keystroke p50 on `infer.cj` 111 → 86 ms (`tokens`) and 96 → 78 ms (`tokens_body`), on `nodes.cj` 255 → 217 ms and 253 → 215 ms; p95 on `nodes.cj` 358 → 299 and 286 → 225 ms; first tokens unchanged. Peak RSS on `nodes.cj` 368 → 394 MB and 357 → 404 MB, far more than the edges' bytes, on `infer.cj` within the runs' spread: not explained yet.
- A dependency is 8 bytes more, and it keeps alive a dropped memo's entry and key, or a collected value's fields, until the memo reading it is computed again.
- `MemoTable.maybeChangedAfter` has no fast path of its own any more: what reaches it is not verified in this revision.
