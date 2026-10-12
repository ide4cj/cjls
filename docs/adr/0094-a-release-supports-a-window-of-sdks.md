# ADR-0094: One cjls release supports a window of SDKs: the latest LTS, the latest STS and the pinned nightly, told apart by `cjc --version`

Status: accepted, 2026-10-12
Amends ADR-0087: the token table is one per SDK of the window, not the pin's alone
Amends ADR-0069: a release SDK's sources are `cangjie_runtime` at the tag `v<version>`

## Context

- Cangjie ships three channels ([cangjie-lang.cn/download](https://cangjie-lang.cn/en/download)): LTS `1.0.x` (`1.0.5`, 2026-02-10; its support "to be determined"), STS every half year, each supported six months (`1.2.0`, 2026-09-22; `1.1.x` ends 2026-10-30), and a nightly every day (`1.3.0-alpha.<date>`). `cjc --version` prints `1.0.5`, `1.2.0`, `1.3.0-alpha.20261002001050`.
- Users are on the releases, not the nightly: of pkg.cangjie-lang.cn's 739 packages, 594 name cjc 1.1, 84 1.0, 51 1.2; of `cjc-version` in GitHub's `cjpm.toml`s, ~3100 name 1.0, ~480 1.1. R4 comes with each SDK and its VS Code plugin is versioned as it.
- The cjls binary links no SDK (D21): the toolchain that builds it (D11) never reaches a user. What ties cjls to the user's SDK is what it reads from it: `.cjo` (D37, D38), std's sources (D65, D69), and the macro server (D87).
- Measured: the tests that read the SDK's std (`cjo`, `loupe.vfs`, `loupe.hir`, 335 cases), built on the pin, run with `CANGJIE_HOME` at the release SDKs (Linux x64). On `1.2.0` all pass. On `1.0.5` one fails: 1.0's `.cjo` has no `Constraint.isImplicitlyIntroduced` (1.2 added it), so an `extend` reads with its type's bounds among its own (`anExtendHasTheBoundsItWritesNotThoseOfItsType`).
- Read from cjc's sources at `v1.0.0`, `v1.2.0` and the nightly: every one writes `cjoVersion` 0.1.0; the schema (`ModuleFormat.fbs`, later `CjoFormat.fbs`) only appends fields and enum values; `Attribute`'s first 72 bits are the same. What moves: `TokenKind`'s numbering (`ILLEGAL` 157 at 1.0.0, 159 at 1.2.0, 162 at the pin), while `MacroMsgFormat.fbs` is unchanged since 1.0.0; std's sources are at `std/libs/std` of `cangjie_runtime`'s tag `v1.0.5`, at `stdlib/libs/std` from `v1.2.0` on.
- Rejected: the nightly alone (its users are few); a cjls per SDK, as zls is per Zig (branches and backports for a `.cjo` that reads across them); STS and nightly without LTS (most code on GitHub is 1.0).

## Decision

- **The window is the newest LTS, the newest STS and the pinned nightly**, named in `.cangjie-window`, each with the sha256 of its archives as `.cangjie-sha256` pins the nightly's (D62). A release's notes name it (D21).
- **One release, no branches**: what differs by SDK is data chosen by its version, which `project_model` reads with the SDK (D40) from `cjc --version`: the token table (D87), where std's sources come from (D69). A field an older `.cjo` lacks reads as absent; no code path per version.
- **The analysis follows the pin** (R3 is the pin's cjc): its language and diagnostics, over the std of whichever SDK is found. A rule cjc changed between releases is not told apart by version until an issue asks for it.
- **An SDK out of the window still works**: `.cjo` of the same major is read, macros are off, and the user is told once, with D40's message.
- **cjls is built on the pin alone** (D11); CI runs the tests that read the SDK's std, and the end-to-end tests, on Linux x64 against each SDK of the window. A release SDK comes from cangjie-lang.cn, its stdx from `cangjie_stdx`'s `v<version>.1`.
- **The window moves with Cangjie**: a new STS or LTS replaces the old in one change with its sha256, its token table and its CI job, as a nightly bump moves `.cangjie-version`.

## Consequences

- An LTS user gets what an STS user does, but the bounds of an `extend` of a binary package: those of its type show among its own.
- D87's question of which SDKs expand macros is closed: those of the window, by their table, which the tests check against each one's `std.ast.getTokenKind`.
- CI downloads two more SDKs (about 0.5 GB) on a cache miss, and a red job names the SDK.
- cangjie-lang.cn serves a release by an `objectKey` of its download page, with no published sha256: a key that moves fails the pin, not the build.
- Not yet: what the analysis says that a release's cjc would not (its diagnostics), a `.cjo` of a major other than 0.
