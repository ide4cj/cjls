# ADR-0048: A signature is a query of its declaration; a path in a type resolves to declarations, not yet to types

Status: accepted, 2026-10-05

## Context

- D47 says what a name means in a file. A declaration's types (`func f(x: a.C<T>): ?U where T <: I`) name things of three more kinds: its type parameters and those of the type or `extend` it is a member of, packages imported by name before a type, and `This`.
- The item tree has no signature, on purpose (D34): an edit to a type would change it, and `defMap`, the exports and every scope above them would run again.
- rust-analyzer kept `TypeRef`s in its `ItemTree` until 2025, then moved them to a query of each declaration (`hir_def::signatures`, with an `ExpressionStore` and its source map). Its `Resolver` resolves a path to declarations (`resolve_path_in_type_ns`, `TypeNs`); `hir-ty` lowers that to a `Ty`. cjc does both at once (`GetTyFromASTType`).
- cjc 1.3.0-alpha.20260918 on paths in types (#48 step 5, N51–N58): a qualifier is a package the file imports by its name or alias, never a path from the root, a sub-package through its parent, its own package, or the package of an imported type; as a qualifier it wins over a type parameter, a declaration shadowing the import and an imported type; as a type a package is nothing; a type has no types in it.

## Decision

- **A signature is a query of its declaration** (`signatureWithSourceMap(db, DefId)`), not part of the item tree: its types lowered to `TypeRef`s, each in an array and naming the others by index, and, apart, where each is written (`SignatureSourceMap`). `signature` projects the first, so an edit of the file but of the declaration's types runs nothing that read it again. A declaration of a package compiled already has an empty one: its `.cjo` has resolved its types, which inference will read.
- **A path in a type resolves to what each segment names** (`resolveTypePath`): a type (`DefId`), a type parameter (its declaration and index), a package as a qualifier; or an ambiguity, packages conflicting, nothing. No `Ty` yet: that is inference's (step 8), as `hir-ty` is rust-analyzer's.
- **The scope of a signature** (`TypeScope`) is the declaration's type parameters, then its parent's, each shadowing anything of its name (N55), then the file's (`lookUp` in `Types`). The qualifier of a path is looked up among the file's imports alone (N52), so a package is no longer a candidate in `Namespace.Types` (N53).
- **The first request is `definitionAt` in `loupe`**, on a name in a signature's type; the handler comes after #105 and #106.

## Consequences

- An edit to a body runs no resolution of signatures again; an edit to a declaration's types runs again what read that declaration's, not its package's names.
- A name in a body, a local declaration's type among them, resolves to nothing until bodies are lowered (step 6).
- A declaration of a package compiled already has no source to go to: `definitionAt` gives nothing for it.
- `This` resolves to its class wherever it is written; that it is allowed only as a class's member function's return type (N56) is for the diagnostics of signatures, not written yet.
