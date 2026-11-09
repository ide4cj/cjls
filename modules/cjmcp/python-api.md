# cjmcp Python API

For connection configuration, see [agent setup](agent-setup.md). Read only the
section needed to resolve an API contract; common tasks use server instructions.
The server sends a semantic-query playbook in the MCP initialization response.
[Task recipes](skills/cangjie-mcp/SKILL.md) cover queries and runtime API discovery;
they ship with the Linux archive alongside the skill. Native objects and types
are injected into scripts; there is no importable `loupe` Python package.

## Server identity

Each script receives server_info, a fresh JSON dictionary also returned as
serverInfo by MCP initialize. Its name/version identify the executable product;
_meta contains apiVersion (currently 1), commit (full build-time Git SHA or null),
dirty (whether the build checkout had local changes, or null without Git identity)
and features: structuredDiagnostics, worktreeSessions, checkedSourceChanges,
sourceExcerpts, outputBudget and semanticViews. Feature names describe this binary's supported
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

Native node/range values are objects, not JSON dictionaries.
The workspace handle provides:

| Workspace member | Result |
|---|---|
| `root` | Absolute root path |
| `sdk` | Selected `CangjieHome` (path, discovery source, version and support channel), or `None` |
| `loadDiagnostics` | Structured project/binary/source loading diagnostics |
| `macros` | MacroStatus with state and structured preparation diagnostics |
| `files()` | Source paths of the loaded project |
| `structure(path)` | Native `StructureNode` objects with nested `children` |
| `diagnostics(path)` | Located WorkspaceDiagnostic values for this revision |
| `hover(path, offset)` | Native `HoverResult` with `HoverItem` objects, or `None` |
| `definition(path, offset)` | `Location` values containing a path and native ranges |
| `revision` | Session-local revision used by this script and returned in the tool response |
| `reload()` | Request preparation after this script; the running script keeps its revision |
| `analysis()` | Retain an `AnalysisRevision` for HIR, inference and navigation |

### Project build inputs

`workspace.sdk` is captured during preparation of the current revision. Its
`version` and `channel` are `None` when the selected compiler cannot report a
recognized version; the SDK itself remains available. Known channels are `LTS`,
`STS`, `pinned nightly` and `out of window`. Reading this value does not run the
compiler or repeat discovery. Changes to SDK selection open a new revision.

`a.semantic().project().modules()` exposes each module's `nativeLibraries()`:
read-only `NativeLibrary` values with a linker `name` and a `VfsPath` search `dir`.
These inputs are separate from Cangjie imports and source dependencies; a selected
library may not exist yet. Build and run native artifacts with the user's build
system before expanding macros that need them.

### Macro state and structured diagnostics

The old problems/hasExpandedMacros API is removed. Use workspace.loadDiagnostics
for loading issues, workspace.macros for macro preparation, and
workspace.diagnostics(path) for a selected file. These native values serialize
directly in result; no record projection or message parsing is needed:

~~~python
a = workspace.analysis()
result = {
    "root": workspace.root,
    "load_diagnostics": workspace.loadDiagnostics,
    "macros": workspace.macros,
    "diagnostics": workspace.diagnostics("src/main.cj"),
}
~~~

MacroStatus has a native MacroState enum and diagnostics. Compare state with
`MacroState.Pending()` or `MacroState.Settled()` in Python; variants support
`isinstance` and pattern matching. JSON encodes them as pending/settled strings,
including when returned directly or nested. String arguments to MacroStatus
are rejected. State is pending while the revision's macro preparation remains
to be performed; settled means its preparation attempt
finished, including a project with no macro calls. Settled can include errors.
Pending alone is not an error, and warnings do not become failures. Completion
and diagnostic severity are independent ([D165](../../docs/adr/0165-cjmcp-structured-diagnostics.md)).
The status and locations belong to the script's fixed revision, not a live worker
progress feed. Writing/reload does not change them during a script. This session
implementation still serializes preparation and Python, so normal scripts see
settled after preparation; this API change adds no wait or new scheduling policy.

WorkspaceDiagnostic exposes these native fields and their JSON representation:

| Field | Meaning |
| --- | --- |
| source | workspace (loading), macro (preparation), or analysis (per-file loupe diagnostics) |
| code | Stable preparation category, or null when the analysis API has no diagnostic code |
| severity | Native Severity; JSON error, warning or hint |
| message | Human-readable detail, with macro hints retained |
| path | Absolute source path, or null when no source file is attributable |
| range | Native TextRange; JSON {start, end}, zero-based UTF-8 bytes, end-exclusive; or null |
| line, column | One-based source line and UTF-8 byte column, or null when unavailable |
| unnecessary | Whether the source should be shown as unnecessary |

