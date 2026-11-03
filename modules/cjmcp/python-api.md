# cjmcp Python API

For connection configuration, see [agent setup](agent-setup.md). Read only the
section needed to resolve an API contract; common tasks use server instructions.
The server sends a semantic-query playbook in the MCP initialization response.
[Task recipes](skills/cangjie-mcp/SKILL.md) cover queries and runtime API discovery;
they ship with the Linux archive alongside the skill. Native objects and types
are injected into scripts; there is no importable `loupe` Python package.

For example, a single script can find functions across the workspace:

```python
result = [
    {"path": path, "name": node.name, "start": node.selectionRange.start}
    for path in workspace.files()
    for node in workspace.structure(path)
    if node.kind.toString() == "Function"
]
```

`node` is a native `loupe.StructureNode` exported through `py_interop`, and
`node.range` is the original `ginkgo.TextRange`. They are not JSON dictionaries.
The workspace handle provides:

| Workspace member | Result |
|---|---|
| `root` | Absolute root path |
| `problems` | Loading, macro build and expansion problems; inspect before trusting answers |
| `hasExpandedMacros` | Whether macro preparation finished without build errors, failed or unsent resolved calls |
| `files()` | Source paths of the loaded project |
| `structure(path)` | Native `StructureNode` objects with nested `children` |
| `diagnostics(path)` | Native `Diagnostic` objects |
| `hover(path, offset)` | Native `HoverResult` with `HoverItem` objects, or `None` |
| `definition(path, offset)` | `Location` values containing a path and native ranges |
| `revision` | Session-local revision used by this script and returned in the tool response |
| `reload()` | Request preparation after this script; the running script keeps its revision |
| `analysis()` | Retain an `AnalysisRevision` for HIR, inference and navigation |

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
ranges. SDK macro outputs are loaded before the revision is returned.
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

## Revisions and synchronization

Paths are absolute or relative to `--dir` (the working directory by default).
Offsets/ranges count UTF-8 bytes from zero; ends are exclusive. An offset must
fall on a UTF-8 boundary. The database, query caches, macro build artifacts and SDK
macro processes persist until the MCP process exits. Closing the client's stdin
stops the background worker and closes SDK processes before removing the session's
temporary build directory. There is no daemon or cache shared across MCP sessions.

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
have no hard timeout. Missing required SDKs, build failures and failed or unsent
resolved calls are reported in `problems` and make `hasExpandedMacros` false; the
partial analysis remains usable. Preparation subprocess output goes to server
stderr; `problems` is the tool-visible preparation report. Unresolved names remain
analysis diagnostics.
Macro diagnostic problems include `path:line:column: message`, with one-based
lines and UTF-8 byte columns. They use the same source ranges and hint text as
LSP diagnostics. A thrown macro exception is attached to the call when the SDK
provides no more precise source location; its original failure text is retained.
Failures before Python starts are tool errors with a null revision. Script errors
include the revision used and are never retried automatically: Python may have
already performed external effects. Preparation failures are retried before a
later script; no script is run on a workspace whose preparation threw.

## Script execution

Each script gets a fresh global namespace and ordinary Python imports. Assign
JSON-serializable data to `result`, print output, or both. The MCP response has
`result`, captured `stdout`/`stderr`, `revision`, and `error` (a traceback or null),
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

`@DerivePython` from `py_interop` exports the selected original analysis types,
including their constructors, fields, properties and methods. Immutable fields
remain read-only. The bindings are built on all native platforms; `runPython`
currently supports native Linux x86_64 and returns an unsupported-platform tool
error elsewhere. Cross compilation of the Python exports has not been verified.
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
