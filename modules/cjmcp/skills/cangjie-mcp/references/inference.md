# Inference recipes

Each block is an independent `runPython` script. Replace the sample path with
a loaded source file and `target` with the intended declaration name. Narrow
ambiguous names by owner or source position; do not choose the first overload.
Native result objects must be projected to JSON values.

## Read expressions with inferred types

`body.exprs`, `inferred.exprs` and `expressionRanges` use the same expression
indices. A null inferred entry means the expression is not a value; it differs
from a present `Ty` whose kind is unknown. A null range means that this convenience
API cannot locate it in the declaration's source file (synthetic or expanded
origin). Use `loweredBody().sourceMap` when expansion provenance matters.

```python
analysis = workspace.analysis()
path = "src/main.cj"
name = "target"
matches = [definition for definition in analysis.declarations(path)
           if (item := analysis.item(definition)) is not None and name in item.names]
if len(matches) != 1:
    raise ValueError(f"Expected one declaration named {name}, found {len(matches)}; narrow the target")
definition = matches[0]
source = analysis.text(path).encode("utf-8")
inferred = analysis.infer(definition)
spans = analysis.expressionRanges(definition)
expressions = [
    {"text": source[span.start:span.end].decode("utf-8"),
     "type": None if ty is None else analysis.typeText(ty)}
    for span, ty in zip(spans, inferred.exprs) if span is not None
]
result = {"expressions": expressions[:10], "located_total": len(expressions),
          "unlocated": sum(span is None for span in spans),
          "omitted": max(0, len(expressions) - 10)}
```

`typeText` prints `{unknown}` for several distinct cases. When the distinction
matters, inspect the native enum rather than that display string:

```python
analysis = workspace.analysis()
path = "src/main.cj"
name = "target"
matches = [definition for definition in analysis.declarations(path)
           if (item := analysis.item(definition)) is not None and name in item.names]
if len(matches) != 1:
    raise ValueError(f"Expected one declaration named {name}, found {len(matches)}; narrow the target")
definition = matches[0]
types = analysis.infer(definition).locals
rows = []
for ty in types[:10]:
    kind = analysis.typeKind(ty)
    if isinstance(kind, TyKind.ErrorTy):
        state = "user_error"
    elif isinstance(kind, TyKind.TodoTy):
        state = "unsupported_analysis"
    elif isinstance(kind, TyKind.UnknownTy):
        state = "missing_input_or_inference_limit"
    else:
        state = "known"
    rows.append({"type": analysis.typeText(ty), "state": state})
result = {"locals": rows, "total": len(types),
          "omitted": max(0, len(types) - len(rows))}
```

## Inspect selected callees

The `CalleeTarget.expr` index identifies the callee expression; a call's outer
`CallExpr` is not generally that expression. The same declaration may occur more
than once. Initializer targets are marked separately from ordinary callees.

```python
analysis = workspace.analysis()
path = "src/main.cj"
name = "target"
matches = [definition for definition in analysis.declarations(path)
           if (item := analysis.item(definition)) is not None and name in item.names]
if len(matches) != 1:
    raise ValueError(f"Expected one declaration named {name}, found {len(matches)}; narrow the target")
definition = matches[0]
targets = analysis.infer(definition).callees
rows = []
for target in targets[:20]:
    callee = analysis.item(target.decl)
    rows.append({
        "callee": [] if callee is None else callee.names,
        "callee_expression": target.expr.index,
        "initializer": target.isInitializer,
    })
result = {"callees": rows, "total": len(targets),
          "omitted": max(0, len(targets) - len(rows))}
```

