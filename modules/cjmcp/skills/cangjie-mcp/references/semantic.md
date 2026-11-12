# Compose semantic queries

Capture one revision and one semantic analysis. Keep its objects together: native
identities and syntax pointers belong to that snapshot and contextual file.
After an input edit, acquire fresh handles; retained view operations raise a
native cancellation error, exposed as Python `RuntimeError`.

```python
a = workspace.analysis()
s = a.semantic()
path = "src/main.cj"
occurrence = s.at(a.fileId(path), 0)  # Replace with the selected UTF-8 byte offset.
resolution = None if occurrence is None else occurrence.resolution()
result = {
    "status": None if resolution is None else resolution.status.kind,
    "targets": [] if occurrence is None or occurrence.definitions is None else [
        {"type": obj.typeDisplay(),
         "origins": [origin.kind for origin in obj.origins()]}
        for obj in occurrence.definitions[:10]
    ],
}
```

Use `s.project()` to traverse loaded modules, contextual packages, files,
dependencies and configuration. Module `nativeLibraries()` reports native linker
names and search directories separately from Cangjie dependencies; `workspace.sdk`
reports the SDK selected for this revision, including its version and support
channel when known. `occurrence.contextualFile()` retains the lookup
context; `visibleNames()` lists scope candidates and `lookup(name, namespace)`
applies native resolution precedence. Dependency permission, written imports and
exports are separate queries. Check availability/cycle flags and explicit gaps.

`occurrence.resolution().call` preserves final call evidence, including
`signature()`, `bindings()` and `argumentParameters()`. Handle absent calls and
non-success status before inspecting these values. `obj.incomingCalls()`,
`outgoingCalls()`, `usages()` and direct hierarchy queries retain semantic
identities, contextual sites and coverage omissions.

For syntax, use `s.syntaxAt(a.fileId(path))`, then `root()`, `children()` or
`descendants()`. `kindName()`, `text()` and `location()` describe exact nodes and
tokens. `mappings()` returns exact HIR relationships; `obj.syntaxOrigins()` walks
back, distinguishing source, synthetic and unavailable syntax. Node `pointer()`
handles are tree-free and resolve only in a tree from the same semantic analysis.
Select and bound nodes before returning their text or mappings.

For example, select written call expressions and return bounded source:

~~~python
a = workspace.analysis()
s = a.semantic()
path = "src/main.cj"
calls = [node for node in s.syntaxAt(a.fileId(path)).root().descendants()
         if node.kindName() == "CallExpr"]
result = {"calls": len(calls), "source": source_excerpts(
    a, [(path, node.location().fullRange) for node in calls], max_bytes=8000)}
~~~

`kindName()` uses names such as `CallExpr` and `PropDecl`; inspect a bounded set
of actual node kinds when an unfamiliar filter returns nothing. `location()`
returns `SemanticLocation` with `fullRange` and `focusRange`, not `range`
(see `loupe/semantic.pyi`). The example selects source syntax, not resolved callees:
use occurrence resolution or inference for call targets. Narrow to the relevant
member for a large file; nested call ranges can overlap.
