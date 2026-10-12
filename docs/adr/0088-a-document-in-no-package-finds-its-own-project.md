# ADR-0088: A document open in no package finds its own project from its path, as R1 does on open, and that project stays loaded with the roots'

Status: proposed
Amends ADR-0033 (a project per root, and those found from documents) and ADR-0080 (its rediscovery is one case of this)

## Context

- A project is found once per root, at the root (D33). A document under the root below a `cjpm.toml` or `cj-project.json` the root's project does not list (a subproject of a monorepo, an example below a library, another checkout in `.claude/worktrees/`) is in no package: go to definition and hover answer nothing in it (#265).
- R1, read at rust-analyzer `f0eebde` (2026-10-12): `handle_did_open_text_document` queues `DeferredTask::CheckIfIndexed`; on a worker, a file whose `crates_for` is empty starts `DiscoverProjectParam::Path` (`main_loop.rs`). The project found is added to `discovered_projects_from_command`, a project of the same build file replaced, and the workspaces are fetched again with it. Nothing removes it: not `didClose`, not a folder change (`rediscover_workspaces` replaces only the projects found on disk). R1 does this only with `workspace.discoverConfig` (a command of the build system); for Cargo it finds the projects up front, in the root or above it, else one level below.
- R1 merges the workspaces into one crate graph, `CrateGraphBuilder::extend` taking a crate equal to one there already as that one: the sysroot is there once. It has no load budget.
- D80 found the project again on open for one case: a loose root cut by the budget.

## Decision

- **A document open in no package, under a root, finds its project from its path** (`projectDirOf`): the nearest directory above it, up to the root, with a `cj-project.json` or a `cjpm.toml`; for a `cjpm.toml` that a `cjpm.toml` above it lists among its workspace's `members`, that workspace. Hidden directories and `target` are gone through. As R1's `Path` discovery, with the manifests read directly instead of a command.
- **A directory that is a root, a linked project or one found already is no new project**: the document is in no package of a project loaded (a file outside `src`), and nothing is found again. The rest is D80: under a loose root cut by the budget, the root is found again.
- **On `didOpen`, the read loop only asks whether there is one, and starts a load; the load finds it**, for every document it is given in no package of the projects it found, and loads it beside them in the same load. A document opened during a load is checked at its end (D80's rule, one predicate for both: `findsProjectAgain`).
- **A project found stays loaded, with the roots' at every load, until the last root it is under is removed** (`ServerState.foundProjects`). As R1 keeps it, but for the folder: cjls drops a removed folder's files, and a project kept under it would load them again. A manifest gone is no project, until it is back.
- **One `std`, one budget**: the projects are merged as the roots' are (D33), a binary of a name seen before left out, as R1's `extend`; the load reads the files of all within its one budget (D31).
- Rejected: the projects under the root found up front (#212, and R1 for Cargo's one level down), which on `cangjie_test` would be 7 202 `cjpm.toml`; and a project of a document dropped with its last document closed, which R1 does not do and would load it again on the next open.

## Consequences

- Go to definition, hover and diagnostics in such a document answer from its package and its dependencies, its locals included; `workspace/symbol` answers from the projects found too.
- Opening the first document of such a project costs a load of the workspace, files known already not read again; one opened before the first load ends is found in it.
- Two projects with modules of one name (two checkouts of one repository) are two modules of the merged project, but imports resolve by a module's name (`PackageIndex`): a package of the other checkout may be taken. Names of the document's own package resolve.
- A file outside every root (SDK sources reached by go to definition) finds no project. #235 is to keep a found project's manifest and sources as changes of the project; #212 would find these projects up front for a loose root, and this one left for a document opened under a `cjpm.toml` root.
