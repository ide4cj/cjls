# ADR-0053: The `extend`s a file may see are looked for in the packages of its interfaces; which of them it sees is decided at the lookup

Status: accepted, 2026-10-06

## Context

- D50 and D52 look members up among the `extend`s of two source packages, the body's and the type's: those of a `.cjo` (`Int64.Max`, `std.collection`'s), and those seen through an interface the file imports (`ErrorCode.REQUEST_FAILED` through `cjls.lsp_types`' `extend ErrorCode <: LSPErrorCodes`), are not found (#48 step 7b).
- cjc 1.3.0-alpha.20260918 (N81–N87): an `extend` of the body's package is seen; one of the type's package, `std.core` for a type of the language, wherever the type is, its import not needed, an interface listed or not (`extend Float64 { fromBits }`); one of another package in a file importing one of the interfaces it lists, by name, alias, glob or a re-export of its package, and the type; then only its interfaces' members are accessible. An `extend` of an imported type lists only its own package's interfaces (N83): so one of a third package is always an interface's, and a file sees it only if it imports from that package. `sealed` is `public` (N87).
- cjc keeps one map from a type to its `extend`s over every package the compilation loads (`TypeManager`'s `declToExtendMap`), filtered at each lookup by the file (`ImportManager::IsExtendAccessible`): a batch compiler loads all of them anyway. rust-analyzer (R1) looks for a type's inherent `impl`s in its crate and goes from the traits in scope to their `impl`s: what it reads is what the file can reach.

## Decision

- **The `extend`s of a type a file may see are looked for in few packages**: the file's, the type's (`std.core` for a type of the language), and those of the interfaces its imports bring (`extendPackagesOf(pkg, file)`, a query per file, made of `interfacePackagesOf(pkg)` for a glob), R1's traits in scope; each package's `extend`s by type are `packageExtends`, of a `.cjo` too (its type read from `Decl.type`).
- One index of every package's `extend`s, as cjc's (A), was built and measured first: it found the same on every name after a `.` of this repository (15 820, identical answers) and the fixtures, but lowered every `.cjo` of the project on the first lookup, and ran again on any `extend` changed anywhere. An IDE reads what the file reaches.
- **Which of them a file sees is decided at the lookup** (`isExtendSeen`, cjc's `IsExtendAccessible`): `memberLookup(from:)` takes the file, not the package.
- **A member of an `extend` seen through an interface is found whether or not the interface declares it**: whether it is accessible is a check at the use, as D52 leaves a member's modifiers (N80).

## Consequences

- An edit adding or removing an `extend` runs again the lookups of files that may see it, not every one; an import changed runs that file's `extendPackagesOf`.
- `Int64.Max`, `Float64.fromBits`, `Int64.parse` with `std.convert` imported, and the members an imported interface brings resolve. On this repository every name after a `.` that names alone can tell resolves, but those a macro declares (D47).
- An implementation is not told from what it implements: `C.e()` finds the `extend`'s `e` and its interface's (step 8). Nor `extend G<Int64>` from `G<String>`'s (N86): both are found.
