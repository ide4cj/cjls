# Locate written signature types

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
