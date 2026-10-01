# ADR-0030: The workspace is loaded on the read loop, under a budget, and watched by the client

Status: accepted, 2026-09-29

## Context

- The server knew a file only once the editor opened it, and read the disk only on `didClose`: nothing answered a question about the files not open (Q1, #12).
- rust-analyzer registers the client's watchers before it scans, loads on a thread of its own, and searches symbols through an index of its own (`file_symbols`).
- The runtime's heap is 256 MiB unless `cjHeapSize` says otherwise, and an editor starts the server without it. The text of a root far wider than a project (`cangjie_test`, 128 000 files and 222 MB of `*.cj`) filled it before the load ended, and the server died.
- `parse` keeps every tree it made until the next revision (D17): a search going through it held the trees of the whole workspace at once.

## Decision

- **Roots** are `workspaceFolders`, or `rootUri` without any. Under each, every `*.cj` but those in `target/` or a hidden directory; links are not followed; a file not UTF-8 is skipped (`loupe.vfs.readRoots`).
- **Loaded on `initialized`, on the read loop**, as one revision (`ServerState.setFilesContents`, on calca's `batch`). What arrives meanwhile waits and applies after it, so no guard against stale text is needed. An open document keeps the editor's buffer.
- **Watchers are registered before the scan**, one `client/registerCapability` registration per root, with an id of its own, so a folder removed unregisters alone. A `RelativePattern` if the client takes one, a glob of the root's path otherwise; nothing, with an `INFO`, without dynamic registration.
- **An outbound request is answered on a `spawn`** (`Client.request(spec, params, logger)`), a failure a `WARN`: a handler must not await it.
- **Watched files**: created or changed is read from disk, deleted is `None`, a directory deleted takes every known file under it; an open document is left alone; one notification is one revision. A file out of every root is the same `None` as a deleted one (A5).
- **A load keeps at most 16 MiB of text**, with a `WARN` when files were left out. A file is told by its size before it is read, and one that does not fit in what is left is skipped. On the default heap, 16 MiB of `cangjie_test`'s `LLT` (14 000 files) loaded in 1.6 s and was searched in 1 s; with 32 MiB the first search ran out of memory. The whole of `cangjie_test` is walked in 2.3 s, 763 files kept.
- **`workspace/symbol` goes through `fileSymbols`**, a tracked query per file that parses on its own and keeps only names and ranges: the trees are garbage at once, and the next search reuses the memos (813 files of cjls: 0.26 s the first time, 10 ms after). Matching is a case-insensitive subsequence; 128 results at most, as rust-analyzer.

## Consequences

- A project the size of cjls (813 files, 2 MB) loads in 22 ms.
- A workspace over the budget is seen partly, as the disk lists it, until the rest is opened. Raising the budget needs a larger heap, or less memory per file.
- A thread that runs out of memory dies without answering (`OutOfMemoryError` is not an `Exception`): the request is never answered.
- No server-side watcher for clients without dynamic registration, no `$/progress`, no reading on a `spawn`, no project model from `cjpm.toml` (#69).
