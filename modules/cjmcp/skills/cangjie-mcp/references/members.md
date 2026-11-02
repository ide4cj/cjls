# Inspect members, outlines and builtin documentation

`allMembers(definition)` accepts a type, an `extend` or a member whose enclosing
type should be inspected. It returns native `MemberTarget` variants, preserving
overloads, inherited members, extension visibility and lookup shadowing.
`fileSymbols(path)` gives the full outline in declaration order. Builtin docs
come from `builtinTypeDoc`, `builtinAnnotationDoc` and `builtinMacroDoc`; use
names without `@`, and handle `None` for unknown names.
