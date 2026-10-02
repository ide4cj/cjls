# ADR-0036: calca evicts by LRU as it touches, within a revision too

Status: accepted, 2026-10-02; supersedes ADR-0017's "eviction happens only when a write opens a revision"

## Context

D17 evicted memo values only in `newRevision`, so a question over every file held every file's tree until the next edit: a sweep of `itemTree` over 8 754 files of `cangjie_test` (21 MiB of text) left 537 MiB more on the heap after a full collection, and the 14 000 files measured for D30 ran out of it. A15 kept `workspace/symbol` off `parse` for that reason, and every whole-workspace feature after it — name resolution (#48), `workspace/diagnostic` (#52), references, rename — would have met the same wall, `itemTree` first: it reads the memoized `parse` (#85). The other way out, that such a question never reads `parse`, cannot hold for diagnostics, whose syntax errors are `parse`'s.

## Decision

- **A touch trims**: `MemoTable` makes a key the last fetched and evicts the values beyond `lru` in one step, under the table's lock that a fetch of an `lru` function takes already. `IdLru.touch` itself still evicts nothing.
- **A reader keeps what it was handed**: eviction takes the value out of the memo, not out of a caller; a fetch that finds it gone between its touch and its read goes the cold way, as for any memo not current.
- **Fetched again in the revision it was evicted in**, a memo is verified (its `verifiedAt` is now) and computed again as unchanged, so it keeps its `changedAt` and nothing that read it runs again.
- **`newRevision` still trims**, for a fetch that ended before it computed (cancelled, unwound by a cycle) and left one key too many.
- Everything else in D17 stands: what a use is, what an evicted memo keeps, capacity at compile time (#54).

## Consequences

- A question over every file holds the `lru` values fetched last and what it keeps of its own: the same sweep leaves 72 MiB and runs a third faster (less to collect), and it no longer grows with the workspace's trees.
- A query that reads one tree twice parses it again if more than 128 others were fetched in between; on parallel snapshots the window is shared.
- A sweep through `parse` pushes the open documents' trees out, and the next request on one parses it again: a reason `fileSymbols` still parses on its own (A15).
- A result holding a node still keeps its tree alive whatever the LRU does (A13).
