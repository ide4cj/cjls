# ADR-0047: A file's scope reads its globs at the lookup; the prelude is a glob of every file

Status: accepted, 2026-10-05
Amends ADR-0045: the prelude is a glob at the level of the imports, not under them

## Context

- D45 and D46 gave what a package declares (`defMap`) and what it shows its importers (`packageExports`). What a name means in a file needs its imports too: its plain ones, its package's re-exports (N11), and the prelude.
- D45 put the prelude on a level of its own, under the imports. cjc 1.3.0-alpha.20260918 does not: it gives every file an implicit `import std.core.*`, and a glob's, an explicit import's, a re-export's or a package alias's `String` against the prelude's is "ambiguous use", "found candidate from implicit imported package 'std.core'" (N39, #48 step 4b). A package compiled `--no-prelude` (`std.core`) has none.
- What else cjc does at a use (N40–N46, N49): a package's function hides an imported type as a value but not as a type, so a lookup is by where the name stands; an imported package is a name like the others; constructors are under every name, imported ones included, and the expected type chooses among them.
- R1 copies every name a glob brings into its module's `ItemScope`, once, in the fixed point. A file in Cangjie globs whole packages (the prelude in every file, `std.collection.*`, a module's own packages), so copying is per file.
- Both were built and measured on this repository as #152 found it, its 37 149 identifiers (`ScopeBench`, and a measurement of the heap held, on Linux): a map per file with every glob copied holds 180 434 names, ~43 MiB, against 1 758 and ~4 MiB; looking every identifier up costs 20 ms against 79 ms, but a declaration added to the package the most files glob costs 389 ms against 106 ms, its importers' maps all made again.

## Decision

- **A file's scope is three levels**: the package's declarations (`defMap`, a `private` one of another file not seen), then the imports, then the constructors, the package's before the imported ones. The first level that has the name decides, but for functions, which gather over the first two (N14). The imports are one level: the file's plain imports, its package's re-exports and the prelude, none shadowing another (N16, N39).
- **A glob is kept as its package**, not copied: `fileImports` (a file's plain imports, the prelude among their globs) and `packageImports` (a package's re-exports) hold the names of explicit paths and the packages of globs; `ImportLevel` reads each glob's exports by the name looked up. A declaration added to a globbed package leaves them equal, and what read them does not run again.
- **A lookup says where the name stands** (`Namespace.Types` or `Values`) and answers one of: declarations (one, or overloads), a package, an ambiguity, constructors (for the expected type to choose), nothing. An ambiguity is the use's, never the import's (N15, N17).
- **The diagnostics of a file's scope are a query of their own** (`scopeDiagnostics`), kept in `loupe` until they are published: an import that brings nothing, a package importing itself (N47), a cycle of packages (N36, through `onImportCycle`, whose fallback marks the packages on it), a name shadowed by a declaration that is not a function, a name imported by two paths (N48), a declaration named like a sub-package (N30). Not cjc's "shadowed" for a `private` declaration of another file, which shadows nothing (N49).

## Consequences

- A lookup costs one read of the exports per glob of the file; a query reading names is memoized above it, so it is paid when that query runs again.
- A declaration added to or taken from a package runs again the lookups through its globs, not the scopes of the files globbing it.
- The prelude is found by name (`std.core` in the package index): without an SDK there is none, and the names of `std` do not resolve.
- A macro's declarations are not in the item trees: a name a macro declares does not resolve, and an import of it is "not accessible".
