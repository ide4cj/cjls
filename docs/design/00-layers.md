# Layers

The [architecture overview](../architecture.md) explains module responsibilities,
request and edit flow, syntax and macro boundaries. This is the stable L0–L7
reference used by the rules and ADRs; the module manifests define dependencies.

L0–L7 describes the downward path of a request. It is not the scheduling model:
background results feed inputs, invalidate snapshots and trigger further work.
See [state ownership and background work](../architecture.md#state-ownership-and-background-work).
Constraint kinds are defined in the [documentation index](../README.md#kinds-of-constraints).

## Layers of a request

| # | Layer | Where | Knows | Down the boundary | Kind |
|---|---|---|---|---|---|
| L0 | transport | `jsonrpc` | bytes, `Content-Length` | `Body` | Boundary |
| L1 | connection | `jsonrpc.Connection` | ids, `CancellationToken` per request | `InboundRequest`, `(method, params)` | Boundary |
| L2 | server | `cjls.server` | lifecycle, handler mode, error codes | `Parts` + raw params | Boundary |
| L3 | route | `Router`, `*Spec` | message types | `Context<P>` / `ReadOnlyContext<P>` | Boundary |
| L4 | handler | `cjls.handlers` | LSP ⇄ loupe translation only | `FileId`, byte offsets, loupe types | Boundary |
| L5 | API | `loupe` | what an editor asks, no LSP | query calls | Boundary |
| L6 | queries | `loupe.syntax`, `loupe.hir` | `@CalcaTracked`, keyed by entities | input reads | Boundary |
| L7 | inputs | `loupe.db`, `loupe.vfs` | files, `SourceFile.text` | — | Boundary |

Above L4/L5: URIs, `Position`, encodings. Below: `FileId`, UTF-8 byte offsets, `TextRange` (D5).
