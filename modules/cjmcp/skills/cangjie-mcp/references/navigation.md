# Navigation recipes

Use these only when the server instructions do not give enough detail for the
task. Replace the symbol query with the requested name. Each block is an
independent `runPython` script; `workspace` and native types are already injected.

## Find declarations and their usages

`symbols` searches names by case-insensitive subsequence. Keep a small limit and
show the actual matches so ambiguous names are visible. `references` includes
declarations, distinguished by `isDeclaration`.

```python
analysis = workspace.analysis()
result = []
for found in analysis.symbols("AnalysisDatabase", 5):
    path = analysis.path(found.fileId)
    refs = analysis.references(path, found.symbol.selectionRange.start)
    span = found.symbol.range
    source = analysis.text(path).encode("utf-8")
    excerpt = source[span.start:span.end].decode("utf-8")
    result.append({
        "name": found.symbol.name,
        "path": path,
        "start": span.start,
        "end": span.end,
        "source": excerpt[:2000],
        "source_truncated": len(excerpt) > 2000,
        "reference_count": len(refs),
        "references_truncated": len(refs) > 20,
        "references": [
            {
                "path": analysis.path(ref.fileId),
                "start": ref.range.start,
                "end": ref.range.end,
                "declaration": ref.isDeclaration,
                "access": None if ref.access is None else ref.access.toString(),
            }
            for ref in refs[:20]
        ],
    })
```

## Workspace checks within a task query

Include `workspace.root`, `workspace.problems` and `workspace.hasExpandedMacros`
with the first task's results. Do not spend a separate call listing files or API
members unless the task needs them. Use `workspace.files()` when paths are unknown.

## Discover an unfamiliar member

Discover unfamiliar native members in the running server, then inspect a small
sample of query results:

```python
analysis = workspace.analysis()
result = {
    "workspace_members": [n for n in dir(type(workspace)) if not n.startswith("_")],
    "analysis_members": [n for n in dir(type(analysis)) if not n.startswith("_")],
    "range_members": [n for n in dir(TextRange) if not n.startswith("_")],
    "call_payloads": list(Expr.CallExpr.__match_args__),
}
```

`dir` shows names, not a complete signature contract. `help(Type)` can expose
native descriptors, but generated bindings may omit method signatures/docstrings;
do not assume `inspect.signature` works. Use the recipes for known call shapes.
Arrays become lists, options become `None`, and immutable fields remain read-only.
`TextRange.len` is a byte-length property (`span.len`, without parentheses).
Enum variants support `isinstance` and Python pattern matching; payloads are
`field0`, `field1`, etc., named in `__match_args__`.

For details beyond these recipes, a checkout contains the complete type
registration in [python_types.cj](../../../src/python_types.cj), workspace bindings in
[python.cj](../../../src/python.cj), revision methods in [analysis.cj](../../../src/analysis.cj),
and native declarations in `modules/loupe/src`. These source links need a checkout;
the Linux archive ships the recipes and skill. Runtime discovery reflects the
installed executable, which may differ from a separate source checkout.

## Maintaining the recipes

Update affected recipes and server instructions alongside binding changes. Keep
examples focused on actual tasks and native names; avoid a parallel handwritten
type catalog. Validate discovery and recipes against the real executable with
`python3 -m unittest discover -s tests/mcp -v`.
