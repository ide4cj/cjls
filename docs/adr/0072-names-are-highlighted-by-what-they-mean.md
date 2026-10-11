# ADR-0072: Semantic tokens tell a name at its use by what it means, through a Definition shared with go to definition

Status: accepted, 2026-10-09
Amends ADR-0019: a name at its use is told; the legend has `namespace`, and two types and modifiers of its own; `refresh` is sent

## Context

- D19 highlighted the tree: a name at its declaration, a name in a type taken for one; a name at its use got no token (#201). Name resolution (D47–D55) and overloads (D63, D64) now tell what almost any name means, but `definitionAt` folded the answer into ranges.
- R1 classifies a name once, `NameRefClass::classify` into a `Definition` (`ide_db::defs`), and both `goto_definition` and `syntax_highlighting` read it; `highlight_def` maps it to a tag and modifiers (`mutable`, `static`, `defaultLibrary`), an unresolved name to `unresolvedReference`, its own type. It sends `workspace/semanticTokens/refresh` after every change of the state, when quiet (`main_loop.rs`, `became_quiescent || state_changed`).
- LSP's predefined types have no unresolved name, its modifiers no mutable one; a client with `refreshSupport` asks the tokens of the documents it shows again when told.
- The workspace's macros are not run (#175, #176): a name one of them declares (`calca`'s `CalcaTracked_*`, `@CalcaInput`'s `get`, `@DeriveExt`'s `fromJson`) means nothing to resolution.

## Decision

- **One classification**, R1's: `classifyName(db, file, item, token)` says what a name means as `Definition`s (a declaration, a local, a member parameter of a primary constructor, a type parameter, a package); empty when it means nothing, `None` when resolution does not tell (a member of a value of a type not inferred, a constructor by a path). `definitionAt` maps them to targets, `highlight` to tags.
- **A name at its use** in an expression, after a `.`, in a type, in a pattern (a lone name a constructor or a binding) and of a macro call gets its declaration's tag: what the outline calls it (`Symbol(StructureKind)`), a parameter, a type parameter, a `namespace`; the first of several. Modifiers as at the declaration: `readonly` for `let` and `const`, `mutable` for `var` and a `mut` property, `static`, `deprecated` (a source's `@Deprecated`), `defaultLibrary` for `std`'s. A package of a `package` line or of an import before another segment is a `namespace` by the tree. A file of no package is told by the tree alone, as before.
- **`unresolvedReference`** for a name resolution finds nothing for, but not after a `.` (a macro on the type may add the member) and not in a package where a declaration is under a macro not of a package compiled already (it may declare the name), until #176.
- **The legend** keeps D19's 19 types at their indices and appends `namespace` and `unresolvedReference`; modifiers append `mutable`. A theme without them shows the token as untyped.
- **`refresh`**, as R1: after a write that changed the files, if the client declared `refreshSupport`; a name of a document may mean something else after another file changed.
- **Lookups made queries** that every name hit: `parentOf`, `itemOf`, `declItemOf` were scans of a file's items per call (526 → 143 ms on `nodes.cj`, below).

## Consequences

- On this repository at ed43583, 944 files: 297 031 tokens, no `unresolvedReference` (29 before the macro rules, all names of the workspace's macros).
- `tests/perf`'s `tokens` scenario (on a file of this repository, master then this change, three runs each, load 3–4 of 24 threads): `lexer.cj` (18 KB, the 90th percentile of the sources) first tokens 23 → 142 ms, after a keystroke p50 7 → 27 ms, p95 9 → 45 ms; `infer.cj` (90 KB, the 99th) 46 → 651 ms, 27 → 180 ms, 40 → 330 ms; `nodes.cj` (170 KB, generated) 85 → 870 ms, 58 → 423 ms, 75 → 710 ms, peak RSS 260 → 310 MB. 40–80% more tokens.
- `HighlightBench` (`nodes.cj` in `ginkgo` and `cjsyntax`, std's `core` and `collection`): 143 ms ±0.7% its bodies inferred, 324 ms ±1.5% after its text set again. What remains: a new revision lowers every body of the file again to verify it (D50's source maps point into the tree), and a name in a type's body looks up its members (N69) every time, `memberLookup` unmemoized; a `range` request reads only the bodies it holds.
- A theme maps `unresolvedReference` and `mutable` only if it knows them: the editor clients (D32) may declare them with a fallback.
- Q19 (#56): `refresh` is answered here; `full/delta` still waits for results kept per `resultId`.
