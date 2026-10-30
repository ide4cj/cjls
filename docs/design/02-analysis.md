# Analysis design

The [architecture overview](../architecture.md#analysis-and-incremental-state)
explains the input/query/API split and links to the source. The rules here
constrain changes to that design; they are not a list of analysis features.

## Rules

Constraint kinds and how to revise them are defined in the
[documentation index](../README.md#kinds-of-constraints).

| # | Topic | Kind |
|---|---|---|
| A1 | [Concrete database handle](#a1-concrete-database-handle) | Design choice |
| A2 | [Entity query keys](#a2-entity-query-keys) | Design choice |
| A3 | [Position dependent API](#a3-position-dependent-api) | Design choice |
| A4 | [Write inputs on the root](#a4-write-inputs-on-the-root) | Boundary |
| A5 | [Deleted files retain identity](#a5-deleted-files-retain-identity) | Design choice |
| A6 | [UTF-8 byte offsets](#a6-utf-8-byte-offsets) | Boundary |
| A7 | [Line endings](#a7-line-endings) | Language constraint |
| A8 | [Analysis knows no LSP](#a8-analysis-knows-no-lsp) | Boundary |
| A9 | [Interners and collected identities](#a9-interners-and-collected-identities) | Design choice |
| A10 | [Equatable query results](#a10-equatable-query-results) | Design choice |
| A11 | [Diagnostics belong to results](#a11-diagnostics-belong-to-results) | Boundary |
| A12 | [Preserve diagnostic ranges](#a12-preserve-diagnostic-ranges) | Boundary |
| A13 | [Do not retain syntax trees](#a13-do-not-retain-syntax-trees) | Boundary |
| A14 | [Meaningful cycle fallbacks](#a14-meaningful-cycle-fallbacks) | Design choice |
| A15 | [Bound syntax retention during sweeps](#a15-bound-syntax-retention-during-sweeps) | Boundary |
| A16 | [Bound disk loading](#a16-bound-disk-loading) | Design choice |
| A17 | [Input durability](#a17-input-durability) | Design choice |
| A18 | [Package membership and visibility](#a18-package-membership-and-visibility) | Language constraint / Design choice |
| A19 | [Stable item identity](#a19-stable-item-identity) | Design choice |
| A20 | [Canonical name text](#a20-canonical-name-text) | Language constraint |
| A21 | [Do not swallow query unwinds](#a21-do-not-swallow-query-unwinds) | Boundary |
| A22 | [Resolution layers](#a22-resolution-layers) | Boundary |
| A23 | [Declaration identity](#a23-declaration-identity) | Design choice |
| A24 | [Signature type dependencies](#a24-signature-type-dependencies) | Design choice |
| A25 | [Local body inference](#a25-local-body-inference) | Design choice |
| A26 | [Call local type variables](#a26-call-local-type-variables) | Boundary |
| A27 | [Isolate overload candidates](#a27-isolate-overload-candidates) | Boundary |
| A28 | [Language items](#a28-language-items) | Language constraint / Design choice |
| A29 | [Source maps for desugaring](#a29-source-maps-for-desugaring) | Design choice |
| A30 | [Errors and analysis gaps](#a30-errors-and-analysis-gaps) | Design choice |
| A31 | [Written and expanded scopes](#a31-written-and-expanded-scopes) | Design choice |
| A32 | [Conservative diagnostics and gates](#a32-conservative-diagnostics-and-gates) | Design choice |
| A33 | [Conditional compilation](#a33-conditional-compilation) | Language constraint |
| A34 | [Common and specific declarations](#a34-common-and-specific-declarations) | Language constraint |
| A35 | [Reading macro expansions](#a35-reading-macro-expansions) | Design choice |
| A36 | [Package navigation](#a36-package-navigation) | Design choice |
| A37 | [Constructor navigation](#a37-constructor-navigation) | Design choice |
| A38 | [Interpolation highlighting](#a38-interpolation-highlighting) | Design choice |

### A1: Concrete database handle

Every query takes `AnalysisDatabase` itself; no database interface (D4).

### A2: Entity query keys

A query is keyed by an entity (`SourceFile`, interned ids), never by a position (D6): memo
values are evicted (`lru`, D17), and interned values unused for a while are collected with the
memos keyed by them (D18), but other keys live as long as the database.

### A3: Position dependent API

Position-dependent API (`hover(db, position)`) is a plain function over queries.

### A4: Write inputs on the root

Inputs are created and set on the root handle only, outside queries (`IllegalStateException`
otherwise).

### A5: Deleted files retain identity

A deleted file is an empty text; its `FileId` and `SourceFile` stay.

### A6: UTF-8 byte offsets

Offsets are UTF-8 bytes on character boundaries, as `TextRange` and `Rope`.

### A7: Line endings

Lines break at `\n` only, as the compiler's lexer; a line ends before the `\r` of `\r\n` (D1).

### A8: Analysis knows no LSP

`loupe` knows no LSP: no URIs, `Position`, encodings or LSP types (D5).

### A9: Interners and collected identities

Anything that interns (dense ids in first-seen order) is an `IndexSet`, or a
`ConcurrentIndexSet` if shared between threads (`PathInterner`, C9; its `FileId`s are forever,
A5), unless its values are collected: then a `Slab` of generations (calca's interned values and
memo keys, D18).

### A10: Equatable query results

A value a query returns is `Equatable`, so it backdates; `[noEq]` only with a reason.

### A11: Diagnostics belong to results

Diagnostics are part of the results of the queries that find them (`Parse.errors`), never
accumulated on the side (D14).

### A12: Preserve diagnostic ranges

A diagnostic's range is what its source gives, an empty one included ("expected `}`" at the end
of a file); widening it for a client is translation.

### A13: Do not retain syntax trees

A tracked result holds no `SyntaxNode`, `SyntaxToken`, typed view, `GreenNode` or `Parse`
(`parse` itself excepted), only `SyntaxNodePtr`/`AstPtr`: a node keeps its whole tree alive, and
`lru` on `parse` frees nothing (D17).

A handler holds nodes for the length of a request.

### A14: Meaningful cycle fallbacks

A query has a fallback on a cycle (`@CalcaTracked[cycleResult: f]`) only where the language
gives a cycle a meaning of its own (glob imports reaching each other, a recursive type alias),
and the fallback is what the compiler reports there (an unresolved name, an error type);
anywhere else a cycle is a bug, and `CycleException` says so.

### A15: Bound syntax retention during sweeps

A question over every file holds no tree past the `lru` of `parse`, which evicts within a
revision too (D36): what it keeps of a file is a summary with no node (`fileSymbols`,
`itemTree`).

One that needs no tree kept parses without `parse` (`fileSymbols`, D30), so a sweep does not
push the open documents' trees out.

### A16: Bound disk loading

What the server reads from disk is bounded: a load keeps at most its budget of text and `.cjo`
(D30, D38), a sixteenth of the heap (D31).

### A17: Input durability

A file's input has its module's durability: `Low` for the user's, `Medium` for a dependency's,
`High` for `std`; a file of no module `Low`; a `.cjo` its binary's, `High` for `std`, `Medium`
for any other.

The project is set before the files it names, so they are created with it (D33).

### A18: Package membership and visibility

Which files a package has is `Package.files`, never found from the texts: a file deleted is an
empty text (A5).

Binary attachments may have detached source contexts linked to their binary package
(D147). They are outside project modules and import candidates, so neither project
resolution nor workspace symbols gains a second copy of SDK declarations. Their
imports use the binary's lookup scope; bodies and file imports use source text.
Names absent from the binary may come from source files with checked declaration
pairs, only inside the detached context; binary names and overload sets win.
Members absent from a binary type may come from its paired source type only for
another source in the same attached package.

Independent dependency selections carry distinct module/package identities and
source import scopes, including when they share a physical path (D155). Scoped
packages use contextual source inputs: the same physical file has separate
analysis identities, and `AnalysisDatabase.setFileText` updates every context. Package-driven
queries retain that context; the physical editor lookup prefers ordinary membership,
otherwise the first active scoped membership. Queries never create contextual inputs.

Visibility (`protected`, `internal`) is computed from package names, not from `Module`: a module
is a unit of the build, cjc's is the first segment of a name (D33).

### A19: Stable item identity

What outlives an edit names an item by its `ItemId`, never by a pointer: a result holding a
`SyntaxNodePtr` changes with every edit above it, and so does everything that read it.

Items come from `itemTree`, nodes back through `itemIdMap` (D34).

### A20: Canonical name text

A name is its `Name.text()` or `NameRef.text()`, never the text of its node or token: `` `foo`
`` is `foo`, a quote's `$foo` is `foo` (D116), and a name compared, hashed into an `ItemId` or
shown keeps no backquotes.

### A21: Do not swallow query unwinds

A query body never catches `Exception` around a calca call, only what it means to tolerate:
calca unwinds with `Exception`s, and a body catching one stores nothing and throws it again
(D42).

A handler interns nothing the user types: interned outside a query, a value is `High`, kept
forever (D18).

### A22: Resolution layers

Resolution is layered (D44): `itemTree` (a file) → `defMap` (a package) → signatures (an
`ItemId`) → bodies and their scopes → inference (a body); a layer reads only those under it.

A name in a scope is a set of definitions; a member, an overload or an `extend`'s member is
found by inference, never by a `defMap`.

Import lookup retains the importing file's test context (#518): a module's
`testDeps` extend only its `*_test.cj` imports, including expansion output at a test
call site. Production package exports omit test-file re-exports. Each dependency
resolves against its own edges; a downstream importer never inherits test edges.

### A23: Declaration identity

A declaration across files is its `DefId` (its `ItemFile` and `ItemId`, interned), never a pair
held apart; a query about one declaration is keyed by it (D45).

An attached source body retains its source identity for locals and ranges, but its
self type and generic owners use the binary declaration paired at its checked
identifier position (D147). Package and member lookup use binary declarations,
including compiler-provided types. A file with no matching declarations has no
source context; navigation targets retain D65's position/name check.

### A24: Signature type dependencies

Lowering a signature to types (`signatureTypes`) reads another declaration's lowered types only
through an alias, its own expansion: a path's type parameters are counted from `signature` or a
`.cjo`'s declaration, which lower nothing (`genericsOf`).

A class whose supertype names another whose supertype names it (`A <: I<B>`, `B <: I<A>`) is no
cycle.

An alias on a cycle of aliases is found by a search of the aliases each names before any is
expanded, and expands none of its cycle: `signatureTypes` itself never cycles, its fallback
(A14) only for a cycle the search would miss (D54).

### A25: Local body inference

Inference (`inferBody`) reads another declaration's body only for a type its signature does not
write (`declaredTyOf`), never its own: a function calling itself of no return type is an error
there, not a cycle; only declarations of unwritten types reading each other are one, each an
error by its fallback (A14, D55).

### A26: Call local type variables

A type variable (`InferTy`) lives while its generic call is inferred. When that call is
itself a callee, its returned function's applications share the same variables and solve
with both the inner and outer arguments (N131, #246). A standalone call still solves alone,
including fallback to its declared bounds. If the arguments' join fails or exceeds an upper
bound, the solver tries the upper bound below all the others, provided every argument fits it
and any numeric literals can use that numeric kind or have their default types boxed into it
(#242). An expected `?I` may select `Option<I>` for this fallback, with arguments boxed as in cjc.

Arguments are checked only against types without variables, an unsolved one an error type.
Every application and callee is recorded with its solved type; no variable reaches an
`InferenceResult` or another query's result (D57).

### A27: Isolate overload candidates

A candidate of a call is tried, never taken on trust: inference writes through a journal while
one is, and undoes it after, whether it fits or not; the one taken is inferred again.

Nothing a candidate wrote is ever in an `InferenceResult` (D63).

### A28: Language items

A declaration of std.core the syntax means (`Option` of `?T`, `composition` of `~>`, `String` of
a literal, `Iterable` of `for-in`) is `langItem`'s, whatever a file's scope names and whatever
its visibility; nothing else looks one up by name.

A type of the compiler's own (`CPointer`, `CString`, `RawArray`, `VArray`, `CFunc`) is no lang
item: a file names it through its scope (D66, D154). Source `std.core` receives synthetic scoped
`BuiltIn` declarations; `RawArray` is internal and the others public. Binary `BuiltInDecl`s
retain scoped identity and navigation metadata. Semantic types and extension heads are independent
of those declarations, so source and binary signatures agree without an SDK `std.core.cjo`.

A source file of no package finds them, as the `extend`s of a type of the language, in the SDK's
binary `std.core` (`sdkCore`, #319).

`VArray` constructors use their semantic type, including a type alias's expansion, and the
ordinary call argument checks. As cjc's `ChkVArrayArg`, a named argument selects `repeat: T`;
an argument in order selects an initializer of type `(Int64) -> T`. A trailing lambda is an
argument of that same call, so it receives the same expected type (#494).

### A29: Source maps for desugaring

A desugaring in the HIR (an optional chain into `QuestMatchExpr`s) adds its expressions after
those it is made of, of the same node or of none, and names std.core only by `LangExpr` (A28):
`BodySourceMap.exprAt` gives a node's expression as written, the link `$v.b` of `a?.b`, and the
expressions after it of that node are what it is desugared into, the last its value (D70).

A custom annotation's constructor uses a synthetic callee during inference. Its placement
diagnostic targets the declaration, so that source stays separately in `BodySourceMap`, with
its expansion provenance. The synthetic callee is never indexed as a written expression:
otherwise declaration names would acquire artificial expression types and unknown roots.
Source-map equality includes these targets so source-only edits refresh diagnostic ranges.

### A30: Errors and analysis gaps

A type not known has three causes (D77, D143): `ErrorTy` only where cjc reports an error, as
far as the analysis follows cjc; `TodoTy(why)` for an unsupported analysis feature (macro
expansion); `UnknownTy(why)` for missing or unreadable inputs (`NoStd`,
`BinaryType`), a type not inferred yet (`NotInferred`), or an exhausted analysis resource budget
(`GenericBoundsLimit`). A malformed binary or an unresolved binary dependency alone does not
establish an error in the user's source.

What is made of a type not known is that one, a `TodoTy` or `UnknownTy` before an `ErrorTy`
(`unknownOf`), never a new error: a failure of known types alone is an `ErrorTy`, unless a macro whose
expansion is not read is called on the type or in the package looked in (a `TodoTy`).

Such a type, or one of its supertypes so called on, may be a subtype of any class or interface
(`hasMacroSupertypes`): a bound it does not seem to meet is met, and a join with it is a
`TodoTy` (#175).

Implied generic bounds are expanded separately from signature lowering (A24). The expansion
budget bounds analysis work; exceeding it yields `UnknownTy(GenericBoundsLimit)` for the affected
parameters, never a partial set treated as complete or a user diagnostic (D143).

A type or package before a `.` is no value: no type at all (`None` in `InferenceResult.exprs`),
never an unknown one.

A28's lang items include std.ast's `Tokens` of `quote`.

### A31: Written and expanded scopes

A package's scope has two stages (`ScopeStage`): what its files write, and that with what the
macro calls in them add (`defMapAt`, `exportsAt`, `fileImportsAt`).

A macro's name is looked up at the first, and nothing on the way from an item to its expansions
(`expandedCalls`) reads the second: what is expanded depends on it, so the second is a function
of the first, never a cycle of queries (D82).

### A32: Conservative diagnostics and gates

Inference reports a diagnostic (`InferenceResult.diagnostics`, by HIR identity) only between
types known wholly (no `ErrorTy`, `TodoTy`, `UnknownTy` or variable inside, A30), at an
expression or declaration the user wrote (A29), and where it matches the arguments as cjc
does. A check it cannot make yet is counted, so a candidate still fails, and not reported.
Custom annotation placement is checked only after its constructor and argument types are
known; its synthetic callee identifies the check, while the separate declaration source
supplies the diagnostic range. It does not make a synthetic expression user-written.

A false error on code cjc accepts fails `DiagnosticsGateTest`: none on this repository, on std's
sources none beyond `std_diagnostics_known.txt`, whose lines each name their gap and only go
(D90).

What no diagnostic shows, this repository's roots of an `ErrorTy`, `ErrorRootsGateTest` holds
per file and kind to `error_roots_known.txt`, on Linux, which only shrinks (D108).

On Optics, a workspace of others' on its own macros, built and expanded as the server does,
`OpticsGateTest` holds the diagnostics and the calls never sent to
`optics_diagnostics_known.txt` alike (D137).

A test over a corpus like these carries `@Tag[gate]`: the coverage run leaves it out, and what
it alone reaches is a fixture (D120).

### A33: Conditional compilation

What reads a file's declarations as a build has them reads `itemTreeOf` (`activeItemTree` of a
source file), never `itemTree`, which keeps what a false `@When` leaves out; and lowers a body
or a signature through an `ActiveFilter`. `itemTree` is for what needs every item whatever the
cfg (D93).

Checks performed while parsing retain that order even when collected by a later diagnostic
query: native annotation rejection on `main` precedes inactive-code filtering, while semantic
target checks follow it. A resolved declaration macro still owns its opaque input; checks
apply to its current successful replacement rather than diagnosing that raw input (A35).

### A34: Common and specific declarations

A `common` declaration a `specific` one of its name and kind completes is that one: a scope
never has it (`DefMap.commons` keeps it aside), its type is the specific's (`selfTyOf`), and the
members of the specific type are the specific's own plus those only the common declares
(`commonMembersNamed`).

Only what shows a declaration to the user reads the common again (`commonsOf`).

A file of a source set the target does not take is in no package, and nothing in it is checked
(D99).

### A35: Reading macro expansions

An expansion is read as a file (`hoverInExpansion`, `definitionInExpansion`, offsets in
`expandedMacro`'s text), its names in the scope of its call's file; bodies in mapped macro-server outputs are lowered and inferred (D132), while cjls's own stub bodies remain comments (D118).

Where a request in an expansion goes is in the source if the macro copied the name from there
(`sourceRangeOf`), else in the expansion (`NavigationTarget.expansion`); a request from a source
file never goes into an expansion.

What outlives a revision names a call by its file and `MacroCallKey` (`macroCallKeyOf`,
`macroCallOf`), never a `MacroCallId`, which may be collected (D18).

A call inside the input of another (D98) shows in that one's expansion: `macroCallAt` gives the
call read (`readCallOf`).

Source calls in macro inputs expand inside out, left to right, including calls in token DSLs
that are not expressions (D153). An outer input waits for nested served calls' outputs, then
substitutes the outermost nested outputs and forwards all descendants' messages in expansion
order. Copied spans keep their source; generated spans point to the nested call's head.
Calls generated by an expansion still have no source key and are not recursively expanded.

A declaration a workspace macro copied is what its expansion declares, at its uses and at itself
(`expandedDeclOf`), documented by the comments written before the call; a type's interfaces are
also those its `@Derive` adds.

The expansion of a call in an item is parsed as where the call stands says (`expandToOf`: an
expression, or a block's statements, D117). The body lowers a current successful answer in place
(D144): a statement expansion's declarations belong to the surrounding block. `BodySource`
qualifies each expression, pattern, local and type pointer by its expansion, or by the body's
own file; reverse lookups must use that qualification. Diagnostics map copied tokens to source
and generated tokens to the call head. Missing, stale, failed or unparseable answers and
speculative completion retain the argument-only fallback.

Hover and definition in a current expression expansion use that body's qualified sources.
An expression output its body does not read keeps the call-site fallback (`callSiteNameOf`):
copied tokens at their source positions, plain generated names in the call site's scope unless
the expansion declares them. Requests on source arguments still wait for #370's descent.

### A36: Package navigation

A package has no node: where it is declared is the `package` header of each of its files, at the
path it names (`packageTargets`); a package compiled already, nowhere.

A name of an `import` means what its path names up to it (`importPathTo`): the name a leaf
brings, what the leaf imports; a name before it, a package.

Hover shows a package as `package` and its name, at an `import` and in a macro's path alike.

### A37: Constructor navigation

Go to definition on a class or struct call uses the explicit initializer selected
by inference; without one, it keeps the type target. An enum constructor call uses
the overload inference selected (D140). A request on an initializer declaration
(`init` or a primary constructor's name), or an enum constructor declaration,
goes to the owning type (D145).

Initializer selection uses the overload journal (A27) and is exposed separately
from ordinary callee identity: class/struct hover and reference searches continue
to use the type. The initializer target selects its name or the `init` keyword,
so another go-to-definition request reaches the type.

### A38: Interpolation highlighting

String interpolation boundaries (`${` and its matching `}`) have their own
`InterpolationDelimiter` tag, translated to the standard LSP `operator` type
even when tokens augment an editor grammar (D148, amending D105). The expression
inside keeps its normal code tags and string text keeps its string tags;
highlighted ranges never overlap. Escaped and raw interpolation text is string
content.

## Analysis tests

Analysis fixtures exercise loupe without LSP or a linked fixture library (D43).
Start with a neighboring feature's `*_test.cj` and the
[fixture helpers](../../modules/loupe/src/fixture/), and follow
[Development](../development.md) for focused and required checks.

Tests using std binary packages (HIR and VFS tests included) need the pinned SDK
selected by `CANGJIE_HOME`, as `cjo` tests do. Tests navigating into std source
also need `.corpora/` at the runtime commit matching the nightly:
[`stdWithSources`](../../modules/loupe/src/fixture/sdk.cj) reads that corpus, not
an arbitrary SDK source checkout (D65). Use the corpus fetch procedure in
Development; missing SDK or corpus data is a prerequisite failure, not permission
to silently skip a case.
