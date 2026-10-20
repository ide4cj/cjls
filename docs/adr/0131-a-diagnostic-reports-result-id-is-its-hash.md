# ADR-0131: A diagnostic report's resultId is a hash of its items and of the openings so far

Status: accepted, 2026-10-20
Amends ADR-0014: a pull answers `unchanged` when the client's `previousResultId` is the report's; closes Q13 (#51) for `textDocument/diagnostic`

## Context

- Since D100 every change pulls the diagnostics of every document the client shows, and each was sent whole again, unchanged or not (Q13). `unchanged` spares the wire and the client's redrawing; it says the last report is still accurate *with its ranges*: the client keeps the `Diagnostic`s it has, at their old positions (Sublime redraws them there after an edit).
- A `readonly` handler writes nothing (S1, S2), so no id can be kept per document by the handler.
- Read from the servers' sources (2026-10-16): R1 sends the constant `"rust-analyzer"` and never `unchanged`; gopls, typescript-go, sourcekit-lsp, ruff send none; pyright counts recomputations per file (state); Roslyn keeps the last id with a project version and a checksum of the result (state); ty hashes the diagnostics and compares with what the client sent, keeping nothing. cjc's LSPServer only pushes.
- Clients (VS Code's `vscode-languageclient` 10, Neovim 0.12, Zed, Helix, Sublime, Eglot) send the id they hold. Neovim keeps it over `didClose`/`didOpen` (`:e!`, a rename) while clearing the buffer's diagnostics: ty answers `unchanged` there and the buffer shows nothing until the next edit (ty#3010). Eglot keeps sending the id of the last full report, never the one an `unchanged` brought.

## Decision

- **`resultId` is a hash of the report's items as the client gets them** (their JSON, positions in the agreed columns), as ty's: nothing is kept between requests, and an id equal to the client's `previousResultId` is answered `unchanged`. A moved diagnostic is a new id.
- **The openings so far are part of it** (`ServerState.openings`, counted by `didOpen`): an id from before any `didOpen` never matches after it, so a reopened buffer gets its report whole. One counter for the server, not one per document: an opening costs every document one full report, and the snapshot copies no map.

## Consequences

- A pull of a document whose diagnostics did not move answers `unchanged`; the diagnostics are still computed (memoized, A11) and serialized once more for the hash.
- Eglot's id stays valid as long as the report is the same, since the hash of the same items is the same.
- Not here: `workspace/diagnostic` (Q14) and `semanticTokens/full/delta`, which needs the previous tokens themselves (D19).
