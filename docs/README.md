# cjls docs

| Where | What | Rule |
|---|---|---|
| [architecture.md](architecture.md) | architecture, request/edit flow and code entry points | overview and navigation; detailed constraints stay in the design rules |
| [design/](design/) | living rules | stable IDs, short rule indexes and readable explanations; changed in the same PR as the code they describe |
| [adr/](adr/) | decisions taken | one decision per file, ≤ 1 page; never rewritten, superseded by a new one |
| [issues](https://github.com/ide4cj/cjls/issues?q=is%3Aissue+label%3Aquestion) labeled `question` | open questions | a closed question becomes an ADR or a rule, which names the issue |
| [prior-art.md](prior-art.md) | the servers cjls is measured against, and what comes from which | updated when a reference changes, or a part of cjls starts following one |
| [lsp-extensions.md](lsp-extensions.md) | the methods under `cjls/`, beyond LSP (D15) | changed in the same PR as the method; what a client needs to call it |
| [sdk-issues.md](sdk-issues.md) | SDK defects, evidence and current workarounds | version/platform evidence or explicit uncertainty; probes remain tracked in #332 |

How to set up, build, test and prepare a review: [Development](development.md).
Agent working instructions: [AGENTS.md](../AGENTS.md). How to add a handler: [CONTRIBUTING.md](../CONTRIBUTING.md).

## Current rules and decision history

`design/` holds current constraints; ADRs record their reasons and original context.
An old premise may no longer apply: S6 keeps D6's handler/query boundary, while
D17 and D18 replaced its no-LRU/no-GC premise. Check behavior in source and tests;
reconcile a mismatch with a rule explicitly. A `proposed` ADR is not an accepted
requirement or proof of missing functionality. Record review evidence in the PR
and unresolved work in issues, rather than maintaining a second decision queue.

## Kinds of constraints

The design indexes identify each rule's basis. Every rule still applies within
its stated scope; the kind explains what evidence a revision needs. A rule can
have more than one basis.

| Kind | Meaning | Reconsider when |
|---|---|---|
| Boundary | Ownership, protocol or correctness invariant | A design change preserves the invariant or explicitly replaces it, with tests |
| Design choice | The current decomposition, policy or representation | Alternatives and consequences justify an architectural decision |
| Convention | A consistent way to express code | A repository-wide convention or documented exception is agreed |
| Measured choice | A choice supported by performance evidence | Relevant benchmarks on the identified platform/toolchain support a change |
| Language constraint | Required by language or compiler semantics | The relevant language/toolchain behavior changes and is verified |
| SDK constraint | A workaround or restriction of the supported SDK/runtime | A focused probe on the supported SDK shows the restriction no longer applies |

Kinds do not turn timings into universal guarantees or SDK workarounds into
permanent architecture. Keep measurements and affected versions with their
evidence; keep the current requirement and its exceptions in the rule.

## When a change writes here

Only when it tells the next reader something the docs and the code do not already say. A change that follows the rules written here writes nothing: a new read request along the slice (S1–S6), a new API function of `loupe`, a new query keyed by an entity.

| Writes | When |
|---|---|
| a rule (`design/`) | the change sets a constraint future code must keep, and the compiler does not check it |
| an ADR | there was a real choice: alternatives weighed, one taken, a reason that is not obvious from the code — or a departure from a rule, R1 or R3 |
| a question (an issue labeled `question`) | something is knowingly left undone, and the way to do it is open |
| nothing | the list of what exists (requests served, API functions, fields): that is the code (`handlers/router.cj`, `loupe`'s package) |
| nothing | the story of the PR, its measurements included: the PR description, with the `@Bench` left beside the code; a rule or ADR cites the conclusion and the bench's name |

One fact, one place: a rule is stated once, in `design/`; an ADR says why, AGENTS.md and CONTRIBUTING.md link to both rather than repeat them.

## Design

| File | Topic |
|---|---|
| [00-layers.md](design/00-layers.md) | modules, packages, what each layer knows |
| [01-request-slice.md](design/01-request-slice.md) | one request / notification from the wire down to the inputs, and back |
| [02-analysis.md](design/02-analysis.md) | the database, queries, files, positions |
| [03-conventions.md](design/03-conventions.md) | how code is written, where the compiler leaves a choice |

## Identifiers

| Prefix | What | Defined in |
|---|---|---|
| L# | layer | [00-layers.md](design/00-layers.md) |
| S# | rule of the request slice | [01-request-slice.md](design/01-request-slice.md) |
| A# | rule of the analysis | [02-analysis.md](design/02-analysis.md) |
| C# | code convention | [03-conventions.md](design/03-conventions.md) |
| D# ≡ ADR-NNNN | decision | [adr/](adr/) |
| K# | SDK issue | [sdk-issues.md](sdk-issues.md) |
| #N | open question | its issue; an old `Q#` (in the ADRs) is found by searching the issues for it |
| R# | reference implementation | [prior-art.md](prior-art.md) |

Ids are never reused. A rule dropped keeps its number, struck through; a closed question is a closed issue, and the ADR or rule that closes it names it.
