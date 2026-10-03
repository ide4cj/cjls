# ADR-0038: A binary package is an input of its own, its `.cjo` outside `Vfs`, lowered into the item tree; the SDK is found without `CANGJIE_HOME`

Status: accepted, 2026-10-03

## Context

- Nothing from `std` resolves without its declarations (#68, #119). D37 reads a `.cjo`; D33 says where `std` and the `bin-dependencies` are, as directories of `.cjo` and packages one by one.
- `Vfs` holds `?Rope`: what an editor may hold as well, the overlay of an open document, `didChange`, changes folded until `takeChanges` (D2). A `.cjo` is never opened, edited or parsed as text.
- Resolution (#48) is to read one model of a definition, wherever it comes from (R1's `ItemTree`, D34). A `.cjo` has its declarations resolved already, by `FullId` (a package and an export id), and keeps them in `allDecls`, a type's members by index, a re-export as an `ImportSpec` only.
- An editor launches the server with the environment of the desktop: `CANGJIE_HOME` is set by `envsetup.sh` in a shell, rarely there. cjsdk installs toolchains under `~/.cjpm/toolchains`.

## Decision

- **The bytes stay out of `Vfs`.** `@CalcaInput BinaryPackageFile { module, name, path, bytes }`, one per package of a binary, never dropped, and the singleton `BinaryPackages`, `std`'s first. `std`'s are `High`, a dependency's `Medium` (A17). Widening `Vfs` would make every reader of `fileContents` handle bytes it never wants.
- **Read when the project is loaded** (`readBinaries` in the loader), within the budget of the text (A16), the binaries first: without `std` nothing resolves, and a root far wider than a project would take the budget before it. A file whose size and mtime are what it was read with is not read again; its bytes are set only when they differ (A4: on the root handle, outside queries). A `.cjo` changes with the SDK or a manifest: the reload of the project there is already.
- **A package that cannot be read** (not a `.cjo`, another major) is left out at the load and logged; one that throws while it is lowered has no trees. Its names do not resolve, and nothing fails. `std` of another major, or no SDK, is told once by `window/showMessage`.
- **Lowered into the item tree.** `binaryItemTrees(db, pkg)` is a tree per entry of `allFiles`, declarations grouped by the file they begin in, ids by D34's hash of parent and name (an `extend` named by its export id), imports the file's re-exports alone. `ItemKind.BuiltIn` is a type built into cjc. What cjc added is left out but for a primary constructor and the fields it declares, which a source file has too. `binaryExports` maps an export id to its item, `binaryDecl` an item back to its `Decl`, read again from the bytes when asked: signatures are queries of their own (#48), and a binary one's types are resolved already. A definition is in an `ItemFile`, `Source` or `Binary` and its file's index; resolution reads its tree and never knows which.
- **The SDK**, the first that is a directory: `initializationOptions.cangjieHome` (the editors pass it from a setting of their own); `CANGJIE_HOME`; cjsdk's `~/.cjpm/toolchains/default`; two up from `cjc` on `PATH`, links followed. It is what `${CANGJIE_HOME}` expands to in every path of a project, not only where `std` is found, for the server and `cjls project` alike.

## Consequences

- std and stdx take about 21 MB of a 128 MB budget; under the runtime's default heap the budget is 16 MB, std's 12 MB, and stdx does not fit: the server re-executes with 2 GB (D31).
- A binary item has no position: go-to-definition into `std` needs its declarations printed as text, read-only, with a map from each to its range (#50).
- The editors' setting for `cangjieHome` is theirs to add (D32).
