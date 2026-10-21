# ADR-0084: What a name means is kept where it was resolved, not resolved again by what reads it

Status: accepted, 2026-10-20
Amends ADR-0072: semantic tokens read what inference and lowering resolved; `lookUp` is a query

## Context

- D72 as first written made semantic tokens ~9× slower than D19's tree (`nodes.cj`, a keystroke 50 → 451 ms): `classifyName` resolved every name again — `resolveBodyName`, `resolveField` and `resolveTypePath` per token, each reading the package's declarations and the file's imports — though inference and the lowering of types had resolved each already.
- R1's `InferenceResult` keeps `method_resolutions`, `field_resolutions`, `variant_resolutions`, `assoc_resolutions` by `ExprId`, and `SourceAnalyzer::resolve_path` reads them first (`hir/src/source_analyzer.rs`). R1 too highlights the whole file for every `full` and `full/delta` request (`handlers/request.rs`); `delta` saves only the bytes sent.
- A new revision verifies every memo a file's highlighting read: ~14 000 memos and ~120 000 edges on `nodes.cj`, two thirds of them `inferBody`'s (~74 dependencies a body).

## Decision

- **Inference keeps what it resolved**: each name a body uses as a value (`InferenceResult.names`) and the name after each `.` (`accesses`), resolved once whatever overload it tries; the lowering of a signature's or a body's types each path's segments (`SignatureTypes.pathOf`, `InferenceResult.typePathOf`). `classifyName` reads them, and resolves again only what they lack. Each is sorted by its id and bisected, as `calleeOf` and `fieldOf` now are.
- **`lookUp` is a query**: what a name means in a file's scope is read once a revision, and a declaration added to the package runs again only what read a name whose answer it changed.
- **A memo verified in this revision answers a dependent at once** (`MemoTable.maybeChangedAfter`), without the cast, the claim and the tuples the shared generic code made a type of at run time on every edge.
- A body's source map finds a node's expression, pattern, local or type by hash; `SyntaxNodePtr.tryToNode` bisects each level's children instead of making a node of each.

## Consequences

- `tests/perf`'s `tokens` scenario (a declaration typed at the end of a file of this repository at cb2869d; master before D72, D72 as first written, and with this; three runs each, interleaved, on a 16-thread box at load below 1.5): `infer.cj` (90 KB, the 99th percentile of the sources) first tokens 34 → 637 → 644 ms, a keystroke p50 24 → 171 → 106 ms, p95 34 → 300 → 245 ms; `nodes.cj` (170 KB, generated) 72 → 936 → 743 ms, 50 → 451 → 254 ms, 69 → 785 → 339 ms, peak RSS 289 → 341 → 337 MB. Typed inside a body instead, a keystroke p50 is 24 → 169 → 97 ms and 49 → 447 → 252 ms. R4 on the same files: 515 ms and 2985 ms first, 439 ms and 3008 ms a keystroke, 1170 MB on `nodes.cj`.
- `HighlightBench` (`nodes.cj` in `ginkgo` and `cjsyntax`, std's `core` and `collection`): 129.5 → 43.0 ms ±5% its bodies inferred, 365 → 209 ms ±0.6% after a space added in its last body.
- What remains is a new revision's floor: the file parsed again (~25 ms), every body and signature of it lowered again (D50's source maps point into the tree, ~20 ms), and the edges verified (~0.9 µs each). Lowering from an item's own node with source maps relative to it (an edit −12%, +10 ms a revision without one) and a memo of each item's tokens (an edit 250 → 305 ms) were measured and do not pay for themselves.
- A body's `InferenceResult` and a signature's `SignatureTypes` are larger by what they keep: peak RSS on `nodes.cj` is back to D72's first.
