# Experimental runPython MCP server

`cjmcp` exposes **one MCP tool, `runPython`**. It embeds CPython in the Cangjie
process and gives scripts a live workspace and native `loupe` analysis objects.
Python can traverse, filter and aggregate those objects in one tool call. The
existing LSP executable uses the same analysis implementation.

## Build and connect

### Download the Linux artifact

The [MCP Linux artifact workflow](https://github.com/ide4cj/cjls/actions/workflows/cjmcp.yml)
builds Linux x86_64 archives on pushes to `experiment/cjmcp` and pull requests
targeting it. Download the `cjmcp-linux-x86_64-<commit>` artifact from a successful run and unzip it, then:

```bash
sha256sum --check SHA256SUMS
tar -xzf cjmcp-linux-x86_64-*.tar.gz
./cjmcp-linux-x86_64-*/cjmcp --help
```

The archive includes `BUILD-INFO` with the source commit, SDK pin and target,
plus the SDK checksum pins and licenses. Actions retains the download for 30 days;
it is an experimental artifact, separate from cjls releases. CI runs the protocol
unit tests and the real-process MCP tests against the unpacked executable before
uploading it.

Builds use Ubuntu 22.04; the executable still requires compatible system glibc
and libstdc++, Python 3 with a shared `libpython` and its standard library, and a
Cangjie SDK for SDK-backed analysis. CI tests with Python 3.12. Python and the SDK
are not bundled. Set `PYTHON_DYNLIB` to the shared library's absolute path if
automatic discovery fails, and `CANGJIE_HOME` to the analysis SDK directory.
Use the unpacked executable's absolute path in the client configuration below.

### Build from source

The first embedded runtime experiment supports native Linux x86_64. Use the
pinned SDK and environment from [Development](../../docs/development.md), and
install Python 3 with its shared `libpython` library. From the repository root:

```bash
cjpm build -m modules/cjmcp
cjHeapSize=2GB target/release/bin/cjmcp --dir /absolute/path/to/project
```

`py_interop` is built statically from a pinned fork revision with runtime and
binding-generation fixes. CPython itself is loaded dynamically; `PYTHON_DYNLIB` can select its
shared library explicitly. SDK discovery follows `project_model`; set
`CANGJIE_HOME` if automatic discovery does not find the SDK to analyze against.
The 2 GB heap setting is recommended for workspaces (the runtime defaults to
256 MiB).

An MCP client can use:

```json
{
  "mcpServers": {
    "cangjie": {
      "command": "/absolute/path/to/cjls/target/release/bin/cjmcp",
      "args": ["--dir", "/absolute/path/to/project"],
      "env": {"cjHeapSize": "2GB"}
    }
  }
}
```

The server implements the [MCP 2025-11-25 lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
and [tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
over newline-delimited JSON-RPC on stdio. Initialize, send
`notifications/initialized`, then call `runPython` with `{ "code": "..." }`.
Other offered versions receive `2025-11-25`; clients must accept it or disconnect.
Newer stateless MCP revisions are not implemented. Closing stdin ends the
process. Incoming messages must end in a newline and are limited to 8 MiB.

## Python API

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
| `problems` | Loading problems; inspect before trusting cross-package answers |
| `hasExpandedMacros` | `False` in this experiment |
| `files()` | Source paths of the loaded project |
| `structure(path)` | Native `StructureNode` objects with nested `children` |
| `diagnostics(path)` | Native `Diagnostic` objects |
| `hover(path, offset)` | Native `HoverResult` with `HoverItem` objects, or `None` |
| `definition(path, offset)` | `Location` values containing a path and native ranges |
| `reload()` | Replace the database with a fresh disk/project load |
| `analysis()` | Retain an `AnalysisRevision` for HIR, inference and navigation |

### HIR and inference

`workspace.analysis()` captures the current loaded disk revision. Keep this object
with the `DefId`, `Ty`, `FileId` and source identities it produces: identities are
scoped to their database and must not be passed to another revision. Reloading the
workspace leaves retained revisions usable, including their database caches and
source text. Holding a revision also retains that database's memory.

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
| `highlights(path)`, `folding(path)`, `selection(path, offset)` | Semantic highlights, folds and enclosing selections |
| `symbols(query, limit)` | Search workspace declarations |
| `members(def, name)`, `supertypes(def)` | Inspect members and type hierarchy |
| `field(def, expr)`, `receiver(def, expr)`, `receiverType(def, expr)` | Inspect member access resolution |
| `macroCall(path, offset)`, `expansion(call)`, `expandedFile(path, header)` | Inspect available macro fallbacks and their source mappings |

Native navigation/reference/symbol results contain `FileId`; call `path(fileId)`
on the same revision. `NavigationTarget.expansion` identifies expansion-relative
ranges. SDK macros remain unexpanded by this server.

All exported classes are present in each script namespace, including `Body`,
`Expr`, `Pat`, `Signature`, `SignatureTypes`, `TyKind`, `InferenceResult`,
`InferenceDiagnostic`, scope/source-map types, completion/navigation/highlight
results, `Cfg` and `CfgExpr`, plus the original workspace result types. The
registration in `src/python_types.cj` is the complete list. Generic syntax trees,
calca database mutation/storage, and collection-backed package indexes are not
exported. This is not a binding of every public loupe API.

Paths are absolute or relative to `--dir` (the working directory by default).
Offsets/ranges count UTF-8 bytes from zero; ends are exclusive. An offset must
fall on a UTF-8 boundary. The workspace is loaded lazily and persists across
calls. Queries reuse its caches; disk edits remain invisible until `reload()`.
A failed reload preserves the previous database. Analysis objects already held
by Python remain values from the revision in which they were obtained.

Each script gets a fresh global namespace and ordinary Python imports. Assign
JSON-serializable data to `result`, print output, or both. The MCP response has
`result`, captured `stdout`/`stderr`, and `error` (a traceback or null), in both
`structuredContent` and text content. Non-serializable results are script errors.
Python exceptions, including `SystemExit`, become tool errors; the session can
continue. File descriptor redirection captures subprocess/native output as well
as Python streams, keeping it off the MCP wire.

This is trusted local Python execution with the process's filesystem/network
access, without a sandbox or hard execution timeout. Calls run sequentially.
SDK macro execution, file watching, editor buffers, cancellation, HTTP and
parallel requests are outside this first experiment. loupe's existing macro
fallbacks still apply, but answers around macro-generated code can be incomplete.

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
is required. See [K29](../../docs/sdk-issues.md#k29) for the earlier compiler failures
and the validated workaround in binding generation.

Proxy lifetime is still experimental: the pinned `py_interop` registry retains
exported native values, and reclaiming those entries is not implemented here.
Repeated large traversals can retain analysis results. This needs a lifetime fix
before treating the prototype as a long-running service.

## Verify

```bash
cjpm test -m modules/cjmcp --no-progress --target-dir target/test
python3 -m unittest discover -s tests/mcp -v
```

Protocol unit tests cover lifecycle, negotiation, notifications and argument
validation. The real-binary Linux test executes Python over original loupe
objects, checks cross-file definition, generic inference, native enum payloads,
source maps, completion details, references, retained revisions and UTF-8 offsets,
captures native output,
recovers from script/serialization errors, then edits/adds/deletes files and
reloads the same workspace. It also runs in CI; `CJMCP_BIN` overrides the binary.

The full Cangjie suite includes `ServedDiagnosticsGateTest`, which checks the
expanded Python bindings for false diagnostics. Run it without excluding gates
when changing the exports or the pinned interop generator.
