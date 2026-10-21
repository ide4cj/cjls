# ADR-0139: A document open in no package is compiled alone, as cjc compiles a file: a module of its own with std

Status: accepted, 2026-10-20
Amends ADR-0088 (what a document in no package does on open)

## Context

- After D88 a document is still in no package below the root's manifest outside its `src` (a script, an example), in a directory D33 leaves out (`target`), or outside every root (opened on its own, or with no folder at all). Every scope hangs off a package (`packageOfFile`): nothing resolves there, its own locals neither (#293).
- cjc, 1.3.0-alpha.20261002: `cjc file.cj` compiles a file as a package of its own, named by its `package` line or `default`, with std (std.core implicitly, the rest by import) and nothing else; a `package foo.bar` in a directory of no such path compiles too.
- R1 answers nothing for a file in no crate unless listed in `detachedFiles`: no model here (D15).
- D67 already makes a program a module rooted at its file.

## Decision

- **A Cangjie document open that the projects found cover none of is a project of its own** (`loneFileProjects`, `ProjectSource.LoneFile`): a module rooted at the file, named after its root package, of one package holding the file alone, named by its `package` line (`default` without one), with no deps: std alone. Covered: a file of a package, of a binary's sources (std's opened by go to definition), or one a module's build leaves out (D99's inactive files stay inactive).
- **The load makes it, after the projects found (D88), from the documents' buffers**: the `package` line is read on the read loop when the load begins (`LoadRequest.packageLines`), as a loose file's is read from disk. A line changed later takes the next load, as a loose root's does.
- **Any document in no package starts a load on open, once `initialized` came** (`ServerState.inNoPackage`, beside D80's and D88's cases in `findsProjectAgain`). With no root and no linked project a load runs for the documents open alone. A blank document new in a module is given its `package` line first (D92), not after the load it begins.
- **It lives while open**: a load after it was closed leaves it out. Unlike D88's projects, nothing else is loaded for it.
- **Modules of one name share their scope of imports** (`packageIndex` unites their deps): a file alone declaring a package of the root's module's name leaves that module its deps.
- Rejected: a `Package` loupe makes for a file `packageOfFile` finds in none: a query cannot make an input, and std would need a project to come from without a root.

## Consequences

- Go to definition, hover, inference and diagnostics answer in such a file from its own names and std; the root's packages are not seen, as by `cjc file.cj`.
- One std, one budget (D31): the project is merged as D88's are, std there once; the file is open, so read already. #263 is untouched: a loose root still loads whole.
- A file alone declaring a package of the root's module's name may import that module's packages: `PackageIndex` knows a module by its name, as D88's two checkouts are known.
- Opening such a file costs a load of the workspace, files known not read again, as D88's first open does.
