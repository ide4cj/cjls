# Discover an unfamiliar member

Use the server's documented API first. Inspect only the object and member family
needed for an unresolved question, preferably alongside the useful query rather
than in a preliminary call. For an unfamiliar signature-related method:

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

If runtime discovery is insufficient, a checkout contains type registration in
[python_types.cj](../../../src/python_types.cj), workspace bindings in
[python.cj](../../../src/python.cj), revision methods in
[analysis.cj](../../../src/analysis.cj), and native declarations in
`modules/loupe/src`. These source links require a checkout. The running executable
may differ from a separate source checkout.
