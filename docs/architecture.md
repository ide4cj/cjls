# Architecture

cjls separates the editor protocol from reusable language analysis. Start with the
flow below when changing a feature; read the linked rules before changing a
boundary. [Development](development.md) covers setup and verification, and the
[ADR archive](adr/README.md) records why choices were made. Current behavior is
specified by the design rules and source; an ADR's historical status is not a
feature availability flag. [Status reconciliation](design/adr-status-review.md)
records implementation evidence where that status still says `proposed`.

## Modules and boundaries

`cjls` owns the connection lifecycle, routing, open documents and protocol
translation. `loupe` owns analysis, with incremental state supplied by `calca`.
The compiler enforces the module boundary: `loupe` has no dependency on `cjls`
and cannot import its LSP types. Modules are reusable libraries with independent
dependencies and output types; server-only code is a package of `cjls` (D3).
Packages are compilation units, so adding a module does not buy build parallelism.
Nothing depends on the executable module.

```mermaid
flowchart TD
    client[Editor] --> rpc[jsonrpc: framing and cancellation tokens]
    rpc --> server[cjls: lifecycle, routes, handlers]
    server --> analysis[loupe: editor analysis without LSP]
    server --> projects[project_model: project discovery]
    server --> host[macro_host: builds and deadlines]
    host --> macro[macro_server: SDK process and protocol]
    host --> analysis
    projects --> analysis
    analysis --> calca[calca: incremental queries]
    analysis --> syntax[cjsyntax and ginkgo: lossless syntax]
    analysis --> binary[cjo and fbs: binary package views]
    analysis --> formatter[cjformat: syntax based formatting]
    analysis --> text[rope and index_map: text and identities]
```

