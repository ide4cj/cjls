# ADR-0044: Resolution is layered as rust-analyzer's, a definition map per package; members, overloads and `extend` are inference's

Status: accepted, 2026-10-05

## Context

- Every semantic request asks what a name means (#48). Three kinds of names answer differently: a name in a signature by the file's scope (imports, the package, the prelude), a local by the scopes of a body, a member (`x.size`) or an overload (`log(n)`) by types.
- rust-analyzer (R1) layers it as queries, each on the ones under it: `ItemTree` (a file) → `DefMap` (a crate, imports to a fixed point) → `Body` and `ExprScopes` (a body) → `InferenceResult` (a body). An edit in a body leaves the item tree equal, and nothing above it runs again. Rust has no overloading and no subclassing: a name in a scope is one definition.
- cjc (R3) runs Sema over a whole package at once, after `ImportPackage` and `MacroExpand`; R4 runs that pipeline per change. K2 (R7), and R9 after it, advance each declaration through lazy resolve phases (imports, supertypes, types, …, body; R9 adds one for `extend`): phases are state on a declaration, and R9 drops its whole session on a change.
- In Cangjie a package is one namespace across its files, but an `import` is its file's. cjc rejects packages importing each other in a cycle (`module_unsupport_circular_dependencies`, after `PackageManager`'s topological sort).
- D34 gave the item tree; D38 lowers a `.cjo` into the same one.

## Decision

- **Layers as R1's**, each a query keyed by an entity (A2): `itemTree` (a file, D34) → `defMap` (a package) → a signature (an `ItemId`) → a body and its scopes (an item with a body) → inference (the same). A file's scope is its imports, then its package's `defMap`, then the prelude.
- **A `defMap` per package**, not per module: it is Cangjie's unit of namespace and of import. An import of another package reads that package's `defMap`; a package's exports changing runs again only the packages importing it.
- **A name in a scope is a set of definitions**: overloads are one name.
- **Members, overloads and `extend` are inference's**, after R6 and R7 inside that layer; R7's phases are not taken: state on a declaration and a session dropped per change do not fit calca's queries.

## Consequences

- An edit in a body runs again that body's lowering and inference alone; a changed modifier or name runs again its package's `defMap`, and those of the packages importing it.
- A re-export across packages (`public import`) is a chain of queries, not one fixed point.
- A cycle of packages is the user's error and a cycle of queries: `defMap` gets a fallback (A14) that leaves the imports closing it unresolved, and reports the cycle as cjc does.
- Reading a `defMap` whole runs again every body of the package when it changes; finer queries (R2's, per name) only when measured to be needed.
