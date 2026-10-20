# Request slice

## Read request (`textDocument/documentSymbol`)

| Thread | Step | Where |
|---|---|---|
| read loop | frame → `Body.Request` → `InboundRequest(id, token)` | `Connection.serve` |
| read loop | lifecycle check → `ReadOnly` route | `Server.onRequest` |
| read loop | **snapshot taken here**, with `cancelledBy: token` | `ServerState.snapshot` |
| spawn | `decodeParams` → `P` (else `INVALID_PARAMS`) | route |
| spawn | `T.from(ctx)` per parameter | `@LspHandler` adapter |
| spawn | URI → `SourceFile`, `Position` → offset | `from_proto.cj` |
| spawn | `fileStructure(snap.analysis, fileId)` | `loupe` |
| spawn | offsets → `Range` via the snapshot's rope | `to_proto.cj` |
| spawn | `encodeResult` → respond | `Server.answer` |

Every read request takes this path; only the `loupe` call and its translation differ. Which ones the server answers is `handlers/router.cj`.

## Write notification (`textDocument/didChange`)

| Thread | Step | Where |
|---|---|---|
| read loop | `Exclusive` route, in arrival order | `Server.onNotification` |
| read loop | edits → `Rope.replace`, in the encoding agreed on | `handleDidChange` |
| read loop | `Vfs` → `takeChanges` → `AnalysisDatabase.applyChanges` | `ServerState.setFileContents` |
| read loop | calca: cancel in-flight snapshot queries, wait for them, new revision | `Runtime.write` |

## Server push (`textDocument/publishDiagnostics`, D14)

Only for a client that cannot pull (`initialize` found no `textDocument.diagnostic`, kept in `ServerState`).

| Thread | Step | Where |
|---|---|---|
| read loop | an `Exclusive` handler (request or notification) returned, having changed the files or opened a document | `Server.writing` |
| read loop | snapshot; the open documents with their `version`, and a new generation for each | `DiagnosticsPush.schedule` |
| spawn | per open document: `diagnostics(snap.analysis, fileId)` → LSP `Diagnostic`s | `documentDiagnostics`, `to_proto.cj` |
| spawn | generation still the document's latest → `client.notify(PublishDiagnosticsNotificationSpec(), …)` with its `version`; else dropped | `DiagnosticsPush.publish` |
| spawn | `CancelledException` → dropped, `DEBUG`: the write that cancelled it scheduled its own | `DiagnosticsPush.schedule` |
| spawn | one document's diagnostics throw an `Exception` or overflow the stack → `ERROR` with its `uri`, that document skipped, the others sent | `DiagnosticsPush.computed` |
| spawn | the connection closed → dropped, `DEBUG`; anything else (a failed send, any other `Error`) → `ERROR`, the push ends | `DiagnosticsPush.schedule` |

`didClose` publishes an empty list for the document at once, on the read loop, so its errors do not stay in the editor.

## Cancellation (D8)

| Cause | Mechanism | Answer |
|---|---|---|
| a file changed | `Runtime.write` cancels in-flight queries; a stale snapshot throws `CancelledException` | the handler runs again on a snapshot taken then, until it answers or the client cancels (D122); `ContentModified` only from a handler on the loop, which runs no query (S1) |
| `$/cancelRequest` | token → snapshot's `cancelledBy` → next calca call throws `CancelledException` | `RequestCancelled` |
| connection closed | every token cancelled | dropped |
| a push overtaken by a write | its snapshot throws `CancelledException`, or its generation is no longer the latest | nothing sent |

## Rules

