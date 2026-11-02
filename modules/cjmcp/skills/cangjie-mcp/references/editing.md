# Read and save Cangjie sources

Use `analysis.text(path)` for loaded revision text, and semantic queries to select
the declaration or usage to change. All source reading and writing goes through
`runPython`, without shell commands or subprocesses. Python `pathlib` I/O in the
tool also supports creating, deleting and reading files not loaded by analysis;
it reads live disk and does not provide semantic answers.

For an edit to an existing file, check that disk still matches the revision before
writing. Apply UTF-8 byte ranges from the end, keeping untouched bytes unchanged:

```python
from pathlib import Path
a = workspace.analysis()
path = "src/main.cj"
before = a.text(path).encode("utf-8")
# Select start/end from a semantic result; replacement is the intended source.
after = before[:start] + replacement.encode("utf-8") + before[end:]
target = Path(workspace.root, path)
assert target.read_bytes() == before, "source changed; query again before editing"
target.write_bytes(after)
result = {"path": str(target), "revision_before_edit": a.revision}
```

The current script retains its old revision after writing. In a **new call**,
reacquire `workspace.analysis()`, check the new text and diagnostics, and recompute
identities and ranges. Run the appropriate compiler/tests to validate the change.
No dedicated refactoring/write API is required for this workflow. Report tool
failures or incomplete analysis; do not replace it with shell analysis or edits.
