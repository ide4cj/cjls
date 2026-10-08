# ADR-0061: The workspace is loaded on a spawn and set in batches between the messages, through a lock the read loop's handlers take too, reporting $/progress; a request meanwhile answers from what is loaded

Status: accepted, 2026-10-08
Amends ADR-0030: the load on the read loop, in one revision

## Context

- D30 loaded the workspace on the read loop, in one revision: nothing was answered meanwhile, `didOpen` and `didChange` included, and the editor showed nothing of why. On `cangjie_test` (filaco.dev): `testsuites/LLT` (32 748 files) held the loop 2.4 s, the whole (87 723 files) 11 s; a document opened at `initialized` had its outline after 2.6 s and 11.6 s. Since D33 a `.cj` created or deleted, or a manifest changed, finds the project again, and for loose files that walks the whole root, on the loop as well (#84).
- rust-analyzer reads on a thread of its own (`vfs-notify`), hands the files to its main loop in batches, reports `$/progress`, and answers requests meanwhile from what is loaded.
- `jsonrpc` has no queue to post work to the read loop: the loop blocks in `transport.read()`, and the runtime has no `select` over it and a queue.
- LSP: a server must not use a token whose `window/workDoneProgress/create` the client answered with an error.

## Decision

- **`Loop` (`cjls.server`) is a lock over `ServerState`** that every `Context` handler runs under, every snapshot is taken under, and work on a thread of its own writes through (`loop.write`), followed by the work after a write (S7) as a handler is. A write from a thread is one more message, between two others, never inside one. Rejected: a queue the read loop drains (a second thread to read the transport, `jsonrpc`'s callbacks no longer on the reading thread), and the budget alone (D30's alternative: the heap and the latency on one knob).
- **A load runs on `loop.start`**: the project found (`findProjects`), the stamps of the `.cjo` taken in one write, the binaries read, the project set with them in one write, then the files of its packages the server does not know read and set 1024 at a time (`LOAD_BATCH`), one write and one revision each.
- **A file set by anything but the load since it began is left as set** (`ServerState.setDuringLoad`): an open document, a `didChangeWatchedFiles` or `didClose` in between, a deletion. A load begun ends the one before at its next write (`beginLoad`'s number), so what a removed folder or a manifest changed calls for is never undone by an older read.
- **`$/progress` when the client takes it** (`window.workDoneProgress`): the token `cjls/load/<n>` created and begun at once, as rust-analyzer does, a report of `done/total files` after each batch, end; nothing more once the client answered the creation with an error, which a thread of its own waits for. Rejected: awaiting the answer before the load (a client that never answers would hold the load up forever), and a bounded wait (a timeout deciding what the user sees).
- **A request before the end answers from what is loaded so far**, as rust-analyzer does: `workspace/symbol` lists the files set, diagnostics see the packages filled so far. Rejected: waiting for the load (a `readonly` handler's snapshot is taken when its message arrives, so a wait would need another snapshot, past the messages after it).

## Consequences

- A document opened at `initialized` gets its outline in 254 ms on `LLT` and 568 ms on the whole of `cangjie_test` (the outline of a file of 8 000–10 000 symbols, beside the load's thread and its garbage); `didOpen` itself took 9 ms. The load takes as long as before (2.4 s, 11 s).
- The loop waits 4–26 ms per batch, and 90 ms (`LLT`) to 380 ms (all of `cangjie_test`) once, for the write that sets the project and lists the files to read.
- A revision per batch cancels what the snapshots before it computed: a pull answered `ServerCancelled` asks again, a push is scheduled anew; the peak heap of edits during a load is higher (1.29 GB against 1.0 GB, typing in `cangjie_test` as it loads).
- A handler on the loop holds the lock already: it calls `loop.start`, never `loop.write` (S14). Tests run a load to its end with `loop.join()`, or call `load` on the test's thread.
