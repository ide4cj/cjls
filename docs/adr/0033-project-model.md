# ADR-0033: A project is a model of loupe's, found from `cj-project.json`, `cjpm.toml` or loose files by a module of its own

Status: accepted, 2026-10-02

## Context

- Name resolution (#48) needs to know which files make which package, which packages make which module, what a module may import, and what `@When` is evaluated against. cjpm has no `cargo metadata`, and not all Cangjie is built by cjpm: `std` itself is built by CMake, `std.core` with `--no-prelude`, its files picked per backend (#69).
- To cjc a module is no unit of its own: `moduleName` is the first segment of a package's name (`Parser.cpp`), and `protected` stops there (`ModulesUtils.cpp`). What cjpm calls a module is a unit of the build: a root on disk, its dependencies, how it is built.
- With every file `Low` (D30), a keystroke re-verifies every edge of a query over the whole workspace. A deleted file is an empty text (A5), so the texts cannot tell which files a package has.
- R1 splits the same work in three: `ProjectJsonData` (the file), `ProjectJson` (resolved), `CrateGraph` (what the analysis takes), the last in `base-db`, the loaders in a crate of their own.

## Decision

- **The model is loupe's** (`loupe.db`): plain values, no serde, no IO — `ProjectModel` of `ModuleModel`s (named after their root package), `PackageModel`s with their files, `BinaryModel`s, a `Cfg`. Every way of finding a project comes down to it.
- **It is inputs**: `Project` (singleton, `High`), a `Module` and a `Package` per name, never dropped, each with its own fields; a package's files are a field of its own. `setProject` sets only what differs from what it set last. A module's durability is `Low` for the user's, `Medium` for a dependency's, `High` for `std`, and its files are set with it.
- **Finding it is `project_model`'s**, a module on `loupe`, `fjson`, `ftoml`, `stdxx`: loupe reads no JSON or TOML (D5, D3). Per root, the first there is: `cj-project.json` in it; `initializationOptions.linkedProjects` under it; `cjpm.toml` (workspace members, `src-dir`, path dependencies as modules that are no members, `bin-dependencies` of the host's target); loose files, a package per `package` line, a module per root package. A manifest that cannot be read is told, and the next way taken. The file is `ProjectJson` (layer 1); lowering it is layer 2 and produces the model directly: the resolved project has nothing the model lacks.
- **`cj-project.json`**: paths relative to the file, `${VAR}` from the environment; a package's files relative to its directory, which its name gives under the module's root unless `dir` says otherwise. Listed `packages` are all the module has; without them, one per directory holding a `*.cj`. `std` is the SDK's `modules/<target>/std` unless a module or a binary is named so.
- **Projects of several roots are merged**: a module of a name seen before adds its packages, a package its files.
- **The server loads the model's files**, not every `*.cj` under the roots (D30): a `build.cj` is no package's. A `.cj` come or gone, or a manifest changed, finds the project again; watchers cover `cjpm.toml` and `cj-project.json` too.
- **`cjls project [dir]`** prints the model as `cj-project.json`, every default written out; no arguments serves LSP, an unknown command exits 2.

## Consequences

- A cjpm project is seen as cjpm builds it; cjls itself is 15 modules with their dependencies and `stdx`.
- Git and version dependencies are left out, and said so: they are on disk only after `cjpm update`. `build.cj` and cjpm's `cfg.toml` are not read. One cfg for the whole project, the host's unless the file says otherwise.
- `cjpm.toml` is read with hand-written renames and `?T` defaults until #110.
- Nothing reads `Project` yet: #48 is its first query. `.cjo` declarations are #68.
