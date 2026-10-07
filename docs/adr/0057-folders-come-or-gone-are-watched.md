# ADR-0057: Everything come or gone under a root is watched, as VS Code reports a folder as one event; the server tells a directory of the workspace from the rest

Status: accepted, 2026-10-08
Amends ADR-0030: what is watched, and which event finds the project again

## Context

- The server watched `**/*.cj` and the manifests (D30, D33). VS Code reports a folder created, deleted, moved or renamed as one event for the folder, not one per file under it ([microsoft/vscode#110923](https://github.com/microsoft/vscode/issues/110923)): `…/src/a` matches no `*.cj` glob, so the client dropped it. A folder deleted stayed in the VFS until a restart; one moved in was not loaded (#94).
- Neovim 0.12 (`vim/lsp/_watchfiles.lua`) honours `kind` and sends a path once, whatever watchers it matches; Zed (`lsp_store.rs`) ignores `kind` and matches one glob set, a path once too. VS Code's client runs a watcher per glob, so a path two globs match comes twice.
- A directory has no glob of its own (`**/` means nothing in LSP), so a watcher wide enough for one sees every file come or gone: cjpm's output, `.git`. Every `Created` or `Deleted` found the project again (D33), which walks the roots.
- rust-analyzer watches `**/*.rs` alone and lives with the same gap.

## Decision

- **Each root's registration watches `**/*` for `Create | Delete`, and `**/*.cj`, `cjpm.toml`, `cj-project.json` for `Change`**: no path is watched for one kind twice, so VS Code sends it once.
- **A non-`.cj` path come or gone finds the project again only if the walk goes into it** (`loupe.vfs.isWorkspaceDirectory`: under a root, through no `target` or hidden directory), and, if come, it is a directory on disk, not a link; a path gone cannot be told a directory, so one the walk would go into counts. A manifest or a `.cj` does as before.
- **A directory come is read by the project found again**, which walks the disk; a directory gone takes its known files, as D30. Rejected: walking the directory on its own (`readRoots` under the budget) — the load already reads every file of the project the server does not know.

## Consequences

- A client that ignores `kind` (Zed) also reports every file changed under a root; such an event is dropped unread.
- A file come under a root through scanned directories (a `README.md`) is taken for a directory only if one is on disk: it finds no project again. One gone (`rm notes.md`) does.
- Without dynamic registration nothing is watched still (D30).
