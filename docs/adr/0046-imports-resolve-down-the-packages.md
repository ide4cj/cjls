# ADR-0046: Imports resolve down the packages, a package's exports a query of their own

Status: accepted, 2026-10-05

## Context

- D45 gave a package's own declarations (`defMap`) and left its re-exports for step 4 of #48. An import names what it brings by its full path; what one package imports from another is that package's declarations and its re-exports.
- R1 resolves a crate's imports to a fixed point (`DefCollector`): a `use` may name what another `use` of the crate brought, and macros add items while it runs.
- cjc has no fixed point. An import names a package by its full name, and packages import one another in no cycle (cjpm rejects one, a package importing itself too). `CjoManager::AddPackageDeclMap` goes depth first down the packages, and a package's `declMap` holds its declarations and its re-exports. It checks a re-export's visibility against the package that imported it first, guarded by `visited`.
- What cjc 1.3.0-alpha.20260918 does, case by case (#48, step 4; N28–N38): re-exports chain and globs carry them. `import m.p.q` is the package `m.p.q` if there is one, else `q` of `m.p`, and a declaration named like a sub-package is an error. A package is not re-exported. An alias re-exports the alias alone. A package's own `X` and the `X` it re-exports are both exported, an ambiguity at the importer's use. A declaration narrower than its re-export is left out silently. An enum's constructor is not imported by its name.

## Decision

- **`packageExports(db, PackageRef)`**, a query over `defMap`: a package's declarations but the `private` ones, and its re-exports resolved, each with the visibility of its import. One name is a set of both, a declaration in it once. `defMap` stays what a package declares (D45).
- **The chain of queries is the fixed point**: a package's exports read those of the packages it re-exports from, as cjc's recursion does. A cycle of re-exports, the user's error, is a cycle of queries; its fallback (A14) is empty exports marked `cyclic`, and an import of them is an error.
- **A re-export keeps its import's visibility and is filtered at the importer**, by how the importer stands to the re-exporting package, as D45 leaves `private` to the lookup. It does not depend on who imports first, as it does in cjc.
- **`packageIndex(db)`**, one query over `Project`: packages by full name, who each is of (a module or a binary), and what each module may import from (itself, its deps, `std`). A `.cjo`'s re-exports find a package of any binary, preferring their own.
- **`resolveImport`** is a plain function from one path of an import to a package, the names it brings, or why it brings nothing. `packageExports` uses it for re-exports, and a file's scope (step 4b) will use it for its plain imports.

## Consequences

- A declaration added to a package runs again the exports of the packages re-exporting from it. Those that re-export another name come out equal, and what read them does not run again (`ImportsTest`).
- A package and a declaration of one name are not told apart by the index alone: the path is the package's first (N30). Reporting the declaration is left to the file's scope (4b), with the other diagnostics of imports.
- The cycle of packages through plain imports is no cycle of queries and goes unreported for now, as is an import of the package itself.
