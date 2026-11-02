# Inference recipes

Each block is an independent `runPython` script. Replace the sample path with
a loaded source file. Native result objects must be projected to JSON values.

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

