# ADR-0068: The `.cjo` of the binaries are watched from the directories they are in, by a registration of their own, and an event on one finds the project again

Status: accepted, 2026-10-09
Amends ADR-0038: what starts a read of the `.cjo`

## Context

- D38 reads the `.cjo` of `std` and of the `bin-dependencies` with each load, again only those whose size or mtime moved; but nothing started a load when they moved. The roots' watchers (D58) see nothing outside the roots, where the SDK is: a new nightly, or a stdx rebuilt, was seen at a manifest's change or a restart (#141).
- A binary is directories of `.cjo` (`path-option`, the SDK's `std`), every one in each read, and `.cjo` named one by one (`package-option`); a project found again may name others.
- An SDK updated in place replaces the directory as a whole (an archive extracted anew), which VS Code reports as one event for the directory, as D58 has it for a folder under a root; a watcher whose base is the directory replaced is not certain to survive it.
- A pattern outside the workspace is LSP 3.17's `RelativePattern` with a `baseUri` (`relativePatternSupport`). A plain glob is matched only under the workspace folders: Neovim 0.12 (`vim/lsp/_watchfiles.lua`) watches each folder for it, and watches any `baseUri` of a relative pattern recursively.

## Decision

- **A registration of the binaries' own**, beside the roots' (D58), made when a load sets a project whose binaries' directories and named files are not those watched already; the new one is registered first, then the one before unregistered, so no event falls between them.
- **Each watched from the directory it is in**: a directory `d` of a binary as `<d's name>` come or gone and `<d's name>/*.cjo` created, changed or deleted, relative to `d`'s parent; a named `.cjo` as its name, relative to its directory. An event on any is a load, which reads only the `.cjo` whose stamps moved (D38, D61). Rejected: `**/*.cjo` under the SDK (cjc reads no subdirectory of a binary's), a watcher per file read (a package come is missed), and `d` as the base (its watcher need not outlive it replaced).
- **Without relative patterns, globs of the paths**, as the roots' (D30): a client that matches globs under its folders alone sees a binary under one of them, the SDK not. Rejected: registering nothing (a binary inside the workspace would be missed for no gain).
- **An event is the binaries' by the paths of the project set**, not by the registration: a client that registered nothing and reports one anyway is followed.

## Consequences

- A new nightly, a stdx rebuilt, a `bin-dependencies` built anew are read without a restart, by a client that takes relative patterns (Neovim and Zed say so, `tests/e2e`'s captures).
- An SDK replaced higher up than a binary's directory's parent (the whole `CANGJIE_HOME`, cjsdk's `default` link pointed elsewhere) is seen only if the client's watcher outlives its base, or at the next load.
- A client may watch a binary's directory's parent recursively (Neovim does any `baseUri`): for `std` that is `modules/<target>`, the SDK's `.cjo` and `.bc` alone.
