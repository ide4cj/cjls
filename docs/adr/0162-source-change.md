# ADR-0162: Share source changes between analysis frontends

Status: accepted

## Context

Formatting already returns UTF-8 text edits, while refactorings and code generation
also need file creation, renaming and deletion. LSP clients own document buffers;
a disk-based frontend owns its filesystem writes. Neither application policy
belongs in analysis or the formatter.

## Decision

A static `source_change` module owns `TextEdit`, checked application to a string,
and a `SourceChange` collection of `FileChange` operations. It depends on
`ginkgo.TextRange`, not Cangjie syntax, project models, LSP or filesystem I/O.
Existing-file operations carry their expected original text. Paths use the
consumer's normalized namespace. Each path is reserved once, including rename
destinations; producers compose dependent operations before handing them off.

The formatter re-exports its existing `TextEdit` name and uses the checked text
application. LSP translation uses expected text for position conversion and
captured document versions. New-file package headers use this translation with
the open buffer's text and version. Clients without `documentChanges` receive
unversioned text edits through `changes`; resource operations require both
`documentChanges` and advertised operation support. A disk frontend resolves
paths, checks revision/content conflicts and owns writes and
failure reporting. A source change does not promise a filesystem transaction.

## Alternatives

Keeping edits in `cjformat` would make unrelated refactorings depend on the
formatter. Putting them in `loupe` would make text-only consumers depend on
analysis. A package inside `ginkgo` would couple source change contracts to tree
and parser machinery. A separate module keeps those responsibilities explicit.
