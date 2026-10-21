# Working on cjls

cjls is a Cangjie language server, written in Cangjie. `cjls` handles LSP;
`loupe` provides incremental analysis on `calca` without knowing LSP. Discover
current features in the router and source, rather than assuming an old overview
is a complete feature list.

## Before changing code

- Read the task-relevant documents below and the affected module's notes.
- Preserve the architectural boundaries and toolchain constraints they describe.
- Check unfamiliar Cangjie/compiler behavior in source or a small probe.
- Run checks appropriate to the change and report their results, including
  limitations and assumptions that have not been verified.

## Start here

| Task | Read |
|---|---|
| Set up a machine, build, test, inspect coverage or troubleshoot | [Development](docs/development.md) |
| Find architecture and code entry points | [Architecture](docs/architecture.md) |
| Find design rules and code conventions | [Documentation index](docs/README.md) |
| Check an SDK defect or workaround | [SDK issues](docs/sdk-issues.md) |
| Add or change a handler | [Contributing](CONTRIBUTING.md) |
| Understand a design choice | [ADRs](docs/adr/README.md), [prior art](docs/prior-art.md) |

Read the affected module's instructions and technical notes before editing it.
Follow links relevant to the task; do not load all module notes or ADRs for every
change.

## Issues and board

When creating or triaging an issue, follow
[the organization's process](https://github.com/ide4cj/.github/blob/master/CONTRIBUTING.md#issues-and-labels).
Set its GitHub issue type (Bug, Feature or Task) and relevant `A-` or `client:`
labels. Add it to [the board](https://github.com/orgs/ide4cj/projects/1) and set
Priority and Status in the same operation; new issues start in Backlog. Read
the current priority definitions and goal in the shared process rather than
relying on remembered milestones. Verify the saved issue and board fields
before reporting completion; automatic board enrollment does not fill them.
The p2cj repository is outside this board's scope.

## Essential boundaries

- stdout is the LSP wire; diagnostics/logging go through the supplied logger,
  never a global logger. Wire structures use `@Serde[skipNone]`; absent fields
  and JSON `null` are distinct.
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

Keep current constraints in the design documents listed by the documentation
index and reasons in ADRs. Preserve rule IDs and historical decisions; add
documentation when behavior or a constraint changes,
not an inventory of functions. Start an ADR with `python3 scripts/docs.py new-adr`;
the ADR index is generated after merge, not edited in a PR (D56). Code, tests and
the documents they invalidate change together.
