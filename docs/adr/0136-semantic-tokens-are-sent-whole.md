# ADR-0136: Semantic tokens are sent whole: no full/delta

Status: proposed
Closes Q19 (#56): ADR-0019's `full` and `range` stay, without `full/delta`

## Context

- `full/delta` answers with the edits from the tokens a `previousResultId` names to the new ones, so the server keeps each document's last tokens. A hash does not do, as it does for diagnostics (D131): the edits need the old tokens themselves, and calca keeps no old revision to compute them again.
- rust-analyzer and clangd keep them in a cache beside the analysis, under a mutex, one entry a document, cleared by `didClose`. Here that is a `readonly` handler writing state, a departure from S2, and a cancelled or rerun handler (D122) overwriting an entry the client never got.
- What it saves is what comes after the tokens are known: the answer's JSON, the pipe, the client's parse. `SemanticTokensBench` takes a keystroke apart on `nodes.cj` (6.6 thousand lines, 16 thousand tokens, every body inferred): `highlight` after an edit about 200 ms, encoding the tokens about 16 ms, writing the answer about 5.5 ms, a delta's hash, diff and write about 0.2 ms. The `tokens` scenario's `response_kb` is about 170 KB a keystroke on a 5000-line file.

## Decision

- **`full` sends every token, every time; no `full/delta`, no cache of what was sent.** It would save under 3% of the server's time a keystroke, at the cost of state a `readonly` handler writes and its races.

## Consequences

- A large file's keystroke costs its `highlight`: making that cheaper (ADR-0019's `@CalcaTracked` over `SourceFile`), and the encoding, is where a keystroke's tokens get faster.
- To be weighed again if `highlight` becomes incremental and the answer's size is what is left, or a client is shown to spend on parsing it; `SemanticTokensBench` and `response_kb` measure both sides.
