# ADR-0075: A write that changes no input opens no revision

Status: proposed
Amends ADR-0018: interned values

## Context

- D18 collects a `Low` interned value unused for `N` active revisions of its table, and relies on the memos holding it being verified by their edges, which marks it used. `verify` skips the edges when nothing of the memo's durability changed since it was verified, and marks it current all the same.
- Every input set or created calls `Runtime.changed`, which stamps the `Low` rank at least. A write that sets nothing still opened a revision: `Storage.batch` with nothing in it, which the server makes on each reload of a project that did not change (`State.setProject`, on `workspace/didChangeWatchedFiles`).
- In such revisions a `Low` memo passes without its edges, while anything else interning or reading values of the table makes the revision active: after `N` of them the memo hands out a collected `Id`, and reading it throws until an input changes. Seen in VS Code as hover and definition failing with `DefId has no value 1359 in this database` while moving around the project, after five reloads set off by another session creating and building a worktree under `.claude/worktrees/`, inside the workspace (`ctorsOf` reading what `packageExports` held).
- Alternatives: verifying the edges of every memo when nothing changed, which is the cost the durability check is there to save; counting as active only the revisions where something changed, which puts the input revisions into each interned table; not opening a batch the server knows is empty, which leaves the same trap for the next caller.

## Decision

- **`Runtime.write` takes the revision back when `change` changed nothing**: it opens it as before, and once `change` returns or throws, stores the previous number again unless `lastChanged` of `Low` is the new one. Nothing else is stamped with a revision inside a write.
- Ingredients' `newRevision` still runs in such a write: what it collects was unused in revisions where every `Low` memo was verified by its edges, so no memo current in the revision kept holds it.

## Consequences

- Between two revisions some input changed: a `Low` memo verified in an older revision always walks its edges, so a value it holds is used whenever the memo is.
- A snapshot pinned before an empty write is not cancelled by it: nothing it reads changed. What was in flight during the write is still cancelled.
