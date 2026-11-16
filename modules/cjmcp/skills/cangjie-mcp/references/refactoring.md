# Refactor a class member end to end

This executable recipe renames a unique source method `Counter.value` to `count`.
Adapt the path/class/member names and transformation to the task. It is a scoped
example, not a general rename engine: inspect overloads, inheritance, interfaces,
extensions and macros separately when present. Resolve partial analysis before
applying; references alone do not prove those cases complete.

The first call finds declarations, collects and deduplicates references, selects
the smallest containing declarations, and returns bounded excerpts. Run with
`apply = False` to inspect the selection; then rerun the same script with
`apply = True` to recompute the plan against the current revision and apply it.
No native objects or globals need to survive calls. An already authorized,
unambiguous change can use `apply = True` immediately.

~~~python
from pathlib import Path
import difflib
a = workspace.analysis()
path, class_name, old_name, new_name = "src/counter.cj", "Counter", "value", "count"
apply = False
root = Path(workspace.root)
classes = [n for n in workspace.structure(path) if n.name == class_name]
assert len(classes) == 1, "select the intended class"
members = [n for n in classes[0].children if n.name == old_name]
assert len(members) == 1, "resolve overloads before changing a member"
member = members[0]
assert not any(n.name == new_name for n in classes[0].children), "name collision"

# Include the declaration explicitly; multiple queries can return the same range.
unique = {(str(root / path), member.selectionRange.start,
           member.selectionRange.end): member.selectionRange}
for declaration in members:
    for ref in a.references(path, declaration.selectionRange.start):
        ref_path = a.path(ref.fileId)
        Path(ref_path).relative_to(root)  # Refuse edits outside this workspace.
        unique[(ref_path, ref.range.start, ref.range.end)] = ref.range

by_path, selected = {}, {}
def flatten(nodes):
    for node in nodes:
        yield node
        yield from flatten(node.children)
for (ref_path, start, end), span in sorted(unique.items()):
    by_path.setdefault(ref_path, []).append(span)
    enclosing = [n for n in flatten(workspace.structure(ref_path))
                 if n.range.start <= start and end <= n.range.end]
    # A class and its method overlap. Prefer the nearest containing declaration.
    shown = min(enclosing, key=lambda n: n.range.end - n.range.start).range if enclosing else span
    selected[(ref_path, shown.start, shown.end)] = (ref_path, shown)
page = source_excerpts(a, list(selected.values()), max_bytes=10000)
result = {"root": workspace.root, "load_diagnostics": workspace.loadDiagnostics,
          "macros": workspace.macros, "references": len(unique), "source": page}

if apply:
    changes, diffs = [], []
    for ref_path, spans in sorted(by_path.items()):
        before = a.text(ref_path)
        data = before.encode("utf-8")
        ordered = sorted(spans, key=lambda s: (s.start, s.end))
        assert all(x.end <= y.start for x, y in zip(ordered, ordered[1:])), "overlapping edits"
        assert all(data[s.start:s.end] == old_name.encode("utf-8") for s in ordered)
        after = data
        for span in reversed(ordered):
            after = after[:span.start] + new_name.encode("utf-8") + after[span.end:]
        changes.append(FileChange.EditFile(ref_path, before,
                       [TextEdit(s, new_name) for s in ordered]))
        diffs.extend(difflib.unified_diff(before.splitlines(), after.decode("utf-8").splitlines(),
                     fromfile=ref_path, tofile=ref_path, n=2, lineterm=""))
    report = workspace.applyChange(SourceChange(changes), a.revision)
    result = {"success": report.isSuccess, "applied": report.applied,
              "failed": report.failed, "error": report.error,
              "paths": sorted(by_path), "references": len(unique),
              "diff": diffs[:80], "omitted_diff_lines": max(0, len(diffs)-80)}
~~~

Inspect the application report, including partial I/O failures. If output exceeds
the response limit, inspect `outputBudget.largest_fields` and select evidence from
`last_output`; never replay the write to recover its response.

In a **new call**, reacquire the snapshot and identities. Copy all affected paths
from the application report into `paths`; the sample fixture changes one file.
Verify the renamed declaration and its references, and inspect diagnostics for
every changed file. Compare root/sessionId with the edit response, and revision
with that response's revision; do not hard-code revision numbers across sessions.

~~~python
a = workspace.analysis()
path = "src/counter.cj"
paths = [path]
owner = next(n for n in workspace.structure(path) if n.name == "Counter")
assert not any(n.name == "value" for n in owner.children)
renamed = [n for n in owner.children if n.name == "count"]
assert len(renamed) == 1
refs = a.references(path, renamed[0].selectionRange.start)
unique = {(a.path(r.fileId), r.range.start, r.range.end) for r in refs}
assert unique
assert all(a.text(p).encode("utf-8")[start:end] == b"count" for p, start, end in unique)
rows = [d for p in paths for d in workspace.diagnostics(p)]
result = {"revision": a.revision, "references": len(unique),
          "diagnostics": rows[:20], "total": len(rows), "omitted": max(0, len(rows)-20)}
~~~

Check the expected reference count from the edit plan as well, and run the
appropriate compiler/tests. Empty diagnostics alone do not prove a refactoring.
