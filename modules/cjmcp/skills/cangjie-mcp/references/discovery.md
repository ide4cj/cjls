# Discover an unfamiliar member

Use the server's documented API first. Inspect only the object and member family
needed for an unresolved question, preferably alongside the useful query rather
than in a preliminary call. When `server_info['_meta']['features']` includes
`apiDocs`, read the supplied signatures before using introspection:

```python
result = api_docs.read("cjmcp/analysis.pyi")
```

`api_docs.files()` lists available `.pyi` paths. Start with `cjmcp/python.pyi`
for `Workspace` or `cjmcp/analysis.pyi` for `AnalysisRevision`; follow paths in
declaration comments relative to the documentation root. Files describe injected
objects, not importable modules. For large files, use `api_docs.outline(path)` to
list top-level declarations, then `api_docs.outline(path, "Expr")` for immediate
class members. Read a complete declaration with
`api_docs.read_symbol(path, "Expr.CallExpr")`; dotted names select nested members.
Overloads and property accessors are returned together with decorators and docs.
Selections over the default 12000 UTF-8 bytes raise an error with the required
size: select a smaller member or explicitly increase `max_bytes`. The regular
response budget still applies. This is the locally generated reference shipped
with the server, which may lag binding changes.

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
