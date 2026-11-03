# Apply source changes

Read loaded source through the current revision and use native `SourceChange`
values for checked project edits. All Cangjie source work stays in `runPython`.

Prefer semantic selection before implementing. Keep full expectedText in Python;
the model usually needs the selected declaration/member, then a compact diff and
the application report. This example changes the unique "{ 1 }" body inside a
function named target to "{ 2 }"; adapt the name and expected fragment to the task:

~~~python
import difflib
a = workspace.analysis()
path = "src/main.cj"
before = a.text(path)
data = before.encode("utf-8")
node = next(s for s in a.fileSymbols(path) if s.name == "target")
expected = b"{ 1 }"
assert data[node.range.start:node.range.end].count(expected) == 1
start = data.index(expected, node.range.start, node.range.end)
span = TextRange(start, start + len(expected))
replacement = "{ 2 }"
after = (data[:span.start] + replacement.encode("utf-8") + data[span.end:]).decode("utf-8")
diff = list(difflib.unified_diff(before.splitlines(), after.splitlines(),
                               fromfile=path, tofile=path, n=2, lineterm=""))
shown = []
used = 0
for line in diff:
    size = len(line.encode("utf-8")) + 1
    if used + size > 6000:
        break
    shown.append(line)
    used += size
report = workspace.applyChange(
    SourceChange([FileChange.EditFile(path, before, [TextEdit(span, replacement)])]),
    a.revision)
result = {"success": report.isSuccess, "applied": report.applied,
          "failed": report.failed, "error": report.error,
          "diff": shown, "diff_lines": len(diff), "omitted_lines": len(diff)-len(shown)}
~~~

If omitted_lines is nonzero, inspect diff hunks separately or request changed
semantic ranges with source_excerpts; omitted lines still need review.

Use a fresh call for diagnostics and semantic verification:

~~~python
a = workspace.analysis()
paths = ["src/main.cj"]
rows = [{"path": p, "message": d.message,
         "range": {"start": d.range.start, "end": d.range.end}}
        for p in paths for d in workspace.diagnostics(p)]
result = {"revision": a.revision, "diagnostics": rows[:20],
          "total": len(rows), "omitted": max(0, len(rows)-20)}
~~~

Also inspect changed references, selected callees or inferred types when they
matter for the change. Empty loupe diagnostics do not replace compiler/tests.
On OutputBudgetExceeded the script already executed. Inspect last_output and
the current state; never replay an applyChange script just to retrieve its diff.


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
