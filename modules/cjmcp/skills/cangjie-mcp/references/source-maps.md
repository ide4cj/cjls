# Locate written signature types

`LoweredSignature` pairs the native `Signature` with a concrete
`SignatureSourceMap` adapter, following the same pointer boundary as `BodySource`.
Use a signature's own `TypeRefId` to locate a written type. Ranges belong to
`analysis.definitionFile(definition)`: for `ItemFile.Expansion`, read the matching
expansion text rather than the call site's file. Missing type references have
`None` ranges; binary declarations have an empty source map.

Select the intended declaration by name. If several overloads or enclosing
types share it, narrow by source position or owner before reading its signature.

```python
analysis = workspace.analysis()
path = "src/main.cj"
name = "target"
matches = [definition for definition in analysis.declarations(path)
           if (item := analysis.item(definition)) is not None and name in item.names]
if len(matches) != 1:
    raise ValueError(f"Expected one declaration named {name}, found {len(matches)}; narrow the target")
definition = matches[0]
lowered = analysis.signatureWithSourceMap(definition)
rows = [
    {"type": lowered.signature.text(TypeRefId(i)), "start": span.start, "end": span.end}
    for i, span in enumerate(lowered.sourceMap.ranges)
    if span is not None
]
result = {"types": rows[:20], "located_total": len(rows),
          "unlocated": sum(span is None for span in lowered.sourceMap.ranges),
          "omitted": max(0, len(rows) - 20)}
```
