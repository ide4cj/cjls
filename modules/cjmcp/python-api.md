# cjmcp Python API

Select syntax and semantic evidence from the analysis database. The query map
below covers simple lookups; use a [task recipe](skills/cangjie-mcp/SKILL.md) for
traversals and refactors. Consult the [generated reference](#api-documentation)
only for an unresolved contract, before falling back to custom textual heuristics
for a concrete gap. Compose selection, analysis and evidence checks in Python;
return bounded source and explicit omissions.
For connection configuration, see [agent setup](agent-setup.md).

## Query map

Capture `a = workspace.analysis()` once per script. Paths refer to loaded files;
offsets and ranges are zero-based UTF-8 bytes, with exclusive ends. Keep native
objects inside Python and project the fields needed for the answer. Only the
documented diagnostic/status/range/severity values serialize automatically.

| Task | Query and result |
|---|---|
| Check the selected project | `workspace.root`, `workspace.loadDiagnostics`, `workspace.macros`; include these with the first useful query |
| Read snapshot text | `a.text(path)`; `workspace.files()` includes dependencies, so filter to the project when needed |
| Find declarations | `a.symbols(name, limit)` returns matches with `.fileId` and `.symbol`; resolve paths with `a.path(fileId)`. A full limit may omit matches |
| Inspect a file outline | `a.fileSymbols(path)` returns symbols with `.name`, `.range`, `.selectionRange`; `workspace.structure(path)` has nested `.children` |
| Find source usages | `a.references(path, offset)` returns `.fileId`, `.range`, `.isDeclaration` |
| Inspect same-file occurrences | `a.related(path, offset)` retains read/write relationships |
| Navigate source | `workspace.definition(path, offset)`, `workspace.hover(path, offset)`, `workspace.diagnostics(path)` |
| Inspect members | `a.allMembers(defId)` includes inherited and visible extension members; `a.members(defId, name)`, `a.supertypes(defId)` narrow the query |
| Inspect member access | `a.field(defId, exprId)`, `a.receiver(defId, exprId)`, `a.receiverType(defId, exprId)` inspect resolution in the selected declaration |
| Inspect a macro | `a.macroCall(path, offset)` returns a value with `.call` or `None`; `a.expansion(call.call)` returns a value with `.text` or `None` |
| Expand a whole file | `a.expandedFile(path, header)` requires an explicit header string; a single macro uses `expansion` instead |
| Navigate generated code | `a.definitionInExpansion(call.call, offset)`, `a.hoverInExpansion(call.call, offset)`, `a.typeDefinitionInExpansion(call.call, offset)`; offsets belong to the expansion text |
| Inspect HIR and types | `a.declarations(path)` returns DefIds; `a.item(defId)`, `a.body(defId)`, `a.infer(defId)`, `a.typeText(ty)`, `a.typeKind(ty)`. Inference `.exprs` and `.locals` align with the body's arrays; `a.expressionRanges(defId)` uses the same expression indices. Null types mean non-value expressions; null ranges mean unavailable source locations |
| Inspect selected callees | `a.infer(defId).callees` has `.expr`, `.decl`, `.isInitializer`; `.expr.index` identifies the callee expression, which need not be the outer call expression |
| Locate written signature types | `a.signatureWithSourceMap(defId)` returns `.signature` and `.sourceMap.ranges`; index by `TypeRefId.index` |
| Compose semantic queries | `s = a.semantic()`; `s.at(a.fileId(path), offset)`, `s.syntaxAt(a.fileId(path))`, `s.project()` retain lookup context |
| Follow call hierarchy | `a.prepareCallHierarchy(path, offset)` returns entries; `a.incomingCalls(entry)`, `a.outgoingCalls(entry)` return grouped call sites |
| Query completion/type navigation | `a.completions(path, offset)`, `a.completionDetails(path, offset, item)`, `a.typeDefinition(path, offset)`, `a.implementations(path, offset)` |
| Inspect editor structure | `a.highlights(path)`, `a.folding(path)`, `a.selection(path, offset)` return highlighting, folds and enclosing selections |
| Preview formatting | `a.formatting(path)`, `a.rangeFormatting(path, TextRange(start, end))` return edits or `None`; optional `options=FormatOptions(indentWidth=2)` |
| Read builtin docs | `a.builtinTypeDoc(name)`, `a.builtinAnnotationDoc(name)`, `a.builtinMacroDoc(name)` return docs or `None`; names exclude `@` |
| Suggest a package header | `a.newFilePackageLine(path)` returns a string or `None`, without creating the file |

Navigation targets expose `.fileId`, `.fullRange`, `.focusRange` and `.expansion`.
For source targets read `a.text(a.path(target.fileId))`; for expansion targets
read `a.expansion(target.expansion).text` before slicing their ranges. Check for
unavailable text. Return explicit target fields, not the native target object.
See the [macro recipe](skills/cangjie-mcp/references/expansions.md) for a complete
expansion-and-navigation script and the other
[task recipes](skills/cangjie-mcp/SKILL.md) for traversal examples.

## Server identity

Each script receives server_info, a fresh JSON dictionary also returned as
serverInfo by MCP initialize. Its name/version identify the executable product;
_meta contains apiVersion (currently 1), commit (full build-time Git SHA or null),
dirty (whether the build checkout had local changes, or null without Git identity)
and features: structuredDiagnostics, worktreeSessions, checkedSourceChanges,
sourceExcerpts, outputBudget, semanticViews and apiDocs. Feature names describe this binary's supported
Python/tool contracts, not analysis completeness or preparation success.

The build hook embeds identity before compilation and preserves the generated
file's timestamp when unchanged. No Git checkout or BUILD-INFO file is needed at
runtime. The identity belongs to the server, independently of root/session/revision.
apiVersion changes for incompatible Python contract changes; additive features
can be checked individually. Missing server_info identifies an older server
without this discovery contract. Do not use a newer checkout's docs as proof of
its capabilities. For example: result = server_info.

## Selecting a project or worktree

runPython accepts an optional root argument: an absolute directory path. Omission
always selects the startup --dir (or startup working directory), independently of
previous calls. The server validates and canonicalizes it before preparing or
executing Python. Symlink and dot-component aliases of the same root reuse one
session. Invalid/missing roots never fall back to another workspace or run code.
This selection is not a filesystem sandbox: scripts retain process permissions.

Each root owns its database, VFS, macro host, revision and last_output. All calls
remain sequential; scripts use the injected workspace without changing queries.
Responses, including budget and preparation errors, include root and sessionId.
Preparation/root-selection errors have null revision; selection failures also
have null sessionId and report the requested path. Successful selection reports
the canonical root. Compare (sessionId, revision) within this MCP connection;
IDs are connection-local, not globally unique across restarts.

At most four sessions are retained, including the default root when used. Selecting
a fifth closes the least recently used session's polling worker and macro host.
Eviction invalidates retained analysis handles with ContentModified.
Returning to an evicted root creates a new sessionId and resets revisions and
last_output. Shutdown closes all sessions. Observed deleted roots are retired
before selection; recreating their path starts a fresh session. Replacing a root
entirely between checks is not tracked as filesystem identity: the existing
session synchronizes its new inputs. Native proxy retention remains an independent
limitation; eviction does not promise to reclaim all Python-exported values.

Retained native objects and semantic IDs must never cross workspace sessions.
Python imports and process state are shared; these are independent analysis
sessions, not isolated Python interpreters or processes. Modules used to retain
objects across calls must keep their producing session identity too.

Native node/range values are objects, not JSON dictionaries. Use task recipes
for traversal and targeted [reference lookups](#api-documentation) for unresolved
member contracts.

### Project build inputs

SDK selection is captured during preparation of the current revision. Reading
`workspace.sdk` does not run the compiler or repeat discovery; a selection change
opens a new revision. An unrecognized compiler version leaves its version/channel
unavailable without making the SDK itself unavailable.

Native linker inputs are separate from Cangjie imports and source dependencies;
a selected library may not exist yet. Build and run native artifacts with the
user's build system before expanding macros that need them.

### Macro state and structured diagnostics

Loading, macro preparation and per-file diagnostics have separate channels.
Their native values serialize directly in `result` without record projection
or message parsing:

~~~python
a = workspace.analysis()
result = {
    "root": workspace.root,
    "load_diagnostics": workspace.loadDiagnostics,
    "macros": workspace.macros,
    "diagnostics": workspace.diagnostics("src/main.cj"),
}
~~~

Macro completion and diagnostic severity are independent
([D165](../../docs/adr/0165-cjmcp-structured-diagnostics.md)). Pending means
preparation remains; settled means its attempt finished, including projects with
no macro calls. Settled can include errors, and pending alone is not an error.
The status belongs to the script's fixed revision, not a live worker progress
feed. Writes/reload do not change it during a script. Preparation and Python
execution are serialized, so normal scripts see settled after preparation.

In Python compare native enum values, such as `d.severity == Severity.Error()`.
The tool's JSON encoder writes severity as error/warning/hint, macro state as
pending/settled and diagnostic source as workspace/macro/analysis. A range becomes
`{start, end}` with zero-based, end-exclusive UTF-8 byte offsets. Diagnostic
line/column fields are one-based, with columns in UTF-8 bytes. Unavailable codes
and locations remain JSON null; hints are retained in diagnostic messages.

Preparation codes are workspace_load, macro_sdk, macro_build, macro_not_sent and
macro_expansion. SDK/build messages without a structured source location keep
location fields null; the server never guesses coordinates by parsing stderr.
Macro errors and warnings use loupe's mapped source range and retain hint text.
A thrown macro exception falls back to the call range if the SDK has no more
precise location. Per-file loupe diagnostics can also include macro findings;
requesting both channels can therefore expose the same finding.

`TextRange` and `Severity` also serialize directly. Other native analysis objects
need explicit projection. Plain `json.dumps` inside a script does not use the
tool's encoder.

Scope diagnostic queries to relevant files. For diagnostic source excerpts, pass
non-null (path, range) pairs to [source_excerpts](#source-excerpts).
[Script execution](#script-execution) describes response budgets and recovery.

### Applying source changes

`workspace.applyChange` applies the shared `source_change` model to disk. See the
[editing recipe](skills/cangjie-mcp/references/editing.md) for construction and
checked-edit examples.

The whole set is validated before the first write. Existing-file operations
carry expected text, checked against disk and the analysis revision when loaded.
Creates and renames never overwrite destinations; missing parent directories are
created. Paths stay inside the workspace and cannot traverse symbolic links.
Writes do not refresh analysis during a script. Reacquire analysis in the next
call to observe edits and new files. An I/O failure can leave earlier operations,
parent directories and partial effects of the failing operation; no rollback or
exclusion of concurrent external writers is promised. Renames use hard links and
require the same filesystem. The protocol frontend never writes editor buffers.

### HIR and inference

`workspace.analysis()` captures the current loaded disk revision. Keep this object
with the `DefId`, `Ty`, `FileId` and source identities it produces: identities are
scoped to their database and must not be passed to another revision. Each script
uses one fixed workspace revision. After an update, methods on an
older retained `AnalysisRevision` raise `RuntimeError` containing `ContentModified`;
acquire `workspace.analysis()` again and recompute identities. Already returned
native values remain values from their producing revision. The analysis handle's
`revision` is the revision in which it was captured.

For traversal examples, use the
[semantic recipe](skills/cangjie-mcp/references/semantic.md). Inference arrays use
the corresponding `Body` arena indices. Signature source-map ranges use
`TypeRefId.index`; missing references have no range, and binary or unavailable
declarations have an empty map. A written range belongs to its contextual source
or macro expansion, as identified by the source map.

Preserve the distinction between user errors, unsupported features and missing
inputs or inference limits. An empty result alone does not establish that the
analysis is complete.

Opaque identities come from analysis and retain native equality/hashing.
Direct Python construction is unavailable; resolve identities through their
producing context. Returned native values remain associated with their producing
revision; immutable fields stay read-only.

### Composable semantic views

`a.semantic()` creates views from the same checked revision. Objects retain
their analysis context while composing resolution, project, syntax and
relationship queries. Returned gaps and unavailable states retain the native
loupe contract; an empty collection does not establish complete analysis.

Semantic views keep their originating snapshot and reject operations after an
input change. Keep one `SemanticAnalysis` when combining contextual objects or
resolving syntax pointers: a pointer from another analysis is rejected even if
its file and range match. Constructors carrying snapshot state are hidden.
`SemanticIdentity` is a copied identity, valid only in its producing context.

Location text comes from the retained snapshot. Coordinates are zero-based
`(line, UTF-8 byte column)` pairs. Call-resolution values retain substitutions,
argument mapping and unresolved or ambiguous outcomes.

### Other analysis queries

Native navigation/reference/symbol results contain `FileId`; resolve paths
through the same revision. A result's expansion identity qualifies its ranges:
inspect it before slicing text. Expansion queries require available expansion
text and valid UTF-8 byte boundaries; their results may point into source or
another expansion.

Formatting does not discover `cjformat.toml`. Applying returned edits follows
the [source-change contract](#applying-source-changes).

## Source excerpts

The injected helper `source_excerpts(analysis, requests, max_bytes=12000,
offset=0, limit=20, context_lines=0)` presents an ordered list of (path, TextRange)
pairs from one analysis revision. It adds no semantic query or write API. See the
[navigation recipe](skills/cangjie-mcp/references/navigation.md) for selection examples.

The shared budget counts compact UTF-8 JSON bytes for the page. Each excerpt is
returned whole, with request index, path, one-based inclusive start/end lines,
requested/shown byte ranges and source. `context_lines=0` returns exactly the
requested range; larger values add complete surrounding lines. Ranges count
UTF-8 bytes and remain end-exclusive. Empty ranges and EOF are supported;
invalid UTF-8 boundaries raise an error. Expansion-relative ranges require the
[expansion recipe](skills/cangjie-mcp/references/expansions.md).

The page includes revision, total, returned, omitted, next_offset and
required_bytes. total counts selected input requests, not unqueried declarations;
omitted is total minus returned, including earlier pages. next_offset is the
first remaining request, or null. Recreate the same ordered requests at the same
revision to continue; edits invalidate ranges and pagination offsets.

The helper stops before an excerpt would exceed the budget or page limit.
required_bytes is normally null; otherwise it reports the candidate page size
that blocked progress. If next_offset equals offset, select a smaller range,
reduce context_lines or increase max_bytes. The response-wide
[output budget](#script-execution) applies independently to the complete reply.

## Revisions and synchronization

Paths are absolute or relative to the selected workspace root (defaulting to
`--dir`, or the startup working directory when omitted).
Offsets/ranges count UTF-8 bytes from zero; ends are exclusive. An offset must
fall on a UTF-8 boundary. The database, query caches, macro build artifacts and SDK
macro processes persist until their workspace session is evicted or the MCP
process exits. Closing the client's stdin stops all workspace workers and closes
SDK processes before removing each session's temporary build directory. There is no daemon or cache shared across MCP connections.

The first script prepares the workspace. Between calls a worker polls disk every
500 ms, rediscovers project membership and compares source contents. Before every
script the server also synchronizes disk inputs and finishes required macro
builds/expansions, repeating the disk check if preparation observed changes.
Unchanged files, queries and expansions are reused. Binary packages use their
size/mtime stamps, as in cjls. Polling is a prototype mechanism: rediscovery and
source reads still cost work even when no analysis inputs change.

One gate covers background updates, final synchronization, Python execution and
result serialization. Files edited during a script are incorporated after it
finishes. Even `reload()` only requests a later preparation; it never changes the
running script's database. The response's `revision`, `workspace.revision` and a
new `workspace.analysis().revision` agree. Revisions increase for observed input
changes or explicit reloads; a synchronization with no changes keeps its number.
A revision identifies the loaded analysis, not an atomic filesystem snapshot or
proof that disk is still unchanged when a result arrives. Ordinary Python file
I/O reads live disk, independently of the analysis revision.

Macro calls have a one-minute deadline; compiler builds and the whole preparation
have no hard timeout. Missing required SDKs, failed builds and unsent calls appear
as structured workspace.macros.diagnostics, independently of state. Loading
failures are in workspace.loadDiagnostics. Partial analysis remains usable.
Preparation subprocess output goes to server stderr; tool-visible diagnostics
carry known locations as fields, never as a path:line:column message prefix.
Unresolved names remain per-file analysis diagnostics.
Failures before Python starts are tool errors with a null revision. Script errors
include the revision used and are never retried automatically: Python may have
already performed external effects. Preparation failures are retried before a
later script; no script is run on a workspace whose preparation threw.

## Script execution

The optional tool argument maxOutputBytes defaults to 24000 ([D164](../../docs/adr/0164-cjmcp-output-budget.md)). It bounds the
complete compact UTF-8 JSON payload (result, stdout, stderr, error, revision,
root and sessionId),
before the MCP text/structuredContent wrapper duplicates it. It is not a wire-size,
token, memory or execution limit. A nonnegative integer is required; 0 explicitly
allows an unlimited reply. Existing code-only calls remain valid, with this new
default protection. Small results have the same fields as before.

After execution/stream capture, exceeding the limit returns isError=true with
OutputBudgetExceeded, empty stdout/stderr, null result, the original revision and
outputBudget {limit_bytes, actual_bytes, retained, largest_fields}.
`largest_fields` lists up to five `{field, bytes}` entries for response channels
and immediate fields of a result object, ranked by compact UTF-8 JSON value size.
For example, `result.files` reveals an oversized inventory without recovering it.
Field labels are capped at 160 characters; nested fields are not traversed.
Parent/child sizes overlap and must not be added together. Nothing is partially
truncated. This actionable error envelope is exempt from the requested budget,
so even maxOutputBytes=1 reports a useful failure. Side effects have already
happened; scripts are never replayed automatically.

The complete rejected payload, including stdout, stderr, traceback and its
original revision, is injected as last_output in subsequent scripts. It is null
before the first rejection and retained until another rejection replaces it.
Filter that dictionary in Python, for example result = last_output["result"][0],
or retrieve it whole with code="result = last_output", maxOutputBytes=0. A
successful recovery does not clear it. It is session-local, holds one response
in memory and is not a durable artifact. Native objects are not retained by this
feature: the saved value is a JSON round-trip. It may describe an older revision;
reacquire analysis and compare revisions before acting on saved source ranges.
The budget prevents context overflow, not the memory needed to construct and
serialize a large result or capture native output.

Each script gets a fresh global namespace and ordinary Python imports. Assign
JSON-serializable data or supported diagnostic/status values to `result`, print output, or both. The MCP response has
`result`, captured `stdout`/`stderr`, `root`, `sessionId`, `revision`,
and `error` (a traceback or null),
in both `structuredContent` and text content. Non-serializable results are script errors.
Python exceptions, including `SystemExit`, become tool errors; the session can
continue. File descriptor redirection captures subprocess/native output as well
as Python streams, keeping it off the MCP wire.

This is trusted local Python execution with the process's filesystem/network
access, without a sandbox or hard execution timeout. Calls run sequentially.
Workspace and analysis queries belong to the executing script; join any Python
threads that use them before returning from the tool.
Native filesystem watchers, editor buffers, cancellation, HTTP and parallel tool
requests are outside this experiment. The existing macro host limitations,
including K28's conflicting loaded libraries within a load, still apply.

## API documentation

Each script receives `api_docs`, which reads the generated `.pyi` reference
supplied with the server. It is independent of the selected workspace and revision:

```python
result = api_docs.read_symbol("cjmcp/analysis.pyi", "AnalysisRevision.symbols")
```

`files()` returns sorted paths relative to the documentation root. `read(path)`
returns UTF-8 text; paths in declaration comments use the same root, for example
`loupe.hir/def_map.pyi`. `Workspace` members are in `cjmcp/python.pyi`;
`AnalysisRevision` members are in `cjmcp/analysis.pyi`. Select a known member
directly by name to get its signature and short contract; skip discovery when
the path and name are known. Follow returned-type links only for fields or
contracts needed by the task. Native objects are injected into
scripts; these paths do not identify importable Python modules. A type documented
for a returned value need not be a global name in the script: inspect `type(value)`
when needed. Namespace registration is separate from type documentation.

The server first uses `api_docs/` beside its executable. A source build in
`<checkout>/target/<profile>/bin/` falls back to that checkout's
`modules/cjmcp/api_docs/`. It never selects documentation from the analyzed
workspace or working directory. Keep `api_docs/` beside a relocated executable.
Missing documentation/files raise `FileNotFoundError`; absolute paths, parent
traversal, non-`.pyi` paths and links outside the documentation root are rejected
with `ValueError`. Non-string paths raise `TypeError`.

If the path or name is unknown, filter `files()` or `outline(path, class_name)`
inside Python and return only matching names. For a known member-name fragment:

```python
result = [entry["symbol"] for entry in api_docs.outline(
    "cjmcp/analysis.pyi", "AnalysisRevision")
    if "signature" in entry["symbol"].lower()]
```

Then select the relevant member with `read_symbol`. Avoid returning whole files
or classes. Use a top-level `outline(path)` only if the container is unknown.
A known nested declaration can be selected directly, for example
`api_docs.read_symbol("loupe.hir/body.pyi", "Expr.CallExpr")`.

`outline(path, symbol=None)` lists immediate declarations in source order, at the
file level or inside the named class. Each entry contains `symbol` (a dotted
qualified name), `kind` (`class`, `function` or `attribute`), `line` and `end_line`.
Line numbers are one-based, inclusive and include decorators. Nested classes are
listed without expanding their members. Overloads and property accessors have
separate entries with the same qualified name.

`read_symbol(path, symbol, *, max_bytes=12000)` returns complete declarations as
dedented text, including decorators and docstrings. All overloads or accessors
with the selected name are returned together, in source order. It parses the
reference with Python's AST; it never imports or executes a stub. Missing symbols
raise `KeyError`; malformed names raise `ValueError`, and non-string names raise
`TypeError`. An outline container must be a class. Both operations use the same
path validation and server-owned documentation as `read()`.

The selection limit counts UTF-8 bytes. An oversized selection raises `ValueError`
with its required size and guidance to select a member or increase `max_bytes`;
it never returns a truncated declaration. The limit must be a positive integer.
The regular `maxOutputBytes` response budget also applies, including JSON overhead.
Use `last_output` to recover an oversized response without repeating work.

The reference is generated and reviewed locally, then committed. Neither builds
nor artifact packaging run `cjpydoc`; the supplied files can lag binding changes.

## Binding implementation constraints

All types exported through `@DerivePython` carry `@PyDoc`. Document exported
methods and properties, and retain documented field contracts in Python as well;
ordinary Cangjie doc comments remain the source documentation. Use `@PyName` when the Python registry
name differs from the declaration name, so `__name__` and introspection agree
with the injected name. Keep existing Python names stable.
Retain `@PyDoc` even when a source comment describes the same declaration:
the pinned interop generator needs it for runtime `__doc__`; generating `.pyi`
from comments alone does not preserve native Python documentation.
The process regression checks every injected class for a nonempty `__doc__` and
an `__name__` matching its injected name. Exposed callables also need docs, except
standard string/hash operations. Keyword-named fields use `@PyName` to expose
valid Python identifiers: `Redefinition.def` and `NoSpecific.def` are available as
`definition`. Constructor argument order stays unchanged; `__match_args__` uses
the exported field names.

`@DerivePython` from `py_interop` exports the selected original analysis types,
including their constructors, fields, properties and methods. Immutable fields
remain read-only. The bindings are built on all native platforms; `runPython`
currently supports native Linux x86_64 and returns an unsupported-platform tool
error elsewhere. Cross compilation of the Python exports has not been verified.
Constructors hidden with `@PyIgnore` follow the ordinary-`init` exception in
[C2](../../docs/design/03-conventions.md#c2-primary-constructors).
Exported value types implement equality, hashing and string conversion directly
in their declarations so `@DerivePython` can bind those native methods without
standard deriving or special trait modes.
Calca identities use `@DerivePython[opaque]` above their identity-generating macro.
Descriptors configure callbacks lazily when their Python class is initialized.
The full workspace builds at normal release `-O2`; no `loupe` optimization override
is required. See [K30](../../docs/sdk-issues.md#k30) for the earlier compiler failures
and the validated workaround in binding generation.

The interop pin keeps the mutable proxy registry in reference types. On Linux
x86_64 with the pinned SDK and CPython 3.14, reentrant proxy allocation with nested
generic struct registry receivers produced invalid GC roots and SIGSEGV. Keep
that registry representation until an SDK-only reproduction establishes a safe
alternative. Raising `cjStackSize` did not resolve the observed failure.

Native conversion must also retain borrowed Python references: an owning wrapper
increments the reference before its finalizer can decrement it. This applies to
callback arguments, enum variant names and exported Python class handles. The
real-process allocation regression exercises constructors and payload getters
without loading a workspace.

Generated callbacks catch Cangjie `Exception` and `Error` before returning across
the C ABI. They report Python `RuntimeError` with the native message and the
appropriate callback failure sentinel. A query for an unloaded file must be
catchable by the script, and subsequent queries must remain usable; an exception
escaping the callback can corrupt CPython's stack and crash a later operation.

Proxy lifetime is still experimental: the pinned `py_interop` registry retains
exported native values, and reclaiming those entries is not implemented here.
Repeated large traversals can retain analysis results. This still limits session
length and traversal volume; keeping the process alive for a chat does not resolve
native proxy retention.

## Task evidence helpers

The server advertises these helpers and exact API discovery with the
`taskEvidence` feature in `server_info["_meta"]["features"]`.

`exact_symbols(analysis, paths, name)` returns all exact, case-sensitive
`(path, symbol)` matches from complete file outlines in explicit paths.
Duplicate paths are ignored; overloads remain separate. It does not use the fuzzy
workspace-symbol limit.

`result_page(rows, offset=0, limit=20)` pages already projected rows with totals,
omissions and continuation. It limits rows, not bytes; the response budget still
applies. Sort rankings and handle ties before paging.

`declaration_range(analysis, path, selection, kind)` selects the smallest source
syntax node of the exact kind whose direct Name child matches the selection, then includes
consecutive enclosing macro-declaration wrappers. It raises ValueError for
unavailable/missing/ambiguous syntax. It preserves annotations such as TestCase
that an outline or bare FuncDecl range excludes; external trivia stays outside.
Recompute after edits and validate replacements with the compiler.

`api_docs.find_symbol(name)` finds an exact dotted declaration name across
bundled stubs and returns all matching paths and declaration counts.
Use `read_symbol` for the selected contract; no guessed import module is needed.
