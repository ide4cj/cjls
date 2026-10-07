# ADR-0032: The server and its editor clients change by one process: the protocol their contract, paired branches, two channels, pins bumped by a bot

Status: accepted, 2026-09-29. Closes #89; supersedes D16's "a change is two pull requests, the server's first" and "this repository's CI runs the plugin's smoke test" (D11's too), and D21's "no nightly yet".
Amends ADR-0011: no editor's tests in CI
Amends ADR-0016: how server and clients change together, and who tests which
Amends ADR-0021: a nightly

## Context

D16 puts each editor client in a repository of its own; after `cangjie.nvim` come [`cangjie-vscode`](https://github.com/ide4cj/cangjie-vscode) and [`cangjie-zed`](https://github.com/ide4cj/cangjie-zed). A change across a server and a client had no way through CI: this repository ran the plugin's `main`, so a server PR changing the contract was red until the plugin's was merged, which had nothing to run against until a release. No client could follow master (D21: no nightly), a pin moved by hand, labels were GitHub's defaults. R1 keeps its VS Code client in-tree and has no workflow for the others; gopls/vscode-go generate the client's settings from the server's; tinymist and ruff publish nightlies; Zed publishes an extension by a reviewed PR, too slowly for a release per server release.

## Decision

- **Thin clients** (D15): a client finds or ships the binary, passes settings, and gives the server's extensions their UI; highlighting of its own only until semantic tokens (D19) cover it.
- **The contract is the protocol.** `docs/lsp-extensions.md` carries the hash of `cjls.lsp_ext` on its first line, and `LspExtensionsDocTest` fails until it moves, as R1's does. A client gates on `experimental` capabilities, never on a version; it supports the server's minor and the one before; a deprecated extension or setting stays two releases. The settings' JSON Schema will come from the server (`cjls --config-schema`) with its first setting, and the clients' settings be generated from it; there is none yet.
- **Each side tests its own.** This CI holds the server to the protocol: `tests/e2e` over stdio with each editor's captured capabilities, and a client's failure that is the server's becomes a case there (C7). It runs no client: that would make a server PR's green hang on every client's default branch, its flakes and its toolchain, and check a pair the client's CI already checks.
- **Paired branches.** A change across repositories is one branch name in each: a client's CI takes this repository's build of its branch name when there is one, else `nightly`, and its pin (`ide4cj/.github/actions/cjls`). The server merges first, behind its capability.
- **Two channels.** cjls: `nightly`, a rolling pre-release of master's newest commit CI passed on, every night (`nightly.yml`), beside the Monday release (D21). VS Code: platform VSIXes with the binary inside, stable on an even minor with the pinned release, pre-release on an odd minor with the nightly; Neovim: the pin, or `vim.g.cjls_version = 'nightly'`; Zed: the newest release within the extension's minor, the pin otherwise, `nightly` by a setting.
- **Pins bumped by a bot**: Renovate's `customManagers` over each client's pin (`github-releases`, Mondays after the train); the client releases once that PR is merged. Each client's CI also runs every day against `nightly` and the editor's own nightly, and a failure opens an issue.
- **One organization.** `ide4cj/.github` holds the issue forms (editor, client, `cjls` version, OS, the server's log), `labels.yml` synced to every repository (`A-`, `S-`, `E-`, `client:`), and the shared actions; an issue's kind is its type (Bug, Feature, Task), the organization's, not a label (#89 proposed `C-` labels as R1 has them; GitHub's types are one field the board and the forms know). The release train pushes with an app's token (`RELEASE_APP_ID`, `RELEASE_APP_KEY`) in the ruleset's bypass list, the person's `RELEASE_TOKEN` until it is installed. Work across repositories is a parent issue here with sub-issues in the clients, on the board.

## Consequences

- A server PR and its client PR are green together, on the client's CI, before either merges; this CI is green whatever the clients' branches are.
- A server change no client paired breaks a client at the latest in that client's daily run against `nightly`, before the Monday release.
- A client release follows a server release by the merge of one bot PR; Zed's registry PR only on a new minor.
- A change to `cjls.lsp_ext` without its doc fails `cjpm test`.
- The nightly binary reports its sources' version; its release notes name the commit.
- Still open: Zed's capabilities as an e2e fixture in `tests/e2e`; `ide4cj/setup-cangjie`; Discussions, `CODEOWNERS` and a triage rotation when outside requests come.
