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
| [0008](0008-cancellation.md) | Two cancellations, two answers | accepted; a stale snapshot's `CancelledException` runs the request again; `ContentModified` is answered by no read-only handler by D122 |
| [0009](0009-names-of-state-and-database.md) | `ServerState` holds the `AnalysisDatabase`; only calca says `Database` | accepted |
| [0010](0010-generated-syntax.md) | Syntax kinds and typed views are generated from an ungrammar | accepted; an accessor finds a child by the tokens around it by D41 |
| [0011](0011-ci-and-releases.md) | A pinned nightly toolchain, CI on three platforms, releases from `cog bump` | accepted; no editor's tests in CI by D32; the nightly is downloaded from GitHub and checked against `.cangjie-sha256` by D62 |
| [0012](0012-drive-paths.md) | Paths are `std.fs.Path`, URIs are stdx's `URL`; Windows drives are spelled one way | accepted |
| [0013](0013-stdin-is-read-with-readv.md) | Stdin is read with `readv`, not `read`: cjc treats `read` as `@FastNative` | accepted |
| [0014](0014-diagnostics-pull-first.md) | Diagnostics are pulled; pushed, by the server after a write, only to clients that cannot pull | accepted; `interFileDependencies: true`; `workspace/diagnostic/refresh` is sent by D100; a pull the files changed under is answered from the files as they are then, not `ServerCancelled` with `retriggerRequest`, by D122; a pull answers `unchanged` when the client's `previousResultId` is the report's; closes Q13 (#51) for `textDocument/diagnostic` by D131; `workspaceDiagnostics: false` is a decision, no longer a gap; closes Q14 (#52), by D135 |
| [0015](0015-reference-implementations.md) | rust-analyzer is the model, salsa the model for calca, cjc the specification; LSPServer and lin-qingying/cangjie the competitors | accepted |
| [0016](0016-editor-integrations-are-repositories.md) | Each editor integration is a repository of its own in ide4cj: `cangjie.nvim` for Neovim | accepted; how server and clients change together, and who tests which, by D32 |
| [0017](0017-lru-of-memo-values.md) | calca evicts memo values by LRU; a query result keeps pointers, never nodes | accepted; interned values by D18; eviction within a revision by D36 |
| [0018](0018-gc-of-interned-values.md) | calca collects unused interned values, and the memos keyed by them | accepted; interned values by D75 |
| [0019](0019-syntactic-highlighting.md) | Semantic tokens from the syntax tree first, in a fixed legend of LSP's own types | accepted; a name at its use is told; the legend has `namespace`, and two types and modifiers of its own; `refresh` is sent, by D72; a client that augments its grammar gets no token the grammar names as well; `this` and `super` are variables; a constructor and a constant are told by modifiers of their own by D105 |
| [0020](0020-no-lto.md) | The Linux binary is not linked with LTO: cjc miscompiles the stack maps under it | accepted |
| [0021](0021-weekly-releases.md) | A release every week from a green master; the first one by hand, its changelog written; versions of cjls's own | accepted; a nightly by D32 |
| [0022](0022-json-codec.md) | The wire is read and written with fjson, through serde's derives `ToJson`/`FromJson` and one `@Serde` marker | accepted |
| [0023](0023-performance-is-measured-over-stdio.md) | Speed and memory are measured over stdio, by one driver for every server | accepted; no threshold by D81 |
| [0024](0024-fjson-conformance.md) | fjson is held to JSONTestSuite, vendored, and fuzzed in `cjpm test`; a lone surrogate reads as U+FFFD; 512 containers deep | accepted; `readFloat64` rounded correctly by D25; the suite fetched by D26 |
| [0025](0025-toml-through-serde.md) | TOML is read and written by ftoml, TOML 1.1 of our own, through `ToToml`/`FromToml` derived from the same `@Serde` model | accepted |
| [0026](0026-test-suites-are-fetched.md) | Third-party test suites are fetched into `.corpora/` at a pinned commit, not vendored | accepted; the suites fetched by D137 |
| [0027](0027-incremental-builds.md) | Builds are incremental, clean on a new compiler and for a release; tests in `target/test`; CI caches `target` from master | accepted; stamps by D28; what CI caches, and in which job, by D96 |
| [0028](0028-ci-stamps-a-package.md) | CI stamps a package's files with one mtime, made of the whole directory | accepted |
| [0029](0029-one-computation-per-memo.md) | One handle computes a memo, the others wait; a wait that closes a loop is a cycle | superseded by D35 |
| [0030](0030-workspace-loader.md) | The workspace is loaded on the read loop in one revision, under a budget of text, watched by the client; symbols are searched through a per-file index | accepted; what is loaded is the project's files by D33; what is watched, and which event finds the project again, by D58; the load on the read loop, in one revision, by D61 |
| [0031](0031-the-server-sets-its-heap.md) | Without `cjHeapSize` the server starts over with a heap of 2 GB; a load keeps a sixteenth of the heap | accepted; on Windows the child dies with the parent by D78; the budget never leaves an open document out of a loose project by D80 |
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
| [0051](0051-o2-is-a-release-option.md) | `-O2` is in each module's `[target.<triple>.release]`, not its `compile-option`: the coverage builds with `-g`, unoptimized | accepted; the multiplatform module uses `-O1` and the workspace root names no optimization level by D102 |
| [0052](0052-a-name-after-a-dot-is-resolved-by-names-up-to-a-value.md) | A name after a `.` is resolved by names up to a value, members looked up from a type; a value's member is inference's | accepted |
| [0053](0053-the-extends-a-file-sees-are-looked-for-in-its-interfaces-packages.md) | The `extend`s a file may see are looked for in the packages of its interfaces; which of them it sees is decided at the lookup | accepted |
| [0054](0054-a-type-is-an-interned-ty-a-signature-lowered-to-it.md) | A type is an interned `Ty`; a declaration's signature is lowered to it in one query, of a source or a `.cjo` alike | accepted |
| [0055](0055-a-body-is-inferred-locally-in-one-query.md) | A body's types are inferred locally, as cjc checks them, in one query of the body; a type not written is the body's | accepted |
| [0056](0056-the-adr-index-is-written-after-the-merge.md) | The ADR index is written after the merge by a bot; a number is taken when the ADR is started, and checked to be the only one | accepted |
| [0057](0057-type-arguments-are-inferred-per-call.md) | Type arguments not written are inferred per call, as cjc's local synthesis | accepted |
| [0058](0058-folders-come-or-gone-are-watched.md) | Everything come or gone under a root is watched, as VS Code reports a folder as one event; the server tells a directory of the workspace from the rest | accepted |
| [0059](0059-macro-arguments-are-parsed-before-expansion.md) | An expression macro's arguments are parsed as an argument list when they parse as one, before any expansion | accepted; `MacroAttr` is no longer tokens alone by D115; a macro call's arguments lowered alone are read while no expansion of it is current by D117 |
| [0060](0060-the-formatter-keeps-line-breaks.md) | The formatter is our own, on the syntax tree, and changes only the whitespace around the author's line breaks | accepted; the line breaks are the author's by D76 |
| [0061](0061-the-workspace-is-loaded-on-a-spawn.md) | The workspace is loaded on a spawn and set in batches between the messages, through a lock the read loop's handlers take too, reporting $/progress; a request meanwhile answers from what is loaded | accepted |
| [0062](0062-toolchain-from-the-github-mirror.md) | The toolchain is downloaded from the GitHub mirror, checked against sha256 pinned from gitcode | accepted |
| [0063](0063-an-overload-is-taken-by-trying-its-candidates.md) | An overload is taken by trying its candidates, as cjc | accepted; a class or struct call goes to the initializer selected by inference, rather than directly to the type, by D145 |
| [0064](0064-an-operator-is-a-call-of-its-types-member.md) | An operator of a type is a call of its member, the language's own tried first, as cjc | accepted; an operator with one declared candidate keeps its return type; a failing built-in operator is an error by D134 |
| [0065](0065-binary-sources-at-the-cjo-positions.md) | A declaration of a package compiled already goes to the sources of its binary, at the position its `.cjo` gives, its name checked there | accepted; source attachments also provide a context for navigation within their files by D147 |
| [0066](0066-sugar-is-typed-as-cjc-desugars-it.md) | Coalescing, pipelines and compositions are typed as what cjc desugars them to, std.core named through lang items | accepted |
| [0067](0067-loose-mains-are-programs.md) | Loose files without a package line, two or more of which declare main, are a program per main, each with the main-less files of its directory | accepted |
| [0068](0068-binaries-are-watched-from-their-directories.md) | The `.cjo` of the binaries are watched from the directories they are in, by a registration of their own, and an event on one finds the project again | accepted |
| [0069](0069-std-sources-fetched-by-cjls.md) | The sources of std are fetched by `cjls fetch-src`, from `cangjie_runtime` at the commit the nightly's release notes name, into the SDK's `src` | accepted; a release SDK's sources are `cangjie_runtime` at the tag `v<version>`; any SDK's come from the GitHub mirror first, then gitcode, by D94 |
| [0070](0070-an-optional-chain-is-lowered-into-matches.md) | An optional chain is lowered into the matches cjc desugars it to, Some and None lang items | accepted |
| [0071](0071-a-union-reads-its-value-on-the-rewound-reader.md) | A union reads its value on the reader itself, rewound to the value's start between attempts | accepted |
| [0072](0072-names-are-highlighted-by-what-they-mean.md) | Semantic tokens tell a name at its use by what it means, through a Definition shared with go to definition | accepted; semantic tokens read what inference and lowering resolved; `lookUp` is a query by D84 |
| [0073](0073-params-are-read-in-place-when-the-method-came-first.md) | Params are read in place, on the read loop, by the route's reader when `method` came before them; a reader that fails leaves them bytes | accepted |
| [0074](0074-range-formatting.md) | A range is formatted by the whole file's edits on the lines it covers | accepted |
| [0075](0075-a-write-that-changes-nothing-opens-no-revision.md) | A write that changes no input opens no revision | accepted |
| [0076](0076-a-bodys-brace-joins-the-line-before.md) | A body's `{` on a line of its own joins the line before | accepted |
| [0077](0077-an-unknown-type-is-an-error-or-a-gap.md) | A type not known is an error the user made or one the analysis cannot find, and why; a type or package before a dot is no value | accepted |
| [0078](0078-the-windows-child-dies-with-its-parent.md) | On Windows the server puts itself in a kill-on-close job before it starts its child | accepted |
| [0079](0079-settings-are-r1s.md) | The settings are one typed model whose schema the server prints, read as R1 reads them | accepted |
| [0080](0080-an-open-document-is-in-the-project.md) | A document open is in the project: loose files take the open documents and their directories first, those documents past the budget, and one opened among the files left out finds the project again | accepted |
| [0081](0081-the-perf-threshold-is-on-queries-executed.md) | The perf threshold is on queries executed, not on time | accepted; the count is also per function by D89 |
| [0082](0082-a-macros-name-is-looked-up-in-what-the-files-write.md) | A macro's name is looked up in what the files write, never in what macros add | accepted |
| [0083](0083-members-named-through-a-type-are-filtered-by-its-type.md) | A member named through a type or alone is filtered by the type the names give, in the lookup | accepted |
| [0084](0084-what-was-resolved-is-kept.md) | What a name means is kept where it was resolved, not resolved again by what reads it | accepted; a memo verified in this revision answers a dependent through its entry, not its table, by D85 |
| [0085](0085-a-dependency-keeps-its-edge.md) | A dependency keeps the object it was read from, which answers for it without a lock when it can | accepted |
| [0086](0086-json-is-read-without-a-tape.md) | JSON is read by the pull reader, not through a tape index | accepted |
| [0087](0087-workspace-macros-run-in-the-sdks-macro-server.md) | The workspace's macros run in the SDK's LSPMacroServer | accepted; Windows is not left opaque by D91; the token table is one per SDK of the window, not the pin's alone, by D94; no table is generated, and no SDK version is required, by D95; how the macro packages are built, and the guard's deadline, by D104 |
| [0088](0088-a-document-in-no-package-finds-its-own-project.md) | A document open in no package finds its own project from its path, as R1 does on open, and that project stays loaded with the roots' | accepted |
| [0089](0089-calca-counts-executions-per-function.md) | calca counts the executions of each tracked function, and keeps no trace | accepted |
| [0090](0090-what-inference-finds-wrong-is-reported.md) | What inference finds wrong is reported by expression, only between types known wholly, held to zero on this repository and to a shrinking list on std's sources | accepted; the gate also holds what no diagnostic shows by D108 |
| [0091](0091-the-windows-macro-server-is-started-by-createprocessw.md) | On Windows the macro server is started by CreateProcessW, inheriting its two pipe handles alone | accepted |
| [0092](0092-a-new-file-is-given-its-package-line.md) | A document opened blank is given its package line | accepted |
| [0093](0093-when-is-evaluated-on-an-active-item-tree.md) | @When is evaluated on an active item tree and in lowering, against the package's cfg | accepted |
| [0094](0094-a-release-supports-a-window-of-sdks.md) | One cjls release supports a window of SDKs: the latest LTS, the latest STS and the pinned nightly, told apart by `cjc --version` | accepted; macros are on for any SDK since 1.0, by a table of cjls's own where the SDK ships no `Tokens.inc`, by D104 |
| [0095](0095-cjc-token-kinds-are-numbered-by-the-sdks-tokens-inc.md) | cjc's token kinds are numbered by the SDK's own Tokens.inc | accepted; the numbers come from that table when the SDK has no `Tokens.inc` by D104 |
| [0096](0096-build-and-tests-are-jobs-of-their-own.md) | CI builds the binary and runs the tests in two jobs side by side, each with the cache of its own target directory | accepted |
| [0097](0097-unused-warnings-are-off.md) | The unused warnings are off in every module | accepted |
| [0098](0098-workspace-expansions-are-an-input-of-their-file.md) | The macro server's answers are an input of the source file, their origins relative to the top-level item | accepted; a call of std's macro nested in a workspace call's input stays as written; children deeper than one level not checked by D114; a call in an expression is a call of the file, keyed and asked as one on an item, by D117; a `MacroCallId` is an item and an index among the calls on it; ADR-0114: a call on a primary constructor parameter is sent as written by D119; a call of std's macro is a call the server runs, nested or read like a workspace macro's, by D123; a replaced item's source is a view of its expansion, mapped by the spans, never read for itself, by D132 |
| [0099](0099-source-sets-are-a-chain-and-common-is-its-specific.md) | A multiplatform module's packages are the files of the target's chain of source sets, and a common declaration is its specific one | accepted |
| [0100](0100-diagnostics-are-pulled-again-after-another-file-changes.md) | Diagnostics depend on other files: pulled again after any change | accepted |
| [0101](0101-platform-code-is-a-multiplatform-module.md) | What differs between platforms is one multiplatform module, `platform`, of `common` and `specific` declarations | accepted; `cjls.macro_host`'s `@When` constants go to `platform`; what may keep a `@When` is named by D113 |
| [0102](0102-the-multiplatform-module-is-built-without-o2.md) | The multiplatform module is built `-O1`, not `-O2`, and the workspace root names no `-O` | accepted |
| [0103](0103-an-expansion-is-shown-as-a-request-and-as-a-read-only-file.md) | An expansion is shown as cjls/expandMacro and as a read-only .cache/cjls/expanded/<file>.macrocall the server navigates | accepted |
| [0104](0104-workspace-macros-are-built-by-cjc-and-run-under-a-deadline.md) | The workspace's macro packages are built by cjc into the server's cache directory, and run under a deadline | accepted |
| [0105](0105-semantic-tokens-augment-the-grammar.md) | Semantic tokens augment the editor's grammar, in token types they share | accepted; string interpolation delimiters are sent even when semantic tokens augment a grammar by D148 |
| [0106](0106-the-servers-directory-is-the-projects-cache-cjls.md) | The server's own directory is <project>/.cache/cjls, owned by one type, with a layout and a lifecycle | accepted |
| [0107](0107-settings-follow-the-pin.md) | A client's settings are made again when its pin moves, never checked against the cjls under test | accepted |
| [0108](0108-error-roots-only-shrink.md) | This repository's roots of an error type are held to a checked-in count per file and kind that only shrinks | accepted; the file only shrinks by D121 |
| [0109](0109-builtins-are-told-in-a-table-of-our-own.md) | What the language builds in is told in our words, a table of our own | accepted |
| [0110](0110-a-speculative-tree-reparses-the-block-around-the-cursor.md) | A speculative tree is built by reparsing the block around the cursor | accepted |
| [0111](0111-completion-lists-from-the-speculative-tree-and-resolves-lazily.md) | Completion lists from the speculative tree, ranks by scope, and leaves the detail to a resolve | accepted |
| [0112](0112-arguments-are-matched-before-a-candidate-is-tried.md) | A call's arguments are matched to each candidate's parameters before it is tried, as cjc | accepted |
| [0113](0113-the-architecture-is-the-only-when.md) | `hostArch` is the one `@When` of this repository's code, and a set's files are named for what they hold | accepted |
| [0114](0114-std-derive-is-expanded-in-a-workspace-macros-input.md) | A std @Derive in a workspace macro's input is the declaration and cjls's own extends after it, and every call nested in the input is a child | accepted; the `extend`s an outer macro copies have bodies of a comment, not empty ones, by D118; a std `@Derive` in a workspace call's input is the server's output, cjls's own only once its run failed, by D123 |
| [0115](0115-unittest-attributes-are-parsed-and-lowered-into-the-declarations-body.md) | A macro attribute is parsed by its shape and std.unittest's are lowered into the body of the declaration they are on | accepted |
| [0116](0116-quote-interpolations-are-code-of-the-macro.md) | A quote's interpolations are code of the macro, the rest of it tokens | accepted |
| [0117](0117-expression-macros-are-asked-with-the-items-calls.md) | A macro called in an expression, std.unittest's included, is asked with its file's other calls, keyed by its item, its macro's name and its ordinal, and read where it stands while its answer is current | proposed; a body's current expression and statement expansions are lowered and inferred (#369) by D144; nested calls are found even when their enclosing input is not an expression (#371, #443), by D153 |
| [0118](0118-a-body-cjls-writes-itself-is-a-comment.md) | A body cjls writes in an expansion of its own is a comment naming the macro | accepted |
| [0119](0119-a-macro-call-on-a-parameter-is-a-call-of-its-items-chain.md) | A macro call on a parameter is a macro call of the item whose parameter list holds it, indexed after the item's own | accepted |
| [0120](0120-the-gate-is-tagged-out-of-the-coverage-run.md) | The diagnostics gate is tagged `gate` and left out of the coverage run | accepted |
| [0121](0121-the-error-roots-file-grows-with-a-known-gap-met-idiomatically.md) | A known gap met by new code grows the error roots file; the code stays idiomatic and the commit names the gap | accepted |
| [0122](0122-a-request-the-files-changed-under-runs-again.md) | A read-only request the files changed under runs again on a fresh snapshot, not answered ContentModified | accepted |
| [0123](0123-std-macros-run-in-the-macro-server.md) | std's macros run in the macro server from the SDK's libraries, under the calls cjls expands itself | accepted; the type errors in the bodies of an output read are reported, where their spans put them, by D132 |
| [0124](0124-references-are-searched-per-request-where-the-declaration-is-visible.md) | References are searched per request in the files a declaration is visible from whose text names it, no index of uses kept | accepted; reference candidates are filtered by a per-file word index instead of a substring scan by D130 |
| [0125](0125-cjc-runs-behind-a-shim-in-ci.md) | cjc runs behind a shim that closes the descriptors it inherited | accepted |
| [0126](0126-the-code-style-follows-std-checked-by-cjlint.md) | The code style follows std where the compiler leaves a choice, and cjlint checks the official guide's rules that hold here | accepted |
| [0127](0127-completion-reads-the-position-by-the-markers-parent.md) | Completion outside a body reads the position by the marker's parent: a type's path, an import, a line no declaration took, a member's name | accepted |
| [0128](0128-a-members-hierarchy-is-matched-by-name-and-parameters.md) | A member's overrides are matched by name and parameters, found down through each package's subtype edges | accepted |
| [0129](0129-test-files-see-std-unittest-macros.md) | A `*_test.cj` file imports std.unittest and its macros with no line, as `cjc --test` does | accepted |
| [0130](0130-references-filter-files-by-an-index-of-their-words.md) | References read only the files whose words, a tracked bloom filter per file, name the name | accepted |
| [0131](0131-a-diagnostic-reports-result-id-is-its-hash.md) | A diagnostic report's resultId is a hash of its items and of the openings so far | accepted |
| [0132](0132-a-replaced-item-is-read-through-its-expansion.md) | An item a macro's output replaces is read through that output alone; its source maps to it by spans | proposed; a body source map can contain nodes from several expansion files by D144 |
| [0133](0133-client-versions-follow-the-server.md) | A client's version is the major and minor of the cjls release it pins, with a patch of its own | accepted |
| [0134](0134-an-operator-none-fits-is-reported.md) | An operator none of whose candidates fits is reported at the operator; of one declared candidate it is of its return type, as a call of one, and between the language's types an error | accepted |
| [0135](0135-workspace-diagnostics-are-not-offered.md) | `workspace/diagnostic` is not offered: a file not open has no diagnostics | accepted |
| [0136](0136-semantic-tokens-are-sent-whole.md) | Semantic tokens are sent whole: no full/delta | accepted |
| [0137](0137-optics-is-the-gate-of-workspace-macros.md) | A workspace of others' on its own macros, Optics, is expanded and analyzed as a gate | accepted |
| [0138](0138-an-index-assigned-by-an-operator-is-desugared-in-the-hir.md) | `a[i] op= v` and `a[i]++` are desugared in the HIR into the value they give a `[]` taking it | accepted |
| [0139](0139-a-file-in-no-package-is-compiled-alone.md) | A document open in no package is compiled alone, as cjc compiles a file: a module of its own with std | accepted |
| [0140](0140-an-enums-constructors-of-one-name-are-overloads.md) | An enum's constructors of one name are overloads, narrowed by arity and type arguments before a call tries them | accepted |
| [0141](0141-a-tests-state-runs-no-macros.md) | A state runs no macros unless it is given what starts them | accepted |
| [0142](0142-linux-glibc-baseline.md) | Build Linux releases on Ubuntu 22.04 and check them without the SDK | proposed |
| [0143](0143-bounded-generic-bounds.md) | Expand implied generic bounds in a separate bounded query | accepted |
| [0144](0144-body-expression-expansions.md) | A body lowers current expression expansions in place, with file-qualified source maps | accepted |
| [0145](0145-constructor-calls-navigate-to-the-selected-initializer.md) | Constructor calls navigate to the selected initializer, and declarations to their type | accepted |
| [0146](0146-prefer-compile-time-constants.md) | Prefer const for values known at compile time | accepted |
| [0147](0147-sdk-source-context.md) | Binary sources resolve in a detached context with canonical binary declarations | proposed |
| [0148](0148-interpolation-delimiters.md) | Highlight interpolation delimiters over editor grammars | accepted |
| [0149](0149-group-completion-overloads.md) | Completion groups overloads by the name it inserts and resolves their signatures together | accepted |
| [0150](0150-width-driven-formatting.md) | The formatter decides line breaks from syntax and a fixed width | accepted |
| [0152](0152-formatter-settings.md) | Project formatter policy has three explicit settings | accepted |
| [0153](0153-nested-source-macro-inputs.md) | Source macro inputs compose nested calls inside out, including token DSLs | proposed |
