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

The page returns every requested fragment intact or stops before one that would
exceed the **shared** JSON byte budget. Each excerpt has its request index, path,
one-based inclusive start/end lines, requested UTF-8 byte range, shown byte range
and source. With context_lines=0 the source is exactly the requested range;
context_lines=2 adds complete surrounding lines. Ranges remain end-exclusive.
Use source fields as text; line numbers are metadata, not inserted into source.

total counts all input requests; returned counts this page; omitted is total minus
returned (including earlier pages). next_offset identifies the first remaining
request, or is null. Recreate the same ordered requests at the same revision to
continue at that offset. Do not reuse offsets or semantic ranges after an edit.
required_bytes is null normally; otherwise it reports the candidate page size
that blocked progress. When next_offset equals offset, select a smaller member
or range, reduce context_lines, or explicitly increase max_bytes. No text is cut.
Counts describe your selected request list, not unqueried workspace declarations.
Empty ranges and EOF are supported; invalid UTF-8 boundaries raise an error.

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