| # | Topic |
|---|---|
| S1 | [Write handlers change inputs](#s1-write-handlers-change-inputs) |
| S2 | [Read from one snapshot](#s2-read-from-one-snapshot) |
| S3 | [Handlers translate](#s3-handlers-translate) |
| S4 | [Unknown documents](#s4-unknown-documents) |
| S5 | [Cancellation escapes handlers](#s5-cancellation-escapes-handlers) |
| S6 | [Handlers are not queries](#s6-handlers-are-not-queries) |
| S7 | [Schedule after writes](#s7-schedule-after-writes) |
| S8 | [One diagnostics source](#s8-one-diagnostics-source) |
| S9 | [Discard stale pushes](#s9-discard-stale-pushes) |
| S10 | [Outbound request boundaries](#s10-outbound-request-boundaries) |
| S11 | [Open buffers own their text](#s11-open-buffers-own-their-text) |
| S12 | [Batch changes into revisions](#s12-batch-changes-into-revisions) |
| S13 | [Catch failures at thread boundaries](#s13-catch-failures-at-thread-boundaries) |
| S14 | [Background writes use the loop](#s14-background-writes-use-the-loop) |

### S1: Write handlers change inputs

A `Context` handler never runs a query: it only changes inputs, and it is short.

### S2: Read from one snapshot

A `readonly` handler reads everything from its snapshot: `FileId`, text for positions
(`file.text(snap.analysis)`, never the `Vfs`), encoding.

### S3: Handlers translate

Handlers only translate; logic goes to `loupe`.

Conversion lives in `from_proto.cj` / `to_proto.cj`.

### S4: Unknown documents

An unknown document gets an empty answer (`null`, `[]`, an empty report).
Malformed parameters use `RpcException` with `INVALID_PARAMS`; a valid request that
cannot be fulfilled may use `REQUEST_FAILED`, as when `cjls.expandMacro` cannot write
the expanded file or the client cannot show it. See
[`handleExecuteCommand` and `writeExpandedFile`](../../modules/cjls/src/handlers/expand_macro.cj).

### S5: Cancellation escapes handlers

Never catch `CancelledException` in a handler; the server maps it (see table).

### S6: Handlers are not queries

LSP handlers stay ordinary functions; incremental memoization belongs in `loupe` queries
keyed by analysis entities (D6, [A2–A3](02-analysis.md#a2-entity-query-keys)). A handler
translates request parameters and analysis results, using its snapshot's client settings;
any effects must run on each invocation rather than be skipped on a cache hit.

This is an architectural boundary. [`@LspHandler`](../../modules/cjls/src/macros/lsp_handler.cj)
only adds a context-extracting overload; it does not explicitly reject `@CalcaTracked`.
D6's original claim that calca has no LRU or GC is historical: memo values can now be
evicted (D17), and unused interned values are collected with the memos keyed by them
(D18). Other keys still live as long as the database (A2), so these mechanisms do not
bound a cache keyed by arbitrary request parameters.

### S7: Schedule after writes

Work after a write is scheduled by the server, not by a handler: it takes the snapshot on the
read loop, after the `Context` handler returned, and runs the queries on a `spawn` (D14).

### S8: One diagnostics source

One source of diagnostics per client: a client that pulls is never pushed to (D14).

### S9: Discard stale pushes

A push never overwrites a newer one: a publish whose generation is not its document's latest is
dropped before `notify`.

### S10: Outbound request boundaries

An outbound request goes by its spec, never a method string: `Client.request(spec, params,
logger)` sent from the handler, answered on a `spawn`, a failure logged; one whose result is
read, `Client.request(spec, params)`, awaited on a `spawn` of its own.

A handler never awaits one (D30).

### S11: Open buffers own their text

An open document is the editor's: nothing read from disk (a load, a watched change, a folder
removed) sets it; `didClose` hands it back to the disk (D30).

### S12: Batch changes into revisions

The changes one handler makes to the files go in one revision (`ServerState.setFilesContents`).

A load's are the project with the files of the folders removed gone in one
(`ServerState.setProject`), then a revision per batch read, which only adds files (D61).

### S13: Catch failures at thread boundaries

Every `spawn` and the read loop catch `Error` (a stack overflow, out of memory) as well as
`Exception`: a request is answered `InternalError`, the failure logged `ERROR` with its stack
(`ErrorLogValue`: stdx.log takes no `Error`), and the server reads on.

### S14: Background writes use the loop

Work a handler leaves to a thread of its own (`Loop.start`, catching everything) changes the
state through `Loop.write` alone; a `Context` handler holds the lock already and never calls
`write` (D61).
