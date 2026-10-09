# ADR

One decision per file, ≤ 1 page: the decision and why, not how it was reached — a benchmark's table goes in the PR, the ADR keeps the result. An accepted ADR is not rewritten: a new one replaces it, saying "supersedes ADR-NNNN". In discussion `D7` ≡ `ADR-0007`.

An ADR is started by `python3 scripts/docs.py new-adr <slug> "<decision>"`, which takes the next number free on master and in the open pull requests; the number is the PR's from then on. The table below is written from the headers after the merge (D56): a PR does not touch it. What an ADR changes in an older one, short of replacing it, is an `Amends` line of the newer one's header, shown in the older one's row.

```md
# ADR-NNNN: <decision>

Status: proposed | accepted | superseded by ADR-NNNN, <date>
Amends ADR-NNNN: <what>        (none, or one per ADR it amends)

## Context
## Decision
## Consequences
```

<!-- written by `python3 scripts/docs.py index` after a merge (D56): never by hand -->

| # | Decision | Status |
|---|---|---|
| [0001](0001-files-are-ropes.md) | Files are persistent ropes; lines break at `\n` | accepted |
| [0002](0002-vfs.md) | A VFS of `FileId`s and folded changes, as rust-analyzer's | accepted; Windows paths by D12 |
| [0003](0003-modules-and-packages.md) | A module is a library that knows nothing of the server | accepted |
| [0004](0004-one-database-class.md) | One database class, no interface ladder | accepted |
| [0005](0005-loupe-knows-no-lsp.md) | The analysis API knows no LSP; handlers translate | accepted |
| [0006](0006-handlers-are-not-queries.md) | Handlers are not queries; queries are keyed by entities | accepted |
| [0007](0007-position-encoding.md) | UTF-8 columns when the client offers them | accepted |
| [0008](0008-cancellation.md) | Two cancellations, two answers | accepted |
| [0009](0009-names-of-state-and-database.md) | `ServerState` holds the `AnalysisDatabase`; only calca says `Database` | accepted |
| [0010](0010-generated-syntax.md) | Syntax kinds and typed views are generated from an ungrammar | accepted; an accessor finds a child by the tokens around it by D41 |
| [0011](0011-ci-and-releases.md) | A pinned nightly toolchain, CI on three platforms, releases from `cog bump` | accepted; no editor's tests in CI by D32; the nightly is downloaded from GitHub and checked against `.cangjie-sha256` by D62 |
| [0012](0012-drive-paths.md) | Paths are `std.fs.Path`, URIs are stdx's `URL`; Windows drives are spelled one way | accepted |
| [0013](0013-stdin-is-read-with-readv.md) | Stdin is read with `readv`, not `read`: cjc treats `read` as `@FastNative` | accepted |
| [0014](0014-diagnostics-pull-first.md) | Diagnostics are pulled; pushed, by the server after a write, only to clients that cannot pull | accepted |
| [0015](0015-reference-implementations.md) | rust-analyzer is the model, salsa the model for calca, cjc the specification; LSPServer and lin-qingying/cangjie the competitors | accepted |
| [0016](0016-editor-integrations-are-repositories.md) | Each editor integration is a repository of its own in ide4cj: `cangjie.nvim` for Neovim | accepted; how server and clients change together, and who tests which, by D32 |
| [0017](0017-lru-of-memo-values.md) | calca evicts memo values by LRU; a query result keeps pointers, never nodes | accepted; interned values by D18; eviction within a revision by D36 |
| [0018](0018-gc-of-interned-values.md) | calca collects unused interned values, and the memos keyed by them | accepted |
| [0019](0019-syntactic-highlighting.md) | Semantic tokens from the syntax tree first, in a fixed legend of LSP's own types | accepted |
| [0020](0020-no-lto.md) | The Linux binary is not linked with LTO: cjc miscompiles the stack maps under it | accepted |
| [0021](0021-weekly-releases.md) | A release every week from a green master; the first one by hand, its changelog written; versions of cjls's own | accepted; a nightly by D32 |
| [0022](0022-json-codec.md) | The wire is read and written with fjson, through serde's derives `ToJson`/`FromJson` and one `@Serde` marker | accepted |
| [0023](0023-performance-is-measured-over-stdio.md) | Speed and memory are measured over stdio, by one driver for every server | accepted |
| [0024](0024-fjson-conformance.md) | fjson is held to JSONTestSuite, vendored, and fuzzed in `cjpm test`; a lone surrogate reads as U+FFFD; 512 containers deep | accepted; `readFloat64` rounded correctly by D25; the suite fetched by D26 |
| [0025](0025-toml-through-serde.md) | TOML is read and written by ftoml, TOML 1.1 of our own, through `ToToml`/`FromToml` derived from the same `@Serde` model | accepted |
| [0026](0026-test-suites-are-fetched.md) | Third-party test suites are fetched into `.corpora/` at a pinned commit, not vendored | accepted |
| [0027](0027-incremental-builds.md) | Builds are incremental, clean on a new compiler and for a release; tests in `target/test`; CI caches `target` from master | accepted; stamps by D28 |
| [0028](0028-ci-stamps-a-package.md) | CI stamps a package's files with one mtime, made of the whole directory | accepted |
| [0029](0029-one-computation-per-memo.md) | One handle computes a memo, the others wait; a wait that closes a loop is a cycle | superseded by D35 |
| [0030](0030-workspace-loader.md) | The workspace is loaded on the read loop in one revision, under a budget of text, watched by the client; symbols are searched through a per-file index | accepted; what is loaded is the project's files by D33; what is watched, and which event finds the project again, by D58; the load on the read loop, in one revision, by D61 |
| [0031](0031-the-server-sets-its-heap.md) | Without `cjHeapSize` the server starts over with a heap of 2 GB; a load keeps a sixteenth of the heap | accepted |
| [0032](0032-one-process-for-server-and-clients.md) | The server and its editor clients change by one process: the protocol their contract, paired branches, two channels, pins bumped by a bot | accepted; the nightly's tag `nightly-build`, updated in place, by D39 |
| [0033](0033-project-model.md) | A project is a model of loupe's, found from `cj-project.json`, `cjpm.toml` or loose files by `project_model`; the server loads its files | accepted; its binaries read by D38; loose files without a `package` line are one `default` only with one `main` at most by D67 |
| [0034](0034-item-ids-and-the-item-tree.md) | An item is named by a hash of its parent and its name; a file's items are a tree with no ranges | accepted |
| [0035](0035-a-handle-closing-a-loop-gives-way.md) | A handle closing a loop of waits gives way, and the owner computes the cycle; one memo per handle otherwise as D29 | accepted |
| [0036](0036-lru-evicts-within-a-revision.md) | calca evicts by LRU as it touches, within a revision too | accepted |
| [0037](0037-cjo-files-are-read-by-generated-views.md) | A `.cjo` is read through views generated from its vendored schema, on a runtime of our own, with no verifier; the enums a patch may extend are open | accepted |
| [0038](0038-binary-packages-are-inputs-of-their-bytes.md) | A package compiled already is an input of its `.cjo` bytes, out of the `Vfs`, read with the project and lowered into the item model | accepted; a binary has sources to go to, never to resolve against, by D65; what starts a read of the `.cjo` by D68 |
| [0039](0039-the-nightly-is-updated-in-place.md) | The nightly is the pre-release `nightly-build`, made once and updated in place; immutable releases are off | accepted |
| [0040](0040-the-sdk-is-found-without-cangjie-home.md) | The SDK is found without `CANGJIE_HOME`: the editor's setting, the variable, cjsdk's default toolchain, `cjc` on `PATH`; it is what `${CANGJIE_HOME}` expands to | accepted |
| [0041](0041-accessors-are-told-by-tokens.md) | A generated accessor finds a child by the tokens between it and the children that could be taken for it; by position only for the child a rule starts with | accepted |
| [0042](0042-a-swallowed-unwind-stores-no-memo.md) | A query that swallows calca's unwinding (`catch (e: Exception)` around a fetch) stores no memo, and throws it again | accepted |
| [0043](0043-analysis-tests-are-fixtures.md) | Analysis tests are fixtures: files, a place and the answers as one text in `loupe.fixture`, written into the test by `UPDATE_EXPECT=1` | accepted |
| [0044](0044-resolution-is-layered-as-rust-analyzer.md) | Resolution is layered as rust-analyzer's, a definition map per package; members, overloads and `extend` are inference's | accepted; a re-export is its package's, not its file's, by D45 |
| [0045](0045-a-package-scope-is-a-def-map-of-sets.md) | A package's scope is a def map of sets, its declarations named by an interned `DefId`; re-exports are the package's | accepted; the prelude is a glob at the level of the imports, not under them, by D47 |
| [0046](0046-imports-resolve-down-the-packages.md) | Imports resolve down the packages, a package's exports a query of their own; a re-export keeps its import's visibility | accepted |
| [0047](0047-a-file-scope-reads-its-globs-at-the-lookup.md) | A file's scope reads its globs at the lookup; the prelude is a glob of every file | accepted; the constructors of an enum any file of the package imports are seen in each by D50 |
| [0048](0048-a-signature-is-a-query-of-its-declaration.md) | A signature is a query of its declaration; a path in a type resolves to declarations, not yet to types | accepted |
| [0049](0049-coverage-is-a-workflow-of-its-own.md) | Coverage is a workflow of its own, counted over source files (tests excluded), shown by a shields.io endpoint badge on a `badges` branch | accepted |
| [0050](0050-a-body-is-lowered-to-hir-and-scoped.md) | A body is lowered to HIR as rust-analyzer's, its scopes a query over it; the members of the type around it a level of the lookup | accepted; a macro call's arguments lowered when they parse by D59 |
| [0051](0051-o2-is-a-release-option.md) | `-O2` is in each module's `[target.<triple>.release]`, not its `compile-option`: the coverage builds with `-g`, unoptimized | accepted |
| [0052](0052-a-name-after-a-dot-is-resolved-by-names-up-to-a-value.md) | A name after a `.` is resolved by names up to a value, members looked up from a type; a value's member is inference's | accepted |
| [0053](0053-the-extends-a-file-sees-are-looked-for-in-its-interfaces-packages.md) | The `extend`s a file may see are looked for in the packages of its interfaces; which of them it sees is decided at the lookup | accepted |
| [0054](0054-a-type-is-an-interned-ty-a-signature-lowered-to-it.md) | A type is an interned `Ty`; a declaration's signature is lowered to it in one query, of a source or a `.cjo` alike | accepted |
| [0055](0055-a-body-is-inferred-locally-in-one-query.md) | A body's types are inferred locally, as cjc checks them, in one query of the body; a type not written is the body's | accepted |
| [0056](0056-the-adr-index-is-written-after-the-merge.md) | The ADR index is written after the merge by a bot; a number is taken when the ADR is started, and checked to be the only one | accepted |
| [0057](0057-type-arguments-are-inferred-per-call.md) | Type arguments not written are inferred per call, as cjc's local synthesis | accepted |
| [0058](0058-folders-come-or-gone-are-watched.md) | Everything come or gone under a root is watched, as VS Code reports a folder as one event; the server tells a directory of the workspace from the rest | accepted |
| [0059](0059-macro-arguments-are-parsed-before-expansion.md) | An expression macro's arguments are parsed as an argument list when they parse as one, before any expansion | accepted |
| [0060](0060-the-formatter-keeps-line-breaks.md) | The formatter is our own, on the syntax tree, and changes only the whitespace around the author's line breaks | accepted |
| [0061](0061-the-workspace-is-loaded-on-a-spawn.md) | The workspace is loaded on a spawn and set in batches between the messages, through a lock the read loop's handlers take too, reporting $/progress; a request meanwhile answers from what is loaded | accepted |
| [0062](0062-toolchain-from-the-github-mirror.md) | The toolchain is downloaded from the GitHub mirror, checked against sha256 pinned from gitcode | accepted |
| [0063](0063-an-overload-is-taken-by-trying-its-candidates.md) | An overload is taken by trying its candidates, as cjc | accepted |
| [0064](0064-an-operator-is-a-call-of-its-types-member.md) | An operator of a type is a call of its member, the language's own tried first, as cjc | accepted |
| [0065](0065-binary-sources-at-the-cjo-positions.md) | A declaration of a package compiled already goes to the sources of its binary, at the position its `.cjo` gives, its name checked there | accepted |
| [0066](0066-sugar-is-typed-as-cjc-desugars-it.md) | Coalescing, pipelines and compositions are typed as what cjc desugars them to, std.core named through lang items | proposed |
| [0067](0067-loose-mains-are-programs.md) | Loose files without a package line, two or more of which declare main, are a program per main, each with the main-less files of its directory | accepted |
| [0068](0068-binaries-are-watched-from-their-directories.md) | The `.cjo` of the binaries are watched from the directories they are in, by a registration of their own, and an event on one finds the project again | accepted |
