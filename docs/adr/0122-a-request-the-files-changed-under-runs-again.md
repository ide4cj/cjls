# ADR-0122: A read-only request the files changed under runs again on a fresh snapshot, not answered ContentModified

Status: accepted, 2026-10-20
Amends ADR-0008: a stale snapshot's `CancelledException` runs the request again; `ContentModified` is answered by no read-only handler
Amends ADR-0014: a pull the files changed under is answered from the files as they are then, not `ServerCancelled` with `retriggerRequest`

## Context

- A write cancels every in-flight query (D8): the request's snapshot throws `CancelledException`, and the server answered `ContentModified`, leaving the client to ask again.
- The server writes after a change of its own accord: the macro outputs of the change (D98, D104) land through `loop.write` some 50–300 ms after the `didChange`, while the completion that keystroke asked for (a `.` typed in a file with a macro call: every handler and every test of this repository) is being computed. In `modules/cjls/src/handlers/completion.cj`, 8 of 11 completions asked within 200 ms of the change were cancelled this way (`tests/e2e`'s client, VS Code's capabilities, the server of master); with the request run again, 11 of 11 answered, in 0.06–0.53 s.
- VS Code's client (`vscode-languageclient` 10) takes `ContentModified` as *no answer* for every request but semantic tokens and the resolves (`handleFailedRequest`: `RequestsToCancelOnContentModified`), and asks nothing more: the completion list stays empty for the keystroke, and completion looks broken in any file with a macro call. The `textDocument/diagnostic` pull alone was told to ask again (`ServerCancelled`, `retriggerRequest: true`, D14).
- rust-analyzer runs such a request again on the new state (`RETRY` in its dispatcher: completion, hover, …) and answers `ContentModified` only when the retry is not allowed.
- A client's own retry would be one more round trip for the common case, and no client but VS Code's semantic tokens makes it.

## Decision

- **A read-only request whose snapshot was cancelled by a write runs again**, on a snapshot taken under the loop then, until it answers or the client cancels it (`Server`, `runAgainOnAChange`): the answer is what the state holds now, never that it moved.
- **A request the client cancelled is not run again**: `RequestCancelled`, as D8 has it. Both the write and the cancellation having happened, the cancellation wins.
- **The pull is no exception**: `textDocument/diagnostic` answers a report of the files as they are then; `ServerCancelled` with `retriggerRequest` goes.
- No bound on the runs: each one follows a write, and writes are messages or the work after one (S7, S14); a request under writes that never end is a server that never idles, which the bound would not mend.

## Consequences

- A completion, hover or definition asked right after a keystroke is answered, a little later, instead of lost; an editor that never retried sees nothing but that.
- `ContentModified` is answered only when a handler on the loop throws `CancelledException`, which S1 says none does.
- A read-only handler may run twice for one request: it must stay a pure function of its snapshot and params (S3 already asks that), and a side effect in one (a log line) may show twice.
- `run`, a read-only notification's, still drops a cancelled handler: nobody waits on its answer, and the write that cancelled it does the work it would have.
