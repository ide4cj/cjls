# source_change

Protocol-independent changes to source files. `TextEdit` and `applyEdits` use
UTF-8 byte ranges against one original string. `SourceChange.validate()` checks
text edits and path conflicts; it performs no I/O. File operations carry expected
contents for existing files and initial contents for new ones.

Paths belong to the consumer's normalized namespace. Consumers must resolve
aliases before applying changes, check expected contents and any relevant
revision or document version, and define application/failure behavior. Rename
destinations never overwrite existing files. Dependent operations on one path
must be composed before constructing the change. These contracts allow LSP and
disk consumers to share a description without sharing write policy; see
[D162](../../docs/adr/0162-source-change.md).

Run the focused tests with:

```bash
cjpm test -m modules/source_change --no-progress --target-dir target/test
```
