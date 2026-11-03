# Count, rank and return all tied maxima

Compose traversal, scope filtering, aggregation and selection in Python to
avoid returning intermediate rows. Split discovery from the final query when
that reduces total token use or clarifies the metric. Sort rankings by the
requested metric, then by name, path and source position as applicable, before
taking a bounded prefix.
For a global maximum, compute it over the whole population and return every
tied winner; an arbitrary prefix can lose winners. Report the population size
and omitted counts when limiting other evidence.

## Find files with the most outline functions and methods

`workspace.files()` includes dependency sources. This example selects paths
under the loaded root, including tests, and counts nested `Function` and `Method`
outline nodes. Constructors and macro expansion declarations are outside this
metric. An empty population has no maximum. This counts declarations per file;
it does not determine semantic overload sets. For overloads, preserve package
and enclosing type identity rather than grouping names across unrelated scopes;
see [member lookup](members.md) for inherited and extension members.

```python
from pathlib import Path

a = workspace.analysis()
root = Path(workspace.root)
rows = []
for path in workspace.files():
    if not Path(path).is_relative_to(root):
        continue
    pending = list(workspace.structure(path))
    count = 0
    while pending:
        node = pending.pop()
        if node.kind.toString() in ("Function", "Method"):
            count += 1
        pending.extend(node.children)
    rows.append({"path": path, "count": count})

rows.sort(key=lambda row: (-row["count"], row["path"]))
maximum = rows[0]["count"] if rows else None
winners = [row for row in rows if row["count"] == maximum]
result = {
    "root": workspace.root,
    "load_diagnostics": workspace.loadDiagnostics,
    "macros": workspace.macros,
    "files_considered": len(rows),
    "maximum": maximum,
    "winner_count": len(winners),
    "winners": winners,
}
```

Keep sorting in the task script: source outlines retain declaration order, and
other ordered results, such as source edits, must retain their API semantics.
