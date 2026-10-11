# ADR-0080: A document open is in the project: loose files take the open documents and their directories first, those documents past the budget, and one opened among the files left out finds the project again

Status: accepted, 2026-10-11
Amends ADR-0031: the budget never leaves an open document out of a loose project

## Context

- A root of loose files past the load budget (D31: a sixteenth of the heap) is cut in walk order. On `cangjie_test` (213 MiB of `*.cj`) the server took 94 167 of 129 341 files, and go to definition in a document opened among the rest answered `null`: a file of no package is resolved against nothing (`packageOfFile`), whatever the editor shows (#213).
- The walk lists every directory anyway, and stops reading headers at the budget; what is left out is decided by the order it reads them in.
- R1, on `didOpen`, checks on a worker whether the file is in any crate (`crates_for`), and if it is in none finds the project again from that path (`DeferredTask::CheckIfIndexed`, `DiscoverProjectParam::Path`); a file of no crate otherwise gets the syntax alone.
- D61 loads on a thread of its own: a document opened during a load arrives after the load took its picture of the state.

## Decision

- **The loose walk takes the directories of the documents open first**, then the rest of the root in walk order, a directory taken once. An open document is taken whatever its size, its text held by the editor already; the other files of its directory count against the budget as any. Its package is what its `package` line names, as for any file, and D67's programs are found the same way: a project is still found by one walk, with one rule.
- **A project found knows whether it left files out** (`ProjectLoad.partial`); the server keeps the roots whose loose project did (`ServerState.partialRoots`).
- **A document opened under such a root, in none of the project's packages, finds the project again** (`startLoad`) with the documents open, as R1 discovers a project for a file in no crate. During a load, that load does it at its end, for a document open now that it was not given. A root whose files are all in its project finds nothing again: a document there in no package (a `target/` file) is not one the walk would take.
- **The load reads the files of the open documents' directories first**: its own budget is the walk's less the binaries', so the packages of what the editor shows are read before it runs out.
- Rejected: putting a document left out in a package of its own (R1's detached file), which would answer nothing from its siblings; and the issue's second step, loading only the open documents' packages up front and the rest on demand, which needs a loose project's packages without reading every header (#213's open question) and changes what `workspace/symbol` answers while the rest is not loaded.

## Consequences

- Go to definition and diagnostics in a document opened anywhere under a root of any size answer from its directory's package.
- Opening a document left out walks the root again (seconds on `cangjie_test`), its files not known yet the only ones read; meanwhile the document has its syntax alone, as during any load. A document opened during a load costs another load after it.
- A document left out still sees only the files of its package within the budget, beyond its directory: a loose package spread over directories past the budget is still cut.
