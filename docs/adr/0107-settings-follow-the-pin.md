# ADR-0107: A client's settings are made again when its pin moves, never checked against the cjls under test

Status: proposed
Amends ADR-0079 and ADR-0032: a client declares the settings of its pin, written by a bot in the PR that moves it; no CI fails on settings that differ

## Context

- D79 has the clients generate their settings from `cjls --config-schema`; each client's CI checked them equal to those of the cjls its `pin` job ran. D32's paired branch makes that cjls the pair's build, not the pin: a pair whose cjls branch is on a master with a setting the pin lacks (`newFilePackage`, after v0.5.0) fails the check in every client (`ide4cj/cangjie-vscode#15`), whatever the pair changes.
- Neither way out holds: skipping the check in a pair lets settings of an unreleased cjls reach the client's master, red at its next run against the pin; a `pin` job without the pair's build tests the client against a server without the change it pairs (D32: a pair is tested against its head's build).
- An exact check needs one server: R1's `generate_package_json_config` writes `editors/code/package.json` in `cargo test`, client and server one commit. vscode-go, a repository of its own like D16's, writes gopls's settings by hand (`tools/generate.go -gopls`, from the gopls on `PATH`), checks them in no CI, and declares the section `gopls` with `additionalProperties: true` (checked at its master of 2026-10).
- D32 already has a client support the server's minor and the one before, and D79's server leaves keys it does not know alone: a setting declared and not known, or known and not declared, breaks nothing.

## Decision

- **A client declares the settings of its pin**, written in the PR that moves the pin, Renovate's (D32), by `ide4cj/.github/actions/settings`: the pin's release downloaded whatever the branch, the client's own generator run, a commit pushed to the PR when they differ, with the organization's app so the checks run again. Renovate ignores the commit (`gitIgnoredAuthors`).
- **No CI checks them** against the cjls it tests; the generators keep `--check` for a hand.
- A pair may declare a setting before the pin has it; the next pin's PR writes them all again.

## Consequences

- A setting of master reaches a client's users with the release that has it, by a bot's commit, with no PR of its own.
- A setting renamed or removed is declared until the pin moves: the user's value is a key the server leaves alone.
- A client whose pin moves by hand runs its generator itself.
