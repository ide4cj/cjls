# ADR-0132: A client's version is the major and minor of the cjls release it pins, with a patch of its own

Status: accepted, 2026-10-16. Amends ADR-0032: a client's version, the VS Code channels' minors.

## Context

- D32 ties each client to cjls by its pin and leaves the version to the client: on cjls `v0.5.0`, Zed was `0.2.0` (`cog bump --auto` from its own commits), VS Code `0.4.0` (the same, its minor made even, the nightly on the odd minor above: `0.5.20261016`), Neovim untagged. A client's version said nothing of the server it runs, and Zed released only when a new cjls minor moved its pin, so two `feat`s waited on master.
- VS Code's even/odd minors are the Marketplace's recommendation for two channels, not a rule: `vsce` refuses a semver pre-release (`0.5.0-nightly`, `publish.js`), and reads no parity. A user on the pre-release channel is given the highest version of the two.
- Everything is `0.*`: "stable" is the channel of the pinned release, not a promise.
- tinymist ships its server and extension as one version from one repository; rust-analyzer's extension is `0.3.<build>`, apart from the server's; ruff-vscode has its own. cjls's clients are repositories of their own (D16), each released after a bot moves its pin (D32), and some changes are the client's alone.

## Decision

- **A client's release is `<the pinned cjls's major>.<its minor>.<a patch of its own>`**: a pin on a newer minor than the client's last release starts it at `.0`; on the same minor the patch goes up by one, for a cjls patch or the client's own change. A pin older than the last release fails the release. `ide4cj/.github/actions/client-version` computes it, for every client's `bump.yml`; `cog` keeps checking the commits, deciding whether there is anything to release, and writing the changelog.
- **VS Code's pre-release is `<the stable minor + 1>.<date>`**, above every stable release until the next minor's; the even/odd minors go.
- **Neovim is tagged too**, by a `bump.yml` of its own once the pin in `lua/cangjie/install.lua` moves.
- The first release of each client after this jumps to the pin's minor (`0.5.0`): none is published to a marketplace or Zed's registry yet.

## Consequences

- `0.5.x` of any client runs cjls `0.5`; Zed's extension, which downloads the newest cjls of its minor, matches its own version by construction.
- Every cjls release is a release of each client, and Zed's registry gets a PR per release, about weekly, rather than per minor as D32 had it.
- A client's own fix goes out as a patch on the current minor without waiting for cjls; a client's `feat` does not move its minor.
