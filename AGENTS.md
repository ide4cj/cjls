# Working on cjls

cjls is a Cangjie language server, written in Cangjie. `cjls` handles LSP;
`loupe` provides incremental analysis on `calca` without knowing LSP. Discover
current features in the router and source, rather than assuming an old overview
is a complete feature list.

## Working agreement

- Respond in the user's language. Keep code, comments, commits and PR text English.
- Explain the intended scope and verification before editing. For architectural
  choices, present the tradeoffs and wait for the maintainer's decision; then
  complete the agreed change. Discuss material scope changes before proceeding.
- Work in small, reviewable steps. Explain the core algorithm and why the tests
  support it so the maintainer can learn through review.
- Treat questions and investigations as such; do not resume old work or publish
  changes merely because the user asks about them. External writes, commits,
  pushes and merges must stay within the user's explicitly requested scope.
- Use a separate Git worktree for implementation. Keep its scratch files and
  build outputs there. Coordinate changes to shared docs; do not delete another
  session's worktree. Cleanup follows review/merge and an explicit activity check.
- Check unfamiliar Cangjie/compiler behavior in source or a small probe. State
  what was verified and what remains uncertain. Report changed behavior, checks
  run and limitations at the end; do not claim unrun checks passed.

## Start here

| Task | Read |
|---|---|
| Set up a machine, build, test, inspect coverage or troubleshoot | [Development](docs/development.md) |
| Find subsystem boundaries and code entry points | [Layers](docs/design/00-layers.md) |
| Add/change a handler, cancellation or document synchronization | [Contributing](CONTRIBUTING.md), [request slice](docs/design/01-request-slice.md) |
| Change analysis, queries, positions or diagnostics | [Analysis rules](docs/design/02-analysis.md) |
| Write or review Cangjie code | [Conventions](docs/design/03-conventions.md) |
| Change grammar, generators, macros or platform code | The affected `modules/<name>/CLAUDE.md`, if present, plus its referenced rules |
| Understand a choice or record a new constraint | [Docs index](docs/README.md), [ADRs](docs/adr/README.md), [prior art](docs/prior-art.md) |

Module `CLAUDE.md` files are transitional technical notes: read the affected
module's note before changing it. They are not automatically discovered Codex
instructions. Do not load all module notes or ADRs for every task. Documentation
migration is tracked in [#455](https://github.com/ide4cj/cjls/issues/455).

## Essential boundaries

- stdout is the LSP wire; diagnostics/logging go through the supplied logger,
  never a global logger. Wire structures use `@Serde[skipNone]`; absent fields
  and JSON `null` are distinct ([codec notes](modules/stdxx/CLAUDE.md)).
- Handlers translate; analysis belongs in `loupe`. Read handlers use their snapshot
  for all data, including text for positions. A read-loop handler changes inputs
  and never runs a query or awaits an outbound request (S1–S3, S10).
- Every `spawn` boundary catches `Error` as well as `Exception` (S13).
- Platform differences belong in `platform` source sets; follow C17 for exceptions.
- Generated files are changed through their inputs and generator. Macro output
  must be checked by building/testing a package using it.
- Preserve the static linking, optimization and compiler workarounds described
  in [Development](docs/development.md#toolchain-constraints); changing one requires
  evidence on the relevant SDK/platform.

## Verification and documentation

Run the focused check that exercises a change, then the broader required checks
for its scope; use the commands and prerequisites in Development. A bug fix needs
a regression case that demonstrates the failure. Concurrency tests coordinate
events deterministically (C13); performance claims use benchmarks on a quiet,
identified machine (C10).

Keep current constraints in `docs/design/` and reasons in ADRs. Preserve rule IDs
and historical decisions; add documentation when behavior or a constraint changes,
not an inventory of functions. Start an ADR with `python3 scripts/docs.py new-adr`;
the ADR index is generated after merge, not edited in a PR (D56). Code, tests and
the documents they invalidate change together. Do not redesign test tiers or
generator workflows as an incidental documentation cleanup.
