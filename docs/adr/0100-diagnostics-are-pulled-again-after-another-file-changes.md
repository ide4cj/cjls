# ADR-0100: Diagnostics depend on other files: pulled again after any change

Status: accepted, 2026-10-12
Amends ADR-0014: `interFileDependencies: true`; `workspace/diagnostic/refresh` is sent

## Context

- D14 advertised `interFileDependencies: false` while a file's diagnostics were its own syntax errors. Since then imports (D46), `@When` (D93) and inference (D90) report what other files declare: an import of `loupe.db.{AnalysisDatabase}` is "not accessible" while `db.cj` is being edited and the class is, for a moment, renamed or not `public`.
- Neovim 0.12.5 pulls a buffer's diagnostics again after its own `didChange` alone, and all of them on `workspace/diagnostic/refresh` (`vim/lsp/diagnostic.lua`); VS Code pulls the open documents again after a change of any when the server declares `interFileDependencies`. The error above stayed in the importing buffer after `db.cj` was put back, until that buffer was edited. The push path (D14) already publishes every open document after a change.
- R1 declares `inter_file_dependencies: true` and sends `DiagnosticRefreshRequest` beside `SemanticTokensRefreshRequest` after a change of the state (`main_loop.rs`, `became_quiescent || state_changed`).

## Decision

- **`interFileDependencies: true`.**
- **`workspace/diagnostic/refresh`**, as R1 and as D72's tokens: after a write that changed the files, if the client declared `workspace.diagnostics.refreshSupport`.

## Consequences

- Every change pulls the diagnostics of every document the client shows: each a query of the bodies of its file, memoized, of which a change of another file re-checks what it read.
- No `resultId` yet (Q13): an unchanged document's report is sent whole again.
