# ADR-0053: The `extend`s of every package are indexed by type; which of them a file sees is decided at the lookup

Status: accepted, 2026-10-06

## Context

- D50 and D52 look members up among the `extend`s of two source packages, the body's and the type's: those of a `.cjo` (`Int64.Max`, `std.collection`'s), and those seen through an interface the file imports (`ErrorCode.REQUEST_FAILED` through `cjls.lsp_types`' `extend ErrorCode <: LSPErrorCodes`), are not found (#48 step 7b).
- cjc 1.3.0-alpha.20260918 (N81–N87): an `extend` of the body's package is seen; one of the type's package, `std.core` for a type of the language, wherever the type is, its import not needed; one of another package, which can only be an interface's (N83), in a file importing one of the interfaces it lists, by name, alias, glob or a re-export of its package, and the type; then only its interfaces' members are accessible. `sealed` is `public` (N87).
- cjc keeps one map from a type to its `extend`s, over every package the compilation loads, source or `.cjo` (`TypeManager`'s `declToExtendMap`, `builtinTyToExtendMap`), and filters it at each lookup by the file (`ImportManager::IsExtendAccessible`); a member it found is checked after the lookup (`IsExtendMemberAccessible`), and so are the type arguments (N86, `FilterTargetsInExtend`). rust-analyzer (R1) takes a type's inherent `impl`s from its crate and its trait `impl`s from an index over the dependencies, filtered by the traits in scope: the same shape.

## Decision

- **The `extend`s of every package of the project are one query, by the type each extends** (`extendsByType`), made of each package's (`packageExtends`, now of a `.cjo` too: its type read from `Decl.type`). Gathering them from the file's imports instead (R1's traits in scope) would be smaller, and as right given N83, but a second way to the same set; cjc's map is what the rules are written against.
- **Which of them a file sees is decided at the lookup** (`isExtendSeen`, cjc's `IsExtendAccessible`): `memberLookup(from:)` takes the file, not the package.
- **A member of an `extend` seen through an interface is found whether or not the interface declares it**: whether it is accessible is a check at the use, as D52 leaves a member's modifiers (N80).

## Consequences

- An edit adding or removing an `extend` anywhere runs `extendsByType` again; one leaving the `extend`s of its package equal stops at `packageExtends`.
- `Int64.Max`, `Int64.parse` with `std.convert` imported, and the members an imported interface brings resolve. On this repository every name after a `.` that names alone can tell resolves, but those a macro declares (D47).
- An implementation is not told from what it implements: `C.e()` finds the `extend`'s `e` and its interface's (step 8). Nor `extend G<Int64>` from `G<String>`'s (N86): both are found.
