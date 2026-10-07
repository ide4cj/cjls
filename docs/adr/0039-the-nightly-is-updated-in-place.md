# ADR-0039: The nightly is the pre-release `nightly-build`, made once and updated in place; immutable releases are off

Status: accepted, 2026-10-03. Supersedes D32's tag `nightly` and its release deleted and made again every night.
Amends ADR-0032: the nightly's tag `nightly-build`, updated in place

## Context

D32's `nightly.yml` deleted the release `nightly` and made it again. Immutable releases were on in this repository: the first nightly (2026-10-02) was published immutable, the next night deleted it, and the new one was refused (`HTTP 422`, "tag_name was used by an immutable release"). GitHub never lets a tag an immutable release had be made again, whether immutable releases are on or off since; `nightly` is lost here. A rolling release cannot be immutable at all: its tag moves, its assets change. rust-analyzer, Neovim and WezTerm roll a `nightly`, Ghostty a `tip`, Bun a `canary` updated in place since 2022, all with immutable releases off; clangd makes a dated `snapshot_*` each time; ruff, deno and oxc, immutable, keep no nightly among their releases.

## Decision

- **The tag is `nightly-build`**, and a client's setting names it as any tag (`vim.g.cjls_version = 'nightly-build'`, Zed's `version`): no word is mapped to it, as `nightly` finds nothing anyway. Not `Nightly`: a case-insensitive filesystem folds it into a clone's stale `nightly`.
- **Made once, updated in place, never deleted**: the assets replaced by name (their names never change), the tag moved, the notes edited. A deletion is the only way a tag can be lost.
- **Immutable releases are off** in this repository. Turning them on again for `v*` takes a nightly that does not roll (a dated tag each night as clangd's, a client taking the newest): a new ADR.

## Consequences

- A user following the nightly sets `nightly-build` in place of `nightly`; `ide4cj/.github/actions/cjls`, `cangjie.nvim`, `cangjie-vscode` and `cangjie-zed` name it, by a paired branch (D32).
- `v0.1.0` and `v0.2.0` stay immutable; the releases after them are not.
- Deleting `nightly-build` by hand while immutable releases are on would lose this name as well.
