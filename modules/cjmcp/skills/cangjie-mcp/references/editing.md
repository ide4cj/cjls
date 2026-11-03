# Apply source changes

Read loaded source through the current revision and use native `SourceChange`
values for checked project edits. All Cangjie source work stays in `runPython`.

```python
a = workspace.analysis()
path = "src/main.cj"
before = a.text(path)
# Select range from a semantic query in this revision.
change = SourceChange([
    FileChange.EditFile(path, before, [TextEdit(range, replacement)]),
    FileChange.CreateFile("src/added.cj", "package sample\nfunc added() {}\n"),
])
report = workspace.applyChange(change, a.revision)
result = {"revision": report.revision, "applied": report.applied,
          "failed": report.failed, "error": report.error}
```

`EditFile(path, expectedText, edits)` accepts unordered UTF-8 byte edits against
one original string. Pass formatting results directly as `edits`. Same-position
insertions keep input order. Overlapping replacements, insertions inside them,
invalid boundaries and out-of-bounds ranges fail before writing.

`CreateFile(path, text)` creates initial contents and missing parent directories;
it never overwrites an existing file. `RenameFile(path, target, expectedText)`
requires a missing target and creates missing parent directories.
`DeleteFile(path, expectedText)` removes an existing regular file.

Each path may occur once, including rename destinations. Compose dependent
operations before constructing the change. Paths may be root-relative or
absolute inside the workspace; normalized path aliases, symbolic-link traversal, paths outside
the workspace and using a changed file as a parent directory are rejected.

Supply this script's revision. Existing files must match both their expected
text on disk and their revision text when loaded. Validation of the entire set
precedes writes. A preflight failure returns an empty `applied`, null `failed`
and an error. A stale revision raises `ContentModified`.

The report's `applied` contains zero-based operation indices. An I/O failure
stops at `failed`; that operation may have partially changed disk, and earlier
operations and newly created directories remain. Inspect disk before retrying.
No automatic rollback, concurrent-writer exclusion or multi-file transaction is
promised. Create/rename destinations are reserved without overwriting them;
renaming uses hard links and therefore requires the same filesystem.

The current script retains its original analysis, even after a successful write.
In a **new call**, reacquire `workspace.analysis()`, inspect the new text and
diagnostics, and recompute identities and ranges. New files are discovered then.
Run the appropriate compiler/tests to validate the change.

Ordinary Python `pathlib` I/O remains available for unloaded files and operations
outside this model. It reads live disk, independently of analysis. For direct
writes to loaded source, compare disk bytes with revision text before writing;
apply byte edits from the end and preserve untouched bytes.
