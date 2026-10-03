# `loupe` — the analysis, and the request slice through it

The analysis, knowing no LSP ([D5](../../docs/adr/0005-loupe-knows-no-lsp.md)): `loupe.vfs` (`FileId`, `VfsPath`, `PathInterner`, `Vfs`, and the disk: `readRoots`, `readFile`, `readBinaries`), `loupe.db` (`@CalcaInput SourceFile`, the project model and its inputs `Project`/`Module`/`Package`, the `.cjo` of the binaries as `BinaryPackageFile`s, `AnalysisDatabase`), `loupe.syntax` (the `parse` query), `loupe.hir` (`itemIdMap`, `itemTree`: a file's items, by ids edits elsewhere leave alone; `binaryItemTrees`: a `.cjo`'s, D38), and the API in `loupe` (`fileStructure`, `diagnostics`, `highlight`, `workspaceSymbols` through the `fileSymbols` index; `TextRange`, the API's ranges, is re-exported from `ginkgo`). Depends on `calca`, `cjo`, `cjsyntax`, `ginkgo`, `index_map`, `rope`. See [02-analysis.md](../../docs/design/02-analysis.md).

The rules are in `docs/design/`, not here: the layers and what each knows ([00-layers.md](../../docs/design/00-layers.md)), one request from the wire to the inputs and back, cancellation included ([01-request-slice.md](../../docs/design/01-request-slice.md)), the database, queries, files and positions ([02-analysis.md](../../docs/design/02-analysis.md)). What is easy to get wrong:

- A `Context` handler only changes inputs, never queries; a `readonly` one reads everything from its snapshot, text for positions included (S1, S2).
- Handlers only translate (`handlers/from_proto.cj`, `handlers/to_proto.cj`); logic goes to `loupe`, which knows no LSP (S3, A8).
- Diagnostics are in the queries' results (`Parse.errors`), never accumulated (A11); `loupe.diagnostics` only collects and sorts them. A client that pulls is never pushed to (S8).
- Queries take `AnalysisDatabase` itself (A1), are keyed by entities, never positions (A2), and return `Equatable` values (A10).
- Lines break at `\n` only; offsets are UTF-8 bytes on character boundaries (A6, A7).
- `ServerState` owns the `Vfs`, the open documents, the negotiated `Encoding` and the `AnalysisDatabase` as `analysis`; a `ServerSnapshot` holds a snapshot of it, cancelled by the request's token (D8). Neither is a database itself: the two types keep a `readonly` handler from writing at compile time.
