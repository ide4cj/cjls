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
plus the SDK checksum pins, licenses and generated `.pyi` API reference in
`api_docs/`. Keep that directory beside the executable when moving the installation.
Actions retains the download for 30 days;
it is an experimental artifact, separate from cjls releases. CI runs the protocol
unit tests and the real-process MCP tests against the unpacked executable before
uploading it.

Builds use Ubuntu 22.04; the executable still requires compatible system glibc
and libstdc++, CPython 3.9–3.14 with a shared `libpython` and its matching standard
library, and a Cangjie SDK for SDK-backed analysis. CI tests the same delivered
binary with every minor version in that range. These checks use regular
GIL-enabled CPython builds; debug and free-threaded builds have not been verified.
Python and the SDK are not bundled. Set `PYTHON_DYNLIB` to the shared library's
absolute path if automatic discovery fails, and `CANGJIE_HOME` to the analysis SDK directory.
For a Python installation outside the system prefix, also set `PYTHONHOME` to
that installation's prefix (`python3 -c 'import sys; print(sys.base_prefix)'`),
so the embedded interpreter can find its matching standard library.
Use the unpacked executable's absolute path in the client configuration below.
Select the library explicitly when multiple Python versions are installed.
No version-specific interop change is required for 3.9–3.13 in the checks below.
Intermittent native crashes during macro reload were observed on 3.10, 3.12 and
3.14 (see also [#596](https://github.com/ide4cj/cjls/pull/596)). Passing compatibility checks do not
establish a fix for that session instability. Python script syntax still follows
the selected interpreter: structural pattern matching (`match`/`case`) requires
Python 3.10 or newer.

### Build from source

The first embedded runtime experiment supports native Linux x86_64. Use the
pinned SDK and environment from [Development](../../docs/development.md), and
install CPython 3.9–3.14 with its shared `libpython` library. From the repository root:

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
Pass an optional absolute `root` in each call to select another project/worktree
without reconnecting; omission always uses `--dir`. Up to four independent
workspace sessions are cached by recency; calls remain sequential. See
[workspace selection](python-api.md#selecting-a-project-or-worktree) for isolation,
eviction and response identity.

Fixed JSON-RPC/MCP responses and the tool schema use wire types with
`@DeriveExt[ToJson]`. Keep arbitrary Python results dynamic; the Python encoder
handles native values and enforces the output budget before the Cangjie response
wrapper is serialized. Wire types use `@Serde[skipNone]`; use `Nullable` for fields
that must remain explicit JSON `null`.

Other offered versions receive `2025-11-25`; clients must accept it or disconnect.
Newer stateless MCP revisions are not implemented. Closing stdin ends the
process. Incoming messages must end in a newline and are limited to 8 MiB.

## Python API

Use the server instructions for common queries and one
[task recipe](skills/cangjie-mcp/SKILL.md) for an unfamiliar operation. Configure
the connection with [agent setup](agent-setup.md). Native objects are injected;
there is no importable `loupe` Python package. Return `server_info` to identify
the running build, Python API version and supported features before consulting
documentation from another checkout; see [server identity](python-api.md#server-identity).

Use `api_docs.files()` to list the supplied `.pyi` files and
`api_docs.read("cjmcp/python.pyi")` to read one through `runPython`.
Paths in declaration comments are relative to the documentation root.
The archive supplies the checked-in reference; building and packaging do not
run the local `cjpydoc` generator. See [API documentation](python-api.md#api-documentation)
for lookup and output-budget behavior.

Read the [API reference](python-api.md) only for detailed contracts:
[source changes](python-api.md#applying-source-changes),
[HIR and inference](python-api.md#hir-and-inference),
[other queries](python-api.md#other-analysis-queries),
[revision freshness](python-api.md#revisions-and-synchronization),
[execution](python-api.md#script-execution) and
[binding constraints](python-api.md#binding-implementation-constraints).
The proxy registry still retains exported native values, limiting session length
and traversal volume; a persistent process does not resolve that retention.

## Verify

```bash
cjpm test -m modules/cjmcp --no-progress --target-dir target/test
python3 -m unittest discover -s tests/mcp -v
```

The test driver needs Python 3.10 or newer. To test a different embedded
interpreter, keep `PYTHONHOME` unset for the driver and supply its prefix through
`CJMCP_PYTHONHOME`; only the server subprocess receives that value as `PYTHONHOME`.
For example:

```bash
CJMCP_PYTHONHOME=/opt/python3.9 \
PYTHON_DYNLIB=/opt/python3.9/lib/libpython3.9.so.1.0 \
CJMCP_PYTHON_VERSION=3.9 python3 -m unittest discover -s tests/mcp -v
```

`CJMCP_PYTHON_VERSION` makes the native allocation regression assert the embedded
minor version, so a passing matrix cannot silently use another installed runtime.
The CI compatibility jobs download the archive from the 3.14 build job and run
these tests with CPython 3.9–3.13; CPython 3.14 is checked before upload.

Protocol unit tests cover lifecycle, negotiation, notifications and argument
validation. The real-binary Linux test executes Python over original loupe
objects, checks cross-file definition, generic inference, native enum payloads,
source maps, completion details, references, retained revisions and UTF-8 offsets,
captures native output,
recovers from script/serialization errors, then edits/adds/deletes files and
synchronizes the same workspace. It also checks edits during a script, stable
revision numbers, nested workspace and std macro execution, changed macro
libraries, stale analysis handles and build failures. Unit tests verify that
unchanged synchronization preserves cached queries and that preparation cannot
overlap a script.
A real Git worktree scenario checks explicit root routing, canonical aliases,
independent edits/revisions/rejected output, invalid-root failures, bounded cache
eviction, invalidated retained handles, deletion/recreation and separate macro
builds for matching package names. It runs in CI; `CJMCP_BIN` overrides the binary.

The full Cangjie suite includes `ServedDiagnosticsGateTest`, which checks the
expanded Python bindings for false diagnostics. Run it without excluding gates
when changing the exports or the pinned interop generator.

### Maintain agent guidance

Update affected recipes and server instructions alongside binding changes. Keep
examples focused on tasks and native names rather than a handwritten type catalog.
Validate discovery and examples with the real-process MCP tests above; load only
the relevant recipe when evaluating an agent task.

### Immediate call evidence

The revision exposes `directCalls`, `callDeclaration` and `trackedCallRoots` for
script-controlled call graph inspection. Edges retain native declaration identity
and source locations; gaps make unsupported execution effects explicit. See the
[shared coverage contract](../../docs/design/02-analysis.md#a39-partial-call-evidence) before interpreting an
empty result.
