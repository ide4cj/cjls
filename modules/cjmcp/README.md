# Experimental runPython MCP server

`cjmcp` exposes **one MCP tool, `runPython`**. It embeds CPython in the Cangjie
process and gives scripts a live workspace and native `loupe` analysis objects.
Python can traverse, filter and aggregate those objects in one tool call. The
existing LSP executable uses the same analysis implementation.

## Build and connect

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
The initial API is deliberately small:

| Workspace member | Result |
|---|---|
| `root` | Absolute root path |
| `problems` | Loading problems; inspect before trusting cross-package answers |
| `macrosExpanded` | `False` in this experiment |
| `files()` | Source paths of the loaded project |
| `structure(path)` | Native `StructureNode` objects with nested `children` |
| `diagnostics(path)` | Native `Diagnostic` objects |
| `hover(path, offset)` | Native `HoverResult` with `HoverItem` objects, or `None` |
| `definition(path, offset)` | `Location` values containing a path and native ranges |
| `reload()` | Replace the database with a fresh disk/project load |

`TextRange`, `StructureNode`, `StructureKind`, `Diagnostic`, `Severity`,
`HoverResult`, `HoverItem` and `Location` are available in the script namespace
for type checks. Analysis queries return native values; exported constructors
and methods are also available. `Location` translates loupe's navigation identity
to a path; the other result classes above are exported original types.
This is not yet a binding of every public loupe API.

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
Place `@DerivePython` below `@Derive[Equatable]` to avoid a compiler crash
when exporting generated equality operators. The root `loupe` package uses
`-O0` because its combined bindings still crash the pinned optimizer; analysis
subpackages retain `-O2`. See [K28](../../docs/sdk-issues.md#k28) for the measured scope.

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
objects, checks cross-file definition and UTF-8 offsets, captures native output,
recovers from script/serialization errors, then edits/adds/deletes files and
reloads the same workspace. It also runs in CI; `CJMCP_BIN` overrides the binary.
