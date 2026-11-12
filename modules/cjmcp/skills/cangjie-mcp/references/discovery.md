# Discover an unfamiliar member

Use this recipe when a specific missing signature, default, field or contract
blocks the next task query. The server's core queries and task recipes can be
used directly, without checking their signatures first. Reuse a reference
declaration already available in the task context. Once the missing detail is
resolved, return to the task rather than exploring adjacent API types.

When the path and member are known, select that member directly; no file listing
or outline is needed. The result includes its signature and short contract:

```python
result = api_docs.read_symbol("cjmcp/analysis.pyi", "AnalysisRevision.symbols")
```

`Workspace` members are in `cjmcp/python.pyi`; `AnalysisRevision` members are in
`cjmcp/analysis.pyi`. Checked edit constructors are `FileChange.EditFile`,
`FileChange.CreateFile`, `FileChange.RenameFile` and `FileChange.DeleteFile`, in
`source_change/source_change.pyi`; they are not injected bare names.
Dotted names select nested members, for example
`api_docs.read_symbol("loupe.hir/body.pyi", "Expr.CallExpr")`.
Follow returned-type links only for fields or contracts needed by the task.
Paths are relative to the documentation root; native objects are injected, not
importable modules.

If the name or path is unknown, filter `api_docs.files()` or
`api_docs.outline(path, class_name)` inside Python, returning only matching names.
For example, to find a revision query by a name fragment:

```python
result = [entry["symbol"] for entry in api_docs.outline(
    "cjmcp/analysis.pyi", "AnalysisRevision")
    if "signature" in entry["symbol"].lower()]
```

Then select the needed member with `read_symbol`; avoid returning whole files or
classes. Use a top-level `outline(path)` only if the container is unknown.
Overloads and property accessors are returned together with decorators and docs.
Selections over the default 12000 UTF-8 bytes raise an error with the required
size: narrow the selection before increasing `max_bytes`. The regular response
budget still applies. This reference ships with the binary and may lag bindings.

For a member absent from the supplied reference, inspect a focused name family:

```python
analysis = workspace.analysis()
names = [name for name in dir(type(analysis)) if "signature" in name.lower()]
result = {"members": names[:20], "omitted": max(0, len(names) - 20)}
```

`dir` shows names, not signatures. Inspect a small result sample for unknown
fields; avoid full object or namespace dumps. `help(Type)` may expose descriptors,
but generated bindings can omit signatures/docstrings; do not assume `inspect.signature` works.
Arrays become lists, options become `None`, and immutable fields stay read-only.
`TextRange.len` is a byte-length property, without parentheses.
Enum variants support `isinstance` and pattern matching; payloads are `field0`,
`field1`, etc., named in the variant's `__match_args__`.

For a contract question, first check the running binary's identity:

```python
a = workspace.analysis()
result = globals().get("server_info")
```

server_info is a plain dictionary with name, version and _meta (apiVersion,
commit, dirty and features). It is independent of the analyzed workspace. Missing
server_info means the server predates identity reporting; do not infer its API
from a newer checkout. Load the documentation shipped with the selected binary,
or compare _meta.commit with a source checkout before consulting it.

If matching source is available, paths relative to that checkout are
`modules/cjmcp/src/python_types.cj` for type registration,
`modules/cjmcp/src/python.cj` for workspace bindings,
`modules/cjmcp/src/analysis.cj` for revision methods, and `modules/loupe/src`
for native declarations. These paths are optional source pointers, not files
installed with this skill. Use runPython for Cangjie source reads.

## Exact exported names

When an exported name is known but its stub path is not, use
`api_docs.find_symbol("FileChange.EditFile")`. It returns every matching path and
declaration count; select the intended path with `read_symbol`. Dotted names
are exact and case-sensitive. This searches bundled documentation, not project
symbols. For source declarations use `exact_symbols(a, paths, name)`; do not
filter a short fuzzy search and interpret the result as exhaustive.
