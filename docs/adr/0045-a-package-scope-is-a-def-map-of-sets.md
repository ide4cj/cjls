# ADR-0045: A package's scope is a def map of sets, its declarations named by an interned `DefId`

Status: accepted, 2026-10-05

## Context

- D44 builds a `defMap` per package; a package is a source one (`Package`) or a compiled one (`BinaryPackageFile`, D38), as an item's file is either (`ItemFile`).
- What cjc 1.3.0-alpha.20260918 does, case by case (#48, step 2 and 3): a package has one namespace across its files (`class A` and `func A` redefine, in one file or two); functions overload, across files too; a top-level `private` is seen in its file only, yet takes its name in the package (`private class P` in one file and `class P` in another redefine); an enum's constructors are a level under the package's declarations (`func Red` beside `enum Color { | Red }` is no redefinition, and `Red` is the function); two enums' constructors of one name are an error at the use only.
- An `internal import` or `public import` re-exports: it is seen in every file of its package, not only its own, unlike a plain `import` (`ImportManager::AddImportedDeclsForFile` keeps re-exports in the package's map). D44 said "an import is its file's".
- R1 names a definition by its file and its id in the `ItemTree`, interned (`ItemLoc` → `FunctionId`, …), and keeps three namespaces, one definition each.

## Decision

- **`defMap(db, PackageRef)`**, `PackageRef` either kind of package, as `ItemFile` is either kind of file: one query whatever a package came from.
- **A declaration across files is a `DefId`**: its `ItemFile` and `ItemId`, `@CalcaInterned`. What is keyed by a declaration (a signature, a body) is keyed by it. Not a tracked struct (salsa's, R2's; #14 §8): `ItemId` is already stable under edits (D34), a query per field stands for tracking by field, and an interned id is made anywhere (from a `.cjo`, from a cursor) without running the query that would have created it.
- **One map of names to sets**, every declaration with its visibility; a `private` one too, left out by the lookup from another file. A name redefined is reported by the map itself, against every declaration after the first that is not a function or comes after one that is not: it is a fact of the declarations, not of a use. An ambiguity (two enums' constructors, later two imports) is the use's.
- **The constructors are a map of their own**, under the names, with their enum's visibility.
- **A package's scope will hold its re-exports** (step 4): the scope of a file is its package's declarations, then its plain imports with its package's re-exports, then the prelude, each level shadowing those under it but for functions, which overload across them (N13, N14). This corrects D44's "an import is its file's", which holds for a plain `import` alone.

## Consequences

- An edit inside a body leaves the item trees, so the def map and what read it, alone (`DefMapTest`).
- `DefId`s interned by a query of `Low` files are collected once unused (D18); a result holding one keeps it alive by being read.
- An overload added before another moves the later one's `ItemId` (D34), so its `DefId`: what was keyed by it runs again under the new one.
- cjc reports a redefinition against the `private` one of two (step 3's `a5`); the map reports the later one in the package's order of files.
- A declaration's fields of `DefId` need the database: the lookup takes it.
