# loupe documentation migration pilot

This records package B of [#455](https://github.com/ide4cj/cjls/issues/455), based
on the module note present after package A (`965e879`). It validates the format
before package E migrates the remaining module groups. It does not mark those
modules or the final scenario acceptance complete.

## Preservation decisions

| Previous content in `modules/loupe/CLAUDE.md` | Destination or removal reason |
|---|---|
| Analysis knows no LSP; dependency and package direction | [Architecture: boundaries](../architecture.md#modules-and-boundaries), [analysis](../architecture.md#analysis-and-incremental-state), A8 and D5. Exact dependencies remain in the module manifest. |
| VFS, database, syntax, HIR and API inventories | Replaced by the architecture's conceptual explanation and [source entry points](../architecture.md#source-entry-points). Current symbols and signatures are source-owned; no hand-maintained catalog is retained. |
| Conditional items (`@When`, D93), common/specific source sets (D99) | A33–A34 retain the constraints. Source entry points lead to the HIR package and project model; the ADRs retain the rationale. |
| Binary item trees, exports, scopes, signatures, bodies, members, hierarchy and inference inventories (D38, D45–D57, D63–D66, D112, D128) | Symbol lists removed in favor of HIR source links; the dependency, identity and inference constraints remain in A18–A30 and A36. Historical decisions remain in the ADR archive. |
| Built-in and server macro expansion, call keys, spans and nested calls (D82, D98, D103, D117–D119, D123) | [Architecture: macros](../architecture.md#macros-and-protocol-isolation), A31 and A35, and source entry points. API function lists removed; exact expansion behavior remains in the rules and ADRs. |
| Completion and reference API inventories (D111, D130), other API feature lists | Removed as implementation inventories. The API source directory and router show current features; neighboring tests show behavior. ADRs are retained. |
| Fixture library not linked into a binary (D43) | [Analysis tests](02-analysis.md#analysis-tests). |
| Context vs read-only handlers, conversion-only boundary (S1–S3, A8) | [Request slice](01-request-slice.md) and architecture request flow; no second local copy. |
| Query keys, concrete database, equatable results (A1, A2, A10) | [Analysis rules](02-analysis.md). |
| Diagnostics as result values and collection/sorting, pull/push exclusivity (A11, A32, S8) | Analysis overview and A11/A32; request slice S8. |
| UTF-8 offsets and line endings (A6, A7) | Analysis rules, IDs unchanged. |
| `.cjo` bytes outside VFS; do not retain borrowed `cjo.Decl` in tracked results | [Architecture: analysis](../architecture.md#analysis-and-incremental-state), with D38 retained. |
| SDK std bytes needed by HIR/VFS tests; std sources at the nightly's runtime commit for navigation tests | [Analysis tests](02-analysis.md#analysis-tests), linking the actual fixture helpers and canonical development prerequisites. |
| ServerState/ServerSnapshot ownership, compile-time read context separation, token cancellation (D8) | [Architecture: request and edit](../architecture.md#a-read-request-and-an-edit), request slice. |
| Links to layer/request/analysis documents and ADR rationale | Module README links the architecture and current rules; original ADRs remain unchanged. |

`modules/loupe/README.md` is a navigation page for humans and agents. There is no
local `AGENTS.md`: the pilot found no extra working instructions beyond the root
policy and linked design/testing prerequisites. The old `CLAUDE.md` is removed,
rather than leaving another competing instruction source. Unmigrated modules keep
their existing notes until E accounts for them.

## Format and verification

S, A and C rules use a compact ID/topic table followed by named sections and
paragraphs. L0–L7 remain a small layer table. The original canonical files and
all ID numbers remain stable; `scripts/docs.py check` can still discover each
ID from a table row. Rule wording is preserved apart from replacing C15's
module-specific `CLAUDE.md` reference with documentation in general, and correcting
A35's stale claim that no expansion body is lowered. `bodyWithSourceMap` already
lowers mapped server output, and `expansionDiagnostics` infers its bodies; the
[existing regression cases](../../modules/loupe/src/diagnostics_test.cj) exercise
that behavior. A35 now distinguishes those bodies from cjls's comment stubs
(D118). This reconciles the rule to implementation without accepting D132's
remaining proposals; see the status review.

S6 now explains the handler/query boundary and distinguishes it from macro
validation. D6's original no-LRU/no-GC rationale is historical; current retention
behavior is described by A2, D17 and D18. The rule and the historical ADR remain
in place; no runtime behavior changes.

S4 preserves empty answers for unknown documents while distinguishing malformed
parameters (`INVALID_PARAMS`) from a valid request that cannot be fulfilled
(`REQUEST_FAILED`), matching the existing macro-expansion command.

S10 scopes the deadlock prohibition to read-loop handlers and calls out cancellation
and retry concerns for waiting in a readonly handler. C22 links its usual Option
style to C11's measured hot-path exception for lambda inlining.

The former analysis "Pieces" API table is replaced by conceptual prose and source
navigation in Architecture. The former layer dependency overview is moved there;
module manifests remain authoritative for the full graph. The
[ADR status review](adr-status-review.md) identifies discrepancies for explicit
reconciliation and does not silently accept or rewrite decisions.

Documentation checks validate IDs and ADR headers; local link and anchor checks
and comparison against the previous rule text validate this move. No Cangjie
behavior changes, SDK installation, generator run or cross-platform claim belongs
to this documentation-only pilot. Final fresh-contributor and fresh-agent scenario
execution remains in F.
