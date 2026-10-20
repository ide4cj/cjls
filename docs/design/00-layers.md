# Layers

The [architecture overview](../architecture.md) explains module responsibilities,
request and edit flow, syntax and macro boundaries. This is the stable L0–L7
reference used by the rules and ADRs; the module manifests define dependencies.

## Layers of a request

| # | Layer | Where | Knows | Down the boundary |
|---|---|---|---|---|
| L0 | transport | `jsonrpc` | bytes, `Content-Length` | `Body` |
| L1 | connection | `jsonrpc.Connection` | ids, `CancellationToken` per request | `InboundRequest`, `(method, params)` |
| L2 | server | `cjls.server` | lifecycle, handler mode, error codes | `Parts` + raw params |
| L3 | route | `Router`, `*Spec` | message types | `Context<P>` / `ReadOnlyContext<P>` |
| L4 | handler | `cjls.handlers` | LSP ⇄ loupe translation only | `FileId`, byte offsets, loupe types |
| L5 | API | `loupe` | what an editor asks, no LSP | query calls |
| L6 | queries | `loupe.syntax`, `loupe.hir` | `@CalcaTracked`, keyed by entities | input reads |
| L7 | inputs | `loupe.db`, `loupe.vfs` | files, `SourceFile.text` | — |

Above L4/L5: URIs, `Position`, encodings. Below: `FileId`, UTF-8 byte offsets, `TextRange` (D5).
