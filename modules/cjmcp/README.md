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
establish a fix for that session instability. [K31](../../docs/sdk-issues.md#k31)
records a separate confirmed exclusive-scope stack-guard defect and a manual
SDK-only probe. Python script syntax still follows
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

The server instructions contain a compact query map, including macro expansion,
navigation, inference, members and formatting. Use it directly; the
[Python query map](python-api.md#query-map) is the readable counterpart.
Use one
[task recipe](skills/cangjie-mcp/SKILL.md) for an unfamiliar operation. Configure
the connection with [agent setup](agent-setup.md).

Use those queries and recipes directly, without a preliminary reference lookup.
If a specific missing API detail blocks the next query, use
[API discovery](skills/cangjie-mcp/references/discovery.md) for a targeted lookup
in the supplied `.pyi` reference, then return to the task.
See [API documentation](python-api.md#api-documentation) for reference contracts.

The [runtime guide](python-api.md) covers workspace sessions, revision freshness,
source coordinates, serialization and write effects. It also records the
[binding constraints](python-api.md#binding-implementation-constraints).
Check `server_info` before consulting another checkout's documentation. The proxy
registry still retains exported native values, limiting session length and
traversal volume.

### Regenerate the reference

To refresh the checked-in reference after building the workspace, run
`python3 scripts/generate_pyi.py -o modules/cjmcp/api_docs` in the SDK environment.
Use a `cjpydoc` supporting `--python-package-source`; the script supplies source
roots for imported type links and declares the manual `BodySource` adapter with
`--python-type=loupe.hir.BodySource=BodySource`. Use a generator that selects the
evaluated `DerivePython` input and rejects unmapped signature types.
Descriptions prefer `@PyDoc`, then source comments;
`@PyIgnore` and `@PyName` follow the runtime bindings. Review the generated diff.

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

The macro process test executes the shipped expansion/navigation recipe in one
tool call. This verifies the example's API use and result serialization, not
agent efficiency. Compare guidance using identical tasks in fresh agent sessions,
with the same model/settings, project revision and server binary. Retain tool
scripts, responses and actual usage when available; compare answer completeness,
errors and documentation-only calls before interpreting call/token reductions.

### Immediate call evidence

The revision exposes `directCalls`, `callDeclaration` and `trackedCallRoots` for
script-controlled call graph inspection. Edges retain native declaration identity
and source locations; gaps make unsupported execution effects explicit. See the
[shared coverage contract](../../docs/design/02-analysis.md#a39-partial-call-evidence) before interpreting an
empty result.
