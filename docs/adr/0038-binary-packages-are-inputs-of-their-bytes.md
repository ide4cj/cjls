# ADR-0038: A package compiled already is an input of its `.cjo` bytes, out of the `Vfs`, read with the project and lowered into the item model

Status: accepted, 2026-10-02
Amends ADR-0033: its binaries read

## Context

- Name resolution (#48) needs the declarations of `std` and of the `bin-dependencies` (`stdx`): the SDK ships their `.cjo`, no sources. D37 reads one; D33 says where they are (`BinaryModel`).
- The `Vfs` holds what an editor may also hold: an open document's overlay, `didChange`, changes folded until `takeChanges`, `?Rope` per file. A `.cjo` is never opened, edited or parsed as text.
- `std` and `stdx` are 85 `.cjo`, about 21 MB, against a budget of 128 MB on the default heap of 2 GB (D31).
- Resolution should not know where a package came from: R1 lowers a library's sources and the workspace's into one model, R4 (cjc's `CjoManager`) a `.cjo` into the same AST its sources give.
- A spike on std and stdx (`modules/cjo/CLAUDE.md`): a re-export is an `ImportSpec` of its file, not a decl; cjc marks what it added `CompilerAdd`, the `init` and the fields a primary constructor desugars to included (cjc keeps no `PrimaryCtorDecl`); an `extend` keeps no name; a decl may begin in a file named through the package's own entry in `imports`.

## Decision

- **An input per package**: `@CalcaInput BinaryPackageFile { binary, name, path, var bytes: Array<Byte> }`, one per binary, package and path, never dropped; `Project.binaryPackages` lists those read. `High` for `std`, `Medium` for any other binary (A17). The `Vfs` is left as it is: no reader of `fileContents` handles bytes.
- **Read with the project**: `ProjectModel.cjoFiles()` lists them (every `*.cjo` of a directory, then those named one by one), `readCjoFiles` reads them within the load's budget, before the text, since every file resolves against `std` (A16). A file whose size and mtime are those it was set with is not read again; one read is set only if its bytes differ; one no longer read holds no bytes. A file that is no `.cjo` of this format (its header) is left out and logged; one that breaks further in gives no items, and nothing fails (D37).
- **Lowered into the item model**, in `loupe.hir`: `binaryItemTrees(db, pkg)` is an `ItemTree` per entry of `allFiles`, each decl in the file it began in, ids as D34's, kinds and modifiers from `DeclKind` and the attributes (cjc's defaults included). What cjc added is left out, but for what a primary constructor desugars to: its `init`, a `PrimaryInit` named as its type (as a source names it, and cjc's `identifierForLsp`), and the fields of its member parameters, `Var`s of the type. An `extend`, or a `let` of a pattern, has its `exportId` for a name in its id. A file's re-exports are its imports; what a `.cjo` only imports is resolved in its types already. `ItemKind.BuiltIn` is `Array`, `CPointer` and the other `BuiltInDecl`s.
- **Found from another package**: `binaryExports(db, pkg)` maps an `exportId` (`_CNat6StringE`, what a `FullId` into the package says) to its file and `ItemId`, and an item to its decl's index; `binaryDecl` reads that decl when asked. `ItemFile` is `Source(SourceFile)` or `Binary(BinaryPackageFile, Int64)`, `itemTreeOf` the tree of either.

## Consequences

- cjls loads its 85 binary packages with its 870 files; a warm load takes ~5 ms more (26–35 → 33 ms).
- A reload of the project (a manifest changed) reads only the `.cjo` whose stamps moved. Nothing watches the `.cjo` themselves: an update of the SDK or of a binary is seen at the next reload or restart (#141).
- A binary item's ids are stable for one `.cjo` only: an `extend`'s changes with its file's name in the `exportId`.
- A member parameter is a field of its type in a binary tree, and no item in a source one (D34): resolution finds the fields of a source type in its primary init too (#48).
- No signatures: a binary item's types are resolved `SemaTy`s already, a query of their own per item (#48). No doc comments: a `.cjo` keeps none.
- No source to show: the printer of virtual files, with a range per decl, comes with go-to-definition into `std` (#50). Finding the SDK without `CANGJIE_HOME` is still open (#68).
