# Find declarations and their usages

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