Preparation codes are workspace_load, macro_sdk, macro_build, macro_not_sent and
macro_expansion. SDK/build messages without a structured source location keep
location fields null; the server never guesses coordinates by parsing stderr.
Macro errors and warnings use loupe's mapped source range and retain hint text.
A thrown macro exception falls back to the call range if the SDK has no more
precise location. Per-file loupe diagnostics can also include macro findings;
requesting both channels can therefore expose the same finding.

In Python filter severity with d.severity == Severity.Error(), not a string
comparison. Return the values directly and JSON will contain lowercase strings.
TextRange and Severity are also supported by the tool's JSON encoder. Other
native analysis objects still need explicit projection. Plain json.dumps inside
a user script does not use the tool's encoder.

Scope diagnostic queries to relevant files. For diagnostic source excerpts, pass
non-null (path, range) pairs to [source_excerpts](#source-excerpts).
[Script execution](#script-execution) describes response budgets and recovery.

### Applying source changes

`workspace.applyChange(change, revision)` applies the shared `source_change`
model to disk. `SourceChange`, `FileChange`, `TextEdit` and `ApplyChangeResult`
are native Python bindings. See the [editing recipe](skills/cangjie-mcp/references/editing.md)
for construction, conflict checks, report fields and failure semantics.

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

```python
analysis = workspace.analysis()
result = []
for definition in analysis.declarations("src/main.cj"):
    item = analysis.item(definition)
    body = analysis.body(definition)
    inferred = analysis.infer(definition)
    result.append({
        "names": item.names,
        "locals": [
            {"name": local.name, "type": analysis.typeText(ty)}
            for local, ty in zip(body.locals, inferred.locals)
        ],
    })
```

Declarations include nested members, in source order. `body(definition)` returns
native HIR; `loweredBody(definition)` also returns its native source map, and
`scopes(definition)` returns lexical scopes. `signature` exposes written type
references, while `signatureTypes` exposes resolved types and signature errors.
`signatureWithSourceMap` returns a `LoweredSignature`: its `sourceMap.ranges`
is indexed by `TypeRefId.index`, with `None` for missing type references.
Ranges belong to the declaration's `definitionFile` (source or expansion text);
binary or unavailable declarations have an empty map. `typeAtRange` performs
an exact-range reverse lookup. These two Python classes are concrete adapters;
generic syntax pointers remain inside loupe, as with `BodySource`.
`infer` returns the native `InferenceResult`: expression, pattern and local types,
field/name resolutions, selected callees, argument-to-parameter mappings and
inference diagnostics. Its native lookup methods such as `calleeOf(ExprId(i))`
are available. Array indices correspond to the matching `Body` arrays.

`typeKind(ty)` returns a native `TyKind`, with variant classes such as
`TyKind.PrimTy` and `TyKind.DeclTy`. Python pattern matching and `isinstance` work
on returned variants; payloads are `field0`, `field1`, etc. `typeText(ty)` formats
a type and `isTypeUnknown(ty)` checks whether it is unknown. Preserve the distinction
between user errors (`ErrorTy`), unsupported features (`TodoTy`) and missing inputs
or inference limits (`UnknownTy`). `internType`, `substituteType` and `headTypes`
allow further type queries within the same revision.

`BodySource` adapts the generic syntax pointer to `range`, `kind` and `expansion`.
Source maps preserve `WrittenSource` versus `SyntheticSource`; a written source's
range belongs to its expansion when `expansion` is present. The convenience
`expressionRanges` and `localRanges` return `None` for synthetic and expanded
origins, so their non-null ranges always refer to the declaration's source file.

Calca-generated identities (`DefId`, `Ty`, `MacroCallId`, `Package`, `SourceFile`,
`BinaryPackageFile`) are exported directly in opaque mode, hiding database-taking
constructors and methods while preserving native comparison and hashing. Use the
producing revision's `item`, `parent`,
`definitionFile`, `definitionItem`, `sourceFileId`, `path` and type queries to
resolve them. `text(path)` reads the retained revision; `fileId(path)` resolves
its file identity. Original HIR/result values, constructors and methods are
exported directly with `@DerivePython`; immutable fields remain read-only.

### Composable semantic views

`a.semantic()` creates a native `SemanticAnalysis` snapshot from the same checked
revision. Start with `s.at(a.fileId(path), offset)` for an occurrence,
`s.syntaxAt(a.fileId(path))` for a lossless tree, or `s.project()` for the loaded
project. Occurrences compose through `resolution()`, `contextualFile()` and their
owner/definition objects. Objects expose types, syntax origins, body resolution,
usages, immediate calls and direct hierarchy relationships without another
database argument. Returned gaps and unavailable states retain the native loupe
contract; an empty collection does not establish complete analysis.

Semantic views keep their originating snapshot and reject operations after an
input change. Keep one `SemanticAnalysis` when combining contextual objects or
resolving syntax pointers: a pointer from another analysis is rejected even if
its file and range match. Constructors carrying snapshot state are hidden.
`SemanticIdentity` is a copied identity, valid only in its producing context.

The Python location helpers `sourceText()` and `coordinates()` return snapshot
text and a zero-based `(line, UTF-8 byte column)` pair. `excerpt(full=True)`
returns the full location range. Raw `Rope`, `LineColumn`, generic parser errors
and syntax kinds stay outside the bindings; use `kindName()` on a syntax element
and `message()`/`range()` on a syntax error. `VfsPath` supports string construction
with `file(path)`, display and path operations; its raw `std.fs.Path` accessor is
hidden. Project module identities are opaque, like other calca identities.

`InferenceResult.calls`, `setterCalls`, `callOf` and `setterCallOf` also expose
native `CallResolution`, `CallResolutionOutcome` and `GenericBinding` values.
They preserve final generic substitutions, argument mapping and unresolved or
ambiguous outcomes. See the [semantic recipe](skills/cangjie-mcp/references/semantic.md)
for a bounded traversal.

### Other analysis queries

An `AnalysisRevision` also offers:

| Methods | Purpose |
|---|---|
| `completions(path, offset)`, `completionDetails(path, offset, item)` | Ranked completion results and documentation |
| `references(path, offset)`, `related(path, offset)` | Workspace usages and same-file read/write occurrences |
| `typeDefinition(path, offset)`, `implementations(path, offset)` | Navigate to types and implementations |
| `prepareCallHierarchy(path, offset)`, `incomingCalls(entry)`, `outgoingCalls(entry)` | Callable roots and grouped explicit call sites |
| `highlights(path)`, `folding(path)`, `selection(path, offset)` | Semantic highlights, folds and enclosing selections |
| `symbols(query, limit)` | Search workspace declarations |
| `fileSymbols(path)` | File declarations in outline order, including container names |
| `members(def, name)`, `supertypes(def)` | Inspect members and type hierarchy |
| `allMembers(def)` | All members of a type/extend, or the type around a member; includes inherited members, visible extensions and overloads |
| `field(def, expr)`, `receiver(def, expr)`, `receiverType(def, expr)` | Inspect member access resolution |
| `macroCall(path, offset)`, `expansion(call)`, `expandedFile(path, header)` | Inspect macro expansions and their source mappings |
| `hoverInExpansion(call, offset)`, `definitionInExpansion(call, offset)`, `typeDefinitionInExpansion(call, offset)` | Query names at validated UTF-8 byte offsets in expansion text |
| `formatting(path, options=...)`, `rangeFormatting(path, range, options=...)` | Return native `TextEdit` values without applying them |
| `builtinTypeDoc(name)`, `builtinAnnotationDoc(name)`, `builtinMacroDoc(name)` | Native `BuiltinDoc` values, or `None`; annotation/macro names exclude `@` |
| `newFilePackageLine(path)` | Package header for a new path from the loaded project and revision text, or `None` outside its packages |

Native navigation/reference/symbol results contain `FileId`; call `path(fileId)`
on the same revision. `NavigationTarget.expansion` identifies expansion-relative
ranges. Expansion availability must be checked for queries that depend on macro output.
Expansion queries reject unavailable expansion text and invalid byte positions;
their hover ranges refer to that expansion. Navigation targets may refer to source
or another expansion; inspect `NavigationTarget.expansion` before slicing text.

Formatting uses explicit `FormatOptions`, defaulting to line width 100, indentation
4 and `SimpleIf.Multiline()`. It does not discover `cjformat.toml`. Widths must be
positive; width counts Unicode scalars. Formatting returns `None` for syntax
errors and an empty list for already canonical input. Range formatting validates
both UTF-8 boundaries and formats the enclosing syntax node. New-file headers do
not require that the file exists, and preserve macro-package metadata.
Python construction of `FormatOptions` accepts omitted keyword arguments using
the same native defaults, so `FormatOptions(indentWidth=2)` changes only indentation.
Unknown keywords, positional arguments and incompatible argument types raise `TypeError`.
The query overloads without `options` supply the library defaults.

All exported classes are present in each script namespace, including `Body`,
`Expr`, `Pat`, `Signature`, `SignatureTypes`, `TyKind`, `InferenceResult`,
`InferenceDiagnostic`, scope/source-map types, completion/navigation/highlight
results, `Cfg` and `CfgExpr`, plus the original workspace result types. The
registration in `src/python_types.cj` is the complete list. Generic syntax trees,
calca database mutation/storage, and collection-backed package indexes are not
exported. This is not a binding of every public loupe API.

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
outputBudget {limit_bytes, actual_bytes, retained}. Nothing is partially
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

## Binding implementation constraints

Use `@PyDoc` for Python-facing contracts on new exports; ordinary Cangjie doc
comments remain the source documentation. Use `@PyName` when the Python registry
name differs from the declaration name, so `__name__` and introspection agree
with the injected name. Keep existing Python names stable.

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
