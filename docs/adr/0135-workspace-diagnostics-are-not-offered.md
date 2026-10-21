# ADR-0135: `workspace/diagnostic` is not offered: a file not open has no diagnostics

Status: accepted, 2026-10-20
Amends ADR-0014: `workspaceDiagnostics: false` is a decision, no longer a gap; closes Q14 (#52)

## Context

- What Q14 waited on is done: semantic diagnostics (#296), the load off the read loop (D61), a question over every file holding no tree past the `lru` (D36, A15). A report's `resultId` is its hash (D131), so `previousResultIds` would need nothing kept.
- One pass over every body of this repository, cold (`DiagnosticsGateTest.thisRepositoryHasNoDiagnostic`: 1 100 files, 3 MB, the load included), takes 15.8 s (Linux x64, a quiet run, 2026-10-16).
- Read from the clients' sources (2026-10-16): VS Code's `vscode-languageclient` asks `workspace/diagnostic` whenever the server declares it, again 2 s after every answer, for ever (`diagnostic.ts`, `pullWorkspace`); Zed the same, and again after every `didChange` (`lsp_store.rs`); Neovim 0.12.6 only on `vim.lsp.buf.workspace_diagnostics()` and on `workspace/diagnostic/refresh`, where it then pulls the workspace *instead of* its buffers, and drops a workspace report of a buffer it pulls (`diagnostic.lua`, `on_refresh`): declared, the server would leave Neovim's open buffers stale after another file changes, D100's bug again. Eglot and lsp-mode never ask it.
- A server answering at once would check the whole workspace every 2 s in VS Code and Zed: ty holds the request until a revision changes when nothing did and streams partial results (`ty.diagnosticMode = "workspace"`, off by default); pyright never answers it, sending only partial results; R1 and tsgo declare `false`.
- No user has asked for the errors of the files not open; `cjpm build` reports them.

## Decision

- **`workspaceDiagnostics: false`**: the diagnostics are those of the documents the client shows (D14, D100).
- Offering it is a change to make when a user asks for it, and its shape is known from the above: a setting off by default with the capability registered dynamically (for Neovim), a request held until the next write when nothing changed (D122's run again), partial results from the first pass, the user's modules' files alone.

## Consequences

- Nothing changes for any client; Q14 is closed.
- A whole-workspace view of the errors is the build's.
