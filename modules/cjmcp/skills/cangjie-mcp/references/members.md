# Inspect members, outlines and builtin documentation

`allMembers(definition)` accepts a type, an `extend` or a member whose enclosing
type should be inspected. It returns native `MemberTarget` variants, preserving
overloads, inherited members, extension visibility and lookup shadowing.
Select the intended declaration by name; if it is ambiguous, narrow it by
containing type or source position rather than choosing the first match. This
example selects a class, excluding its same-named primary constructor; adapt the
kind filter for another declaration category.

```python
analysis = workspace.analysis()
path = "src/main.cj"
name = "target"
matches = [definition for definition in analysis.declarations(path)
           if (item := analysis.item(definition)) is not None
           and name in item.names and isinstance(item.kind, ItemKind.Class)]
if len(matches) != 1:
    raise ValueError(f"Expected one declaration named {name}, found {len(matches)}; narrow the target")
definition = matches[0]
targets = analysis.allMembers(definition)
rows = []
for target in targets[:20]:
    item = analysis.item(target.field0)
    names = [] if item is None else item.names
    if isinstance(target, MemberTarget.MemberDecl):
        rows.append({"kind": "declaration", "names": names})
    elif isinstance(target, MemberTarget.MemberParam):
        rows.append({"kind": "parameter", "owner_names": names,
                     "local_index": target.field1.index})
    else:
        raise ValueError("Unrecognized MemberTarget variant")
result = {"members": rows, "total": len(targets),
          "omitted": max(0, len(targets) - len(rows))}
```

A `MemberDecl` carries the member's declaration ID in `field0`. A `MemberParam`
carries its owning declaration in `field0` and constructor parameter `LocalId`
in `field1`; the owner's names are not the parameter's name. Keep the native
targets inside Python for further queries; the JSON projection is a summary.
`fileSymbols(path)` gives the full outline in declaration order. Builtin docs
come from `builtinTypeDoc`, `builtinAnnotationDoc` and `builtinMacroDoc`; use
names without `@`, and handle `None` for unknown names.
