# Python API recipes for agents

Run these scripts inside the MCP tool `runPython`. `workspace` and native types
are injected; do not `import loupe`. The executable's initialization instructions
provide the query playbook. For task routing, use the optional
[cangjie-mcp skill](../SKILL.md).

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

## Execution and freshness

- Assign JSON-serializable values to `result`, or print a compact answer. Native
  objects are not JSON dictionaries and cannot be returned directly.
- Each call has fresh Python globals. The loaded workspace persists. Obtain
  `analysis = workspace.analysis()` in each script that uses revision queries.
- Disk inputs and required macro expansions are synchronized automatically before
  each script. Between calls, a worker polls for changes every 500 ms. Query caches,
  build artifacts and SDK processes persist for the MCP session.
- The database stays fixed throughout the script and result serialization. Edits
  made during execution become visible to a later call. `workspace.reload()` only
  requests preparation after the script; it never refreshes a running script.
- The tool response's `revision`, `workspace.revision` and a newly captured
  `analysis.revision` agree. After a workspace update, older analysis handles raise
  `RuntimeError` containing `ContentModified`; reacquire a handle and its identities.
  Revision numbers describe loaded analysis, not an atomic snapshot of live disk.
- Keep all identities (`DefId`, `Ty`, `FileId`, macro calls) with their producing
  revision. Do not mix values from separate revisions.
- Paths may be absolute or relative to `workspace.root`. Offsets count UTF-8
  bytes from zero, must fall on character boundaries, and exclude range ends.
  Slice `analysis.text(path).encode("utf-8")`, not the Python string, with them.
- Preparation finishes before Python runs. Inspect `workspace.problems` and
  `workspace.hasExpandedMacros`; a usable answer may still be partial. If preparation
  throws, Python does not run and the tool error has a null `revision`.
- Python/native callback failures are reported through the tool's `error`
  traceback. Python has ordinary imports and local I/O, without a sandbox or
  hard timeout. Calls execute sequentially and scripts are never replayed
  automatically. Join any Python threads using analysis before the script returns.

## Check the loaded workspace

```python
result = {
    "root": workspace.root,
    "revision": workspace.revision,
    "problems": workspace.problems,
    "has_expanded_macros": workspace.hasExpandedMacros,
    "files": workspace.files()[:20],
}
```

For subsequent recipes, replace the sample path or symbol query with one from
the workspace. Each block is an independent `runPython` script. Limits below
bound the output; they do not impose a timeout on native analysis.

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

## Read expressions with inferred types

`body.exprs`, `inferred.exprs` and `expressionRanges` use the same expression
indices. A null inferred entry means the expression is not a value; it differs
from a present `Ty` whose kind is unknown. A null range means that this convenience
API cannot locate it in the declaration's source file (synthetic or expanded
origin). Use `loweredBody().sourceMap` when expansion provenance matters.

```python
analysis = workspace.analysis()
path = "src/main.cj"
source = analysis.text(path).encode("utf-8")
result = []
for definition in analysis.declarations(path):
    item = analysis.item(definition)
    inferred = analysis.infer(definition)
    spans = analysis.expressionRanges(definition)
    expressions = []
    for span, ty in zip(spans, inferred.exprs):
        if span is None:
            continue
        expressions.append({
            "text": source[span.start:span.end].decode("utf-8"),
            "type": None if ty is None else analysis.typeText(ty),
        })
        if len(expressions) == 10:
            break
    result.append({
        "names": [] if item is None else item.names,
        "expressions": expressions,
    })
    if len(result) == 10:
        break
```

`typeText` prints `{unknown}` for several distinct cases. When the distinction
matters, inspect the native enum rather than that display string:

```python
analysis = workspace.analysis()
result = []
for definition in analysis.declarations("src/main.cj")[:10]:
    for ty in analysis.infer(definition).locals[:10]:
        kind = analysis.typeKind(ty)
        if isinstance(kind, TyKind.ErrorTy):
            state = "user_error"
        elif isinstance(kind, TyKind.TodoTy):
            state = "unsupported_analysis"
        elif isinstance(kind, TyKind.UnknownTy):
            state = "missing_input_or_inference_limit"
        else:
            state = "known"
        result.append({"type": analysis.typeText(ty), "state": state})
```

## Inspect selected callees

The `CalleeTarget.expr` index identifies the callee expression; a call's outer
`CallExpr` is not generally that expression. The same declaration may occur more
than once. Initializer targets are marked separately from ordinary callees.

```python
analysis = workspace.analysis()
result = []
for definition in analysis.declarations("src/main.cj")[:10]:
    caller = analysis.item(definition)
    for target in analysis.infer(definition).callees[:20]:
        callee = analysis.item(target.decl)
        result.append({
            "caller": [] if caller is None else caller.names,
            "callee": [] if callee is None else callee.names,
            "callee_expression": target.expr.index,
            "initializer": target.isInitializer,
        })
```

## Maintaining the recipes

Update affected recipes and server instructions alongside binding changes. Keep
examples focused on actual tasks and native names; avoid a parallel handwritten
type catalog. Validate discovery and recipes against the real executable with
`python3 -m unittest discover -s tests/mcp -v`.
