# Find declarations, then return selected source

Keep revision text inside Python. Existing symbols, fileSymbols, structure and
references queries do the semantic selection; source_excerpts only presents it.
For known paths, filter the complete file outline so overloads and totals remain
visible. For an unknown path, start with a.symbols("name", 20): it searches by
case-insensitive subsequence, and a full limit means there may be more matches,
not that the total is 20. Narrow the name/path before selecting an ambiguous hit.

~~~python
a = workspace.analysis()
path = "src/runtime/app.cj"
candidates = [s for s in a.fileSymbols(path)
              if s.name in ("run", "dispatch")]
result = {
    "root": workspace.root,
    "load_diagnostics": workspace.loadDiagnostics,
    "macros": workspace.macros,
    "source": source_excerpts(a, [(path, s.range) for s in candidates],
                              max_bytes=12000),
}
~~~

The helper returns whole excerpts with paths, line/range metadata and explicit
omissions. Follow next_offset with the same ordered requests and revision;
if it cannot advance, select a smaller member/range or increase max_bytes.
The page includes revision, total, returned, omitted, next_offset and required_bytes.
The budget counts compact UTF-8 JSON bytes; context_lines adds whole surrounding
lines. total counts selected requests; omitted includes earlier pages.
required_bytes reports the page size that blocked progress. The tool response
budget applies independently to the complete reply.

For a large class or test suite, traverse nested structure children and select
individual methods/tests before asking for source. Do not send the entire class
just to locate one method. If semantic selection is unavailable, search the full
text in Python and return only matching UTF-8 ranges with context; label this as
textual evidence. It is fine to return a small file in full when it helps.

References include declarations (isDeclaration). Select a few relevant usages,
but preserve the complete count:

~~~python
a = workspace.analysis()
path = "src/main.cj"
symbol = next(s for s in a.fileSymbols(path) if s.name == "target")
refs = a.references(path, symbol.selectionRange.start)
requests = [(a.path(r.fileId), r.range) for r in refs]
result = source_excerpts(a, requests, context_lines=2, max_bytes=10000)
~~~

For NavigationTarget values, inspect expansion before slicing: an expansion range
belongs to expansion text, not a.text(path). This helper accepts source-file
ranges; expansion excerpts still use the [expansion recipe](expansions.md).
