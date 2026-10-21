# ADR-0124: References are searched per request in the files a declaration is visible from whose text names it, no index of uses kept

Status: accepted, 2026-10-20

## Context

- `textDocument/references` (#387) asks for every name of the workspace meaning what one name does. `highlightRelated` answers it for one file: the names spelled as it, then those of them `classifyName` says mean it.
- Two designs are in use. R1, ty (`references_for_search`), Roslyn and IntelliJ search per request: the files a declaration may be named from, those of them whose text names it, then resolution in those only. R4, gopls and clangd keep an index of uses by a symbol's id, built by a batch analysis of a package (cjc's typed AST, `go/types`, clang's), and keep it fresh: R4 compiles the stale dependents again before it answers, clangd's background index may lag.
- cjls has no batch analysis to build such an index from: a body is inferred when asked (D55), and calca already keeps what was asked until a write changes it.
- cjc sees a top-level `private` declaration in its file only (`undeclared identifier` from another file of the package, 1.3.0-alpha.20261002); `Visibility.isSeen` lets the package see it.

## Decision

- **No index of uses: a search per request**, R1's `FindUsages` in cjls's terms (`loupe.findReferences`): the files of the scope, those whose text has one of the names searched (`mentions`, over the rope's chunks), and in each `highlightRelated`'s pass.
- **The scope by what may name it** (`searchScope`, R1's `search_scope`): a local, the file of its body; a type parameter, the file asked in; a `private` declaration, its file, a member's as a top-level one's; a member of any other visibility, every file of the project, as a value of its type goes where its type is never named; any other declaration, the packages that see it (`isSeen`) in the modules that may import its (`PackageIndex.scopes`). The file asked in first, the project's order after.
- **The names searched**: the one asked about and the name the declaration gives; in each file, the aliases its imports give it (`import a.foo as bar`), which `classifyName` resolves to it. R1 does not follow aliases (its #14079).
- **No hierarchy yet**: a member's overrides and what it implements are #390's.

## Consequences

- Nothing to keep fresh: a write leaves the parses and inferences it did not change, and a search after it reads them again.
- A request costs a scan of the scope's texts and the inference of the bodies in the files naming the name: a common member's name (`size`) is most of a large workspace. #388 replaces the scan with an index of each file's identifiers, a tracked function, measured by a scenario of `tests/perf`.
- A request is cancelled by a write or the client as any query is (D8, D122): every file goes through calca.
- A member's scope is the whole project even when its type is internal: a superset, which the text and resolution narrow.
- What a macro declares has no text to find (#175).
