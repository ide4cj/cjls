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

## Follow incoming and outgoing calls

`prepareCallHierarchy(path, offset)` returns callable declarations, or `[]` for
an ordinary value or unresolved name. Keep each `CallHierarchyEntry` with its
producing analysis revision. `incomingCalls(entry)` groups callers;
`outgoingCalls(entry)` groups callees. Each `HierarchyCalls.ranges` lists the
explicit call sites in the caller's file: the returned item's target for incoming
calls, the input entry's target for outgoing calls. Anonymous lambdas belong to
their enclosing callable; function values are not followed through assignments.

Binary callables carry their canonical identity in `entry.definition`, including
when attached sources provide `entry.target`. Without attached sources, the target
points to the referring name. Preserve `definition` when reconstructing an entry;
incoming calls use it to distinguish binary overloads. Source-only entries use `None`.

```python
analysis = workspace.analysis()
path = "src/main.cj"
offset = analysis.text(path).encode("utf-8").index(b"main")
result = [
    {"callee": calls.item.name,
     "path": analysis.path(calls.item.target.fileId),
     "sites": [{"start": span.start, "end": span.end} for span in calls.ranges]}
    for entry in analysis.prepareCallHierarchy(path, offset)
    for calls in analysis.outgoingCalls(entry)
]
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

## Signature ranges and formatting edits

`LoweredSignature` pairs the native `Signature` with a concrete
`SignatureSourceMap` adapter, following the same pointer boundary as `BodySource`.
Use a signature's own `TypeRefId` to locate a written type. Ranges belong to
`analysis.definitionFile(definition)`: for `ItemFile.Expansion`, read the matching
expansion text rather than the call site's file. Missing type references have
`None` ranges; binary declarations have an empty source map.

```python
analysis = workspace.analysis()
definition = analysis.declarations("src/main.cj")[0]
lowered = analysis.signatureWithSourceMap(definition)
result = [
    {"type": lowered.signature.text(TypeRefId(i)), "start": span.start, "end": span.end}
    for i, span in enumerate(lowered.sourceMap.ranges)
    if span is not None
]
```

Formatting returns edits without writing files or reading formatter config.
`None` means syntax errors; `[]` means the text is already canonical. Pass
`FormatOptions` explicitly for a policy other than the library defaults. Apply
non-overlapping edits from the end when constructing a preview from UTF-8 bytes:

```python
analysis = workspace.analysis()
path = "src/main.cj"
options = FormatOptions(lineWidth=100, indentWidth=2, simpleIf=SimpleIf.Compact())
edits = analysis.formatting(path, options=options)
data = analysis.text(path).encode("utf-8")
if edits is not None:
    for edit in reversed(edits):
        data = data[:edit.range.start] + edit.text.encode("utf-8") + data[edit.range.end:]
result = {"preview": None if edits is None else data.decode("utf-8")}
```

`rangeFormatting(path, TextRange(start, end), options=options)` formats the
complete enclosing syntax node. Both endpoints must be valid UTF-8 boundaries
inside the revision text. `newFilePackageLine(path)` suggests a header for a new
file without creating it; it also recognizes macro packages.
`formatting(path)` and `rangeFormatting(path, range)` use the library defaults.
`FormatOptions()` uses those same defaults; `FormatOptions(indentWidth=2)` changes
only indentation. Unknown keywords and incompatible argument types raise `TypeError`.

`allMembers(definition)` accepts a type, an `extend` or a member whose enclosing
type should be inspected. It returns native `MemberTarget` variants, preserving
overloads, inherited members, extension visibility and lookup shadowing.
`fileSymbols(path)` gives the full outline in declaration order. Builtin docs
come from `builtinTypeDoc`, `builtinAnnotationDoc` and `builtinMacroDoc`; use
names without `@`, and handle `None` for unknown names.

Expansion queries use byte offsets into `analysis.expansion(call).text`:
`hoverInExpansion`, `definitionInExpansion` and `typeDefinitionInExpansion`.
They reject missing expansion text or invalid byte positions. A hover range
belongs to the requested expansion; each navigation target has its own
`expansion` identity (or `None` for source), which selects the text for its ranges.

## Maintaining the recipes

Update affected recipes and server instructions alongside binding changes. Keep
examples focused on actual tasks and native names; avoid a parallel handwritten
type catalog. Validate discovery and recipes against the real executable with
`python3 -m unittest discover -s tests/mcp -v`.