This shows responsibility boundaries, not every manifest dependency. Read the
module's `cjpm.toml` for its exact dependencies. `platform`, on std alone, supplies
common declarations with OS-specific implementations for modules that need them
([C17](design/03-conventions.md#c17-platform-source-sets), D101).
`jsonrpc` uses `stdxx` and its JSON support (`fjson`, `fnum`); project loading uses
`ftoml`. These utilities do not know language analysis.

The [layer map](design/00-layers.md) names L0–L7. Across the handler/analysis
boundary, URIs, LSP positions and negotiated encodings become `FileId`, UTF-8 byte
offsets and analysis-owned results. Position conversion uses the text of the same
snapshot as the answer ([D5](adr/0005-loupe-knows-no-lsp.md)).

## A read request and an edit

For `textDocument/documentSymbol`, the connection frames a request and assigns a
cancellation token. On the read loop, the server checks lifecycle and routing,
then takes a snapshot linked to that token. A worker decodes the parameters,
translates the URI, calls analysis, converts ranges using the snapshot's rope,
and sends the result. The [request slice](design/01-request-slice.md) follows each
step and gives the rules for failures, diagnostics and outbound requests.

`textDocument/didChange` instead runs exclusively on the read loop, in arrival
order. It applies edits to the open buffer in the negotiated encoding, folds VFS
changes into analysis inputs and opens a new calca revision. This path changes
inputs and runs no queries. Open buffers belong to the editor; disk loads cannot
overwrite them. Background work returns changes through the loop's write boundary.

`ServerState` owns the VFS, open documents, encoding and root `AnalysisDatabase`.
`ServerSnapshot` holds a snapshot of that database and the request's view of
server data. Neither server type is itself a database. Distinct handler context
types give a read handler a snapshot instead of mutable `ServerState` (D8, D9).
They do not prohibit external effects such as file writes or requests to the
client. The contract for such effects and automatic retries is tracked separately
in [#462](https://github.com/ide4cj/cjls/issues/462).

A write cancels queries in flight and waits for them before updating inputs. A
stale read request runs again on a fresh snapshot; client cancellation ends it
with `RequestCancelled`, and a closed connection drops the answer. Do not catch
cancellation inside a handler or query. Diagnostics pushes have their own snapshot
and document generations, so an older push cannot overwrite a newer one. Clients
that pull diagnostics never receive pushes. See [cancellation](design/01-request-slice.md#cancellation-d8)
and [S1–S14](design/01-request-slice.md#rules).

## State ownership and background work

The request layers describe calls down into analysis. Execution also has feedback:
workers produce new inputs, a write invalidates snapshots, and the server schedules
work for the resulting state. The arrows below show execution and data flow, not
module dependencies.

```mermaid
flowchart TD
    editor[Editor messages] --> loop[Loop: serialize state access]
    loop --> state[ServerState: VFS, open documents, root database]
    state -->|snapshot| reads[Read request workers]
    loop -->|start load| loader[Project and disk workers]
    loader -->|Loop.write: project and file batches| loop
    loop -->|wake after files change| macros[Macro host worker]
    state -->|snapshot and analysis requests| macros
    macros -->|Loop.write: libraries and outputs| loop
    loop -->|schedule after writes| diagnostics[Diagnostics workers]
    state -->|snapshot| diagnostics
    reads -->|response| editor
    diagnostics -->|publish if document generation is current| editor
    state -->|input write| revision[calca: cancel readers, wait, update revision]
    revision -.->|stale snapshot: retry request| reads
    revision -.->|stale snapshot: drop push| diagnostics
```

`Loop` serializes mutable server access under one lock: both exclusive handlers
and background `Loop.write` calls use it, and snapshots are taken under it.
Background commits therefore happen between handled messages; they need not run
on the read-loop thread. `ServerState` owns the mutable server data, and calca owns
revision and dependency validity. Workers use snapshots or copied task inputs and
return changes through this write boundary rather than mutating the VFS or root
database directly ([S14](design/01-request-slice.md#s14-background-writes-use-the-loop)).

| Work | Who starts it | Who accepts the result and checks freshness |
|---|---|---|
| Read request | `Server.onRequest`, with a snapshot and request token | Server answers; stale snapshots retry, client cancellation ends the request |
| Project/disk load | Workspace handlers through `Loop.start` | Load commits use `Loop.write`; `ServerState` checks the load id and preserves open buffers |
| Macro work | Workspace setup starts the host; `Loop.afterWrite` wakes it when files change | Host rounds read snapshots and commit outputs through `Loop.write`, matched by stable call keys; an edit ends a round and later rounds ask again |
| Diagnostics push | `Loop.afterWrite`, for clients that cannot pull | `DiagnosticsPush` computes from a snapshot and checks the document's publish generation before sending |

Freshness is specific to each task: a serialized write alone does not establish
that a background result is current. The [request rules](design/01-request-slice.md)
define cancellation and publication requirements. Start in
[`Loop`](../modules/cjls/src/server/loop.cj),
[`workspace loading`](../modules/cjls/src/handlers/workspace.cj),
[`macro scheduling`](../modules/cjls/src/macro_host/host.cj) and
[`diagnostics push`](../modules/cjls/src/server/push.cj) when changing these paths.

## Analysis and incremental state

Inside `loupe`, dependencies point down: API → HIR → syntax → database → VFS.
Packages describe analysis layers; a feature is a file in the API package. Two
features share a lower-level query rather than calling each other. The API offers
plain functions over queries, including position-dependent questions; tracked
queries are keyed by entities so arbitrary cursor positions do not become
long-lived memo keys ([A1–A3](design/02-analysis.md#rules)).

The VFS maps stable file identities to optional immutable ropes and folds pending
changes. Its path interner is the thread-safe part. `SourceFile` inputs remain
allocated when files disappear; deleted text becomes empty. Project loading
normalizes different project formats into one model and lowers it into project,
module and package inputs. Membership comes from the project, not a scan of file
text. Input durability distinguishes workspace code, dependencies and std.

Binary packages are inputs of their `.cjo` bytes outside the VFS (D38); source
files attached to a binary are navigation destinations and do not create a second
resolution scope (D65). Queries lower source and binary declarations to the same
item model. Binary views borrow their input bytes: tracked results keep a stable
binary item identity and reopen the declaration instead of retaining `cjo.Decl`.

Resolution proceeds through file items, package scopes, signatures, bodies and
inference. Item summaries omit bodies and ranges so editing a body does not
invalidate package scope. Stable item and declaration IDs connect revisions;
syntax pointers recover nodes only when needed. Equatable query results allow
calca to backdate unchanged answers. Diagnostics are values in the query that
finds them; the API collects, locates and sorts them, without side accumulation.
The [analysis rules](design/02-analysis.md) cover memory bounds, cycle meanings,
type inference, unknown types, configuration and macro expansion navigation.

## Syntax and generated code

`ginkgo` supplies immutable green trees, syntax views, pointers and parsing
infrastructure. `cjsyntax` supplies Cangjie's lexer and grammar, error recovery and
typed AST views. Parsing preserves the whole text, including errors, so incomplete
editor buffers remain usable. `loupe.syntax` makes parsing an incremental query
with a bounded cache. Retaining a node retains its tree: other tracked results
keep pointers or summaries, not syntax nodes ([A13](design/02-analysis.md#a13-do-not-retain-syntax-trees)).

`cjformat` formats syntax without analysis; the server reaches it through `loupe`,
and `cjls fmt` can use it on text. Generated syntax kinds and AST views come from
`syntax_codegen` (D10), LSP types and adapters from `lsp_codegen`, and binary views
and protocol writers from `fbs_codegen` (D37, D87). Change generator inputs and
verify the consuming package; use the [generator procedures](development.md) and
module notes for commands. Generated files are not a second place to maintain a
schema or grammar.

## Macros and protocol isolation

Analysis identifies calls and writes requests as plain values. Macro outputs are
a separate input field of the source file; changing an output invalidates its
readers without changing source text (D98). The written and expanded scope stages
keep macro-name lookup independent of what expansion adds, avoiding a query cycle
([A31](design/02-analysis.md#a31-written-and-expanded-scopes)).

`macro_host` builds workspace macro packages, orders work, applies deadlines and
returns results to inputs. `macro_server` owns the SDK's `LSPMacroServer` process,
its FlatBuffers protocol and conversion from syntax tokens to compiler tokens.
Server-specific scheduling, settings and open documents stay in `cjls.macro_host`.
Thus `loupe` depends on neither SDK macro protocol structures nor LSP. std macros
can run through the same host, with analysis fallback expansions where specified
by D123. An expansion is read as a file in its call site's scope; mapped spans say
which text came from source and which the macro wrote. Current navigation limits,
body expansion limits and stable call keys are explicit in
[A35](design/02-analysis.md#a35-reading-macro-expansions).

LSP stdout is the wire. Logs use the supplied logger, and absent optional fields
remain distinct from JSON `null` (`@Serde[skipNone]`). The router and generated
specifications are the maintained protocol inventory; [LSP extensions](lsp-extensions.md)
document the additional client-facing contracts.

## Source entry points

| Change or question | Start here |
|---|---|
| Supported routes and one read handler | [router](../modules/cjls/src/handlers/router.cj), [document symbols](../modules/cjls/src/handlers/document_symbol.cj) |
| Server scheduling, snapshots, edits | [server](../modules/cjls/src/server/server.cj), [state](../modules/cjls/src/server/state.cj), [document sync](../modules/cjls/src/handlers/document_sync.cj) |
| Position and result conversion | [from protocol](../modules/cjls/src/handlers/from_proto.cj), [to protocol](../modules/cjls/src/handlers/to_proto.cj) |
| Incremental writes and cancellation | [database](../modules/loupe/src/db/db.cj), [calca runtime](../modules/calca/src/runtime.cj) |
| Analysis features and their tests | [loupe source](../modules/loupe/src/), [structure example](../modules/loupe/src/structure.cj) |
| Stable items, scopes, inference | [item tree](../modules/loupe/src/hir/item_tree.cj), [definition map](../modules/loupe/src/hir/def_map.cj), [inference](../modules/loupe/src/hir/infer.cj) |
| Syntax ownership and recovery | [green tree](../modules/ginkgo/src/green.cj), [Cangjie parsing](../modules/cjsyntax/src/parse.cj), [parse query](../modules/loupe/src/syntax/syntax.cj) |
| Macro input and output boundaries | [analysis requests](../modules/loupe/src/hir/server_macro.cj), [output values](../modules/loupe/src/db/macro_output.cj), [host](../modules/macro_host/src/), [SDK protocol](../modules/macro_server/src/) |
| Analysis fixtures and SDK prerequisites | [analysis testing](design/02-analysis.md#analysis-tests), [fixture helpers](../modules/loupe/src/fixture/) |

These are navigation points, not an API catalog. Find current symbols and behavior
in the source and neighboring tests. The [loupe migration record](design/loupe-migration.md)
accounts for the module-note pilot before the other module groups are migrated.
