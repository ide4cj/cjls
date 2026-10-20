# ADR status reconciliation queue

This is an explicit review queue for [#455](https://github.com/ide4cj/cjls/issues/455),
against the package A base (`965e879`). Historical ADR files and their generated
index are unchanged. A `proposed` heading can coexist with implemented code;
neither the presence of code nor this table constitutes maintainer acceptance.

## Implementation evidence in the architecture pilot

These decisions still say `proposed`, but source inspection found the following
implementation. Reconcile each status explicitly: confirm the whole decision,
record partial implementation or changed scope, and identify any superseding
decision. Do not batch-relabel them solely because one cited symbol exists.
No behavior tests were run for this documentation audit.

| Historical status | Observed evidence requiring reconciliation |
|---|---|
| [D82](../adr/0082-a-macros-name-is-looked-up-in-what-the-files-write.md): proposed | Macro qualifiers and exported names are read at `ScopeStage.Written`. [Source](../../modules/loupe/src/hir/macro_resolution.cj). |
| [D93](../adr/0093-when-is-evaluated-on-an-active-item-tree.md): proposed | `activeItemTree` filters the written item tree by cfg. [Source](../../modules/loupe/src/hir/when.cj). |
| [D98](../adr/0098-workspace-expansions-are-an-input-of-their-file.md): proposed | `SourceFile.macroOutputs` is an input field; `hir/server_macro.cj` reads it and sets outputs by stable key. [Source](../../modules/loupe/src/db/db.cj). |
| [D99](../adr/0099-source-sets-are-a-chain-and-common-is-its-specific.md): proposed | `commonsOf` and `commonMembersNamed` implement common/specific correspondence. [Source](../../modules/loupe/src/hir/multiplatform.cj). |
| [D117](../adr/0117-expression-macros-are-asked-with-the-items-calls.md): proposed | `expandToOf` selects item, expression or statement parsing; reading expression bodies remains limited by A35. [Source](../../modules/loupe/src/hir/expansion.cj). |
| [D122](../adr/0122-a-request-the-files-changed-under-runs-again.md): proposed | `runAgainOnAChange` retries on a fresh loop snapshot unless the client cancelled. [Source](../../modules/cjls/src/server/server.cj). |
| [D123](../adr/0123-std-macros-run-in-the-macro-server.md): proposed | `serverCalls` handles std and workspace calls; output values feed analysis. Full host behavior needs separate review. [Source](../../modules/loupe/src/hir/server_macro.cj). |
| [D128](../adr/0128-a-members-hierarchy-is-matched-by-name-and-parameters.md): proposed | Tracked `packageSubtypes`, `overriddenMembers` and `overridingMembers` are present. [Source](../../modules/loupe/src/hir/hierarchy.cj). |
| [D129](../adr/0129-test-files-see-std-unittest-macros.md): proposed | `testImportsOf` uses the package test-file input; database lowering populates that input. [Source](../../modules/loupe/src/hir/scope.cj). |
| [D130](../adr/0130-references-filter-files-by-an-index-of-their-words.md): proposed | `fileWords` is tracked and constructs a blocked bloom filter read by reference search. [Source](../../modules/loupe/src/file_words.cj). |
| [D131](../adr/0131-a-diagnostic-reports-result-id-is-its-hash.md): proposed | `resultIdOf` hashes serialized items and the snapshot openings counter. [Source](../../modules/cjls/src/handlers/diagnostics.cj). |
| [D132](../adr/0132-a-replaced-item-is-read-through-its-expansion.md): proposed | Partial implementation: `bodyWithSourceMap` lowers mapped server output; diagnostics skips replaced source bodies and infers output bodies. This does not establish every proposed source-position mapping and feature behavior. [Source](../../modules/loupe/src/hir/body.cj). |
| [D135](../adr/0135-workspace-diagnostics-are-not-offered.md): proposed | Advertised diagnostic options set `workspaceDiagnostics: false`. [Source](../../modules/cjls/src/handlers/router.cj). |
| [D136](../adr/0136-semantic-tokens-are-sent-whole.md): proposed | The handler returns full tokens; the router offers no full/delta route. [Source](../../modules/cjls/src/handlers/semantic_tokens.cj). |
| [D139](../adr/0139-a-file-in-no-package-is-compiled-alone.md): proposed | `loneFileProjects` constructs projects for uncovered documents. [Source](../../modules/project_model/src/lone.cj). |
| [D141](../adr/0141-a-tests-state-runs-no-macros.md): proposed | `startsMacros` defaults to `None`; workspace scheduling consults it before starting macro work. [Source](../../modules/cjls/src/server/state.cj). |

D132 exposes a concrete mismatch in the old A35 wording: the rule said that no
expansion body is lowered, while the implementation lowers and infers mapped
server output. The pilot corrects that sentence only, preserving the limitation
for cjls-generated comment stubs (D118) and expression/statement macros. See
[`expansionDiagnostics`](../../modules/loupe/src/diagnostics.cj) and the
[regression cases](../../modules/loupe/src/diagnostics_test.cj) for replaced bodies.
D132 remains proposed, including its broader source-position mapping and gate
claims, until a separate decision review reconciles their scope.

## Remaining proposed decisions

The following proposed ADRs were enumerated from the archive but their complete
implementation was not assessed in this pilot. Their status is not evidence of
missing functionality. Review them in the corresponding module or SDK workstream
before claiming a complete archive reconciliation:

[D66](../adr/0066-sugar-is-typed-as-cjc-desugars-it.md), [D69](../adr/0069-std-sources-fetched-by-cjls.md), [D70](../adr/0070-an-optional-chain-is-lowered-into-matches.md), [D74](../adr/0074-range-formatting.md), [D75](../adr/0075-a-write-that-changes-nothing-opens-no-revision.md), [D76](../adr/0076-a-bodys-brace-joins-the-line-before.md), [D77](../adr/0077-an-unknown-type-is-an-error-or-a-gap.md), [D78](../adr/0078-the-windows-child-dies-with-its-parent.md), [D79](../adr/0079-settings-are-r1s.md), [D83](../adr/0083-members-named-through-a-type-are-filtered-by-its-type.md), [D84](../adr/0084-what-was-resolved-is-kept.md), [D85](../adr/0085-a-dependency-keeps-its-edge.md), [D87](../adr/0087-workspace-macros-run-in-the-sdks-macro-server.md), [D88](../adr/0088-a-document-in-no-package-finds-its-own-project.md), [D90](../adr/0090-what-inference-finds-wrong-is-reported.md), [D91](../adr/0091-the-windows-macro-server-is-started-by-createprocessw.md), [D92](../adr/0092-a-new-file-is-given-its-package-line.md), [D95](../adr/0095-cjc-token-kinds-are-numbered-by-the-sdks-tokens-inc.md), [D96](../adr/0096-build-and-tests-are-jobs-of-their-own.md), [D97](../adr/0097-unused-warnings-are-off.md), [D101](../adr/0101-platform-code-is-a-multiplatform-module.md), [D102](../adr/0102-the-multiplatform-module-is-built-without-o2.md), [D103](../adr/0103-an-expansion-is-shown-as-a-request-and-as-a-read-only-file.md), [D104](../adr/0104-workspace-macros-are-built-by-cjc-and-run-under-a-deadline.md), [D105](../adr/0105-semantic-tokens-augment-the-grammar.md), [D106](../adr/0106-the-servers-directory-is-the-projects-cache-cjls.md), [D107](../adr/0107-settings-follow-the-pin.md), [D108](../adr/0108-error-roots-only-shrink.md), [D109](../adr/0109-builtins-are-told-in-a-table-of-our-own.md), [D110](../adr/0110-a-speculative-tree-reparses-the-block-around-the-cursor.md), [D111](../adr/0111-completion-lists-from-the-speculative-tree-and-resolves-lazily.md), [D112](../adr/0112-arguments-are-matched-before-a-candidate-is-tried.md), [D113](../adr/0113-the-architecture-is-the-only-when.md), [D114](../adr/0114-std-derive-is-expanded-in-a-workspace-macros-input.md), [D115](../adr/0115-unittest-attributes-are-parsed-and-lowered-into-the-declarations-body.md), [D116](../adr/0116-quote-interpolations-are-code-of-the-macro.md), [D118](../adr/0118-a-body-cjls-writes-itself-is-a-comment.md), [D119](../adr/0119-a-macro-call-on-a-parameter-is-a-call-of-its-items-chain.md), [D121](../adr/0121-the-error-roots-file-grows-with-a-known-gap-met-idiomatically.md), [D124](../adr/0124-references-are-searched-per-request-where-the-declaration-is-visible.md), [D125](../adr/0125-cjc-runs-behind-a-shim-in-ci.md), [D127](../adr/0127-completion-reads-the-position-by-the-markers-parent.md), [D134](../adr/0134-an-operator-none-fits-is-reported.md), [D137](../adr/0137-optics-is-the-gate-of-workspace-macros.md), [D138](../adr/0138-an-index-assigned-by-an-operator-is-desugared-in-the-hir.md), [D140](../adr/0140-an-enums-constructors-of-one-name-are-overloads.md).

The queue separates documentation migration from acceptance of architectural
choices. Any explicit status reconciliation must preserve the decision history
and use a new or amending ADR when the decision itself changes. The generated
ADR index is updated by the existing merge workflow, not by this pilot.
