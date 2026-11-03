# ADR-0163: The formatter removes redundant singleton import braces

Status: accepted, 2026-11-03

## Context

`import source_change.{applyEdits}` and `import source_change.applyEdits`
express the same import, but D150's token preservation prevents the formatter
from choosing the shorter form. A separate import action would leave this
purely syntactic choice inconsistent between CLI, LSP and generators.

## Decision

Narrow D150's token and tree preservation contract: remove the braces of an
import-tree list containing exactly one import, with no comments anywhere in
the list and no trailing comma. Apply the same rule recursively, including to
aliases and public imports, in whole-file and range formatting. Preserve all
other significant tokens and the existing comment placement guarantees.

Keep this normalization in the shared layout builder, where import syntax is
already known. No semantic analysis or new setting is needed. Sorting,
merging, deduplication and unused-import removal remain outside this change.

## Consequences

Preservation checks compare tokens and reparsed structure after independently
canonicalizing only these singleton lists. Explicit expected-output cases cover
paths, aliases, nesting, comments, commas and range isolation. Files with syntax
errors are still refused; protected macro and string contents stay verbatim.
