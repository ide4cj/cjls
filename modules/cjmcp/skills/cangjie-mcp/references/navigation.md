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
just to locate one method. If a semantic query has a gap, try syntax selection
([semantic recipe](semantic.md)) and targeted [API discovery](discovery.md) for
unknown contracts before a text fallback. Report the concrete limitation and
label textual evidence. It is fine to return a small file in full when it helps.

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

## Search root-relative paths safely

`workspace.files()` includes dependencies and returns absolute paths. Use path
components rather than string prefixes (`/repo-other` is not inside `/repo`).
For literals/comments, candidate discovery, residual-name checks or an identified
analysis gap, this textual search preserves all matches and UTF-8 byte ranges
while returning a bounded source page. It does not replace resolved usages:

~~~python
from pathlib import Path
a = workspace.analysis()
root = Path(workspace.root)
requests = []
files = []
needle = "target".encode("utf-8")
assert needle
for path in workspace.files():
    try:
        relative = Path(path).relative_to(root).as_posix()
    except ValueError:
        continue  # Dependency outside this workspace.
    if not (relative.startswith("src/") and relative.endswith(".cj")):
        continue
    files.append(relative)
    data = a.text(path).encode("utf-8")
    start = 0
    while True:
        start = data.find(needle, start)
        if start < 0:
            break
        requests.append((path, TextRange(start, start + len(needle))))
        start += 1  # Preserve overlapping textual matches.
result = {"files_searched": len(files), "matches": len(requests),
          "source": source_excerpts(a, requests, context_lines=1, max_bytes=10000)}
~~~

This is textual evidence. Semantic references should be deduplicated by
`(path, range.start, range.end)`. Source ranges may overlap: a class encloses its
methods, and context lines may overlap even for disjoint matches. For member
selection choose the smallest enclosing declaration; deduplicate selected
member ranges before presentation. `source_excerpts` preserves requests and
counts them separately; it does not merge overlapping excerpts. Never turn
context-expanded display ranges into edit ranges.

## Exact names and compact evidence

For an exact source name, explicitly select the source files first. The helper
walks complete file outlines and preserves overloads; its scope is the supplied
paths, including dependency files only when selected.

~~~python
a = workspace.analysis()
paths = ["src/main.cj"]
matches = exact_symbols(a, paths, "parse")
result = result_page([
    {"path": path, "name": symbol.name, "range": symbol.range,
     "selection": symbol.selectionRange}
    for path, symbol in matches
], limit=20)
~~~

`result_page` reports total, returned, omitted and next_offset. It bounds rows,
not JSON bytes: use `source_excerpts` for source and project native fields rather
than `str(object)`. Complete the query before paging; an empty page at the end
is not an empty search. The MCP response budget still applies.

### Extension type, extension member and ambiguous calls

The name in `extend String` denotes the extended type. References at that
position find uses of String, potentially across dependencies. It is not a
container query for extension members. Select the desired child from
`workspace.structure(path)`, then query its `selectionRange.start`.
Do not automatically run references on every top-level outline node.

References preserve possible meanings when call inference is ambiguous.
A reproduced cjpm case has overloaded static `parse` in a generic interface,
an optional-value cast in its body, and same-named free functions in scope.
The internal `parse(ctx, obj)` call has `AmbiguousMeaning`; references to both
free functions include it. This is candidate evidence, not proof of a dependency.
Keep the uncertainty visible:

~~~python
a = workspace.analysis()
s = a.semantic()
path, symbol = exact_symbols(a, ["src/main.cj"], "parse")[0]
rows = []
for ref in a.references(path, symbol.selectionRange.start):
    ref_path = a.path(ref.fileId)
    occurrence = s.at(ref.fileId, ref.range.start)
    resolution = None if occurrence is None else occurrence.resolution()
    rows.append({"path": ref_path, "range": ref.range,
                 "declaration": ref.isDeclaration,
                 "status": None if resolution is None else resolution.status.kind})
result = result_page(rows, limit=20)
~~~

Inspect resolved definitions/call evidence before changing an ambiguous
occurrence. Do not discard all ambiguous candidates and claim the remaining
references are complete. The real-process regression retains this limitation;
compiler validation remains necessary.
