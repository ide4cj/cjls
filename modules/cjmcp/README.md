# Experimental Cangjie MCP server

`cjmcp` is a separate executable over `project_model` and `loupe`, in the same
workspace as `cjls`. It shares the analysis implementation without depending on
LSP handlers, Python bindings or a copy of the analyzer.

## Build and connect

Use the pinned SDK and environment from [Development](../../docs/development.md).
From the repository root:

```bash
cjpm build -m modules/cjmcp
cjHeapSize=2GB target/release/bin/cjmcp --dir /absolute/path/to/project
```

The process waits for MCP traffic; ordinary terminal input is not a CLI session.
An MCP client's server configuration can use:

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

The executable links the runtime statically. Runtime SDK discovery follows
`project_model`; set `CANGJIE_HOME` explicitly if automatic discovery does not find
the SDK to analyze against. The 2 GB heap setting is recommended for workspaces;
the runtime's default heap is only 256 MiB.

## Experiment contract

This implements the [MCP 2025-11-25 lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
and [tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
over newline-delimited JSON-RPC on stdio. Send `initialize`, then
`notifications/initialized`, before using tools. Other offered versions receive
`2025-11-25`; clients must accept that version or disconnect. This prototype
does not implement newer stateless MCP revisions. stdout contains protocol
messages only; fatal diagnostics go to stderr. Closing stdin ends the process.
Messages must end in a newline and are limited to 8 MiB.

| Tool | Arguments | Result |
|---|---|---|
| `workspace` | none | Load lazily; return files, loading problems and macro status |
| `reload_workspace` | none | Replace the database with a fresh disk/project load |
| `diagnostics` | `path` | Syntax and semantic diagnostics |
| `file_structure` | `path` | Nested declaration outline |
| `hover` | `path`, `offset` | Declaration/type/documentation, or `hover: null` |
| `definition` | `path`, `offset` | Declaration paths and ranges |

Paths are absolute or relative to `--dir` (the working directory by default).
Offsets and ranges count UTF-8 bytes from zero; range ends are exclusive. An
offset must fall on a UTF-8 boundary. Results have both `structuredContent` and
JSON text content. Invalid requests/arguments produce JSON-RPC errors; loading
and query failures produce tool results with `isError: true`.

Calls run sequentially against one disk revision. Repeated queries reuse loupe's
incremental query cache. Disk edits remain invisible until `reload_workspace`;
a reload rebuilds the database, so additions, deletions and manifest changes are
included. Inspect `workspace.problems` before relying on cross-package answers.
A failed reload preserves the previous database.

SDK macro expansion, file watching, editor buffers, cancellation, parallel
requests, HTTP, resources and prompts are outside this first experiment.
Analysis can use loupe's existing macro fallbacks, but workspace macros are not
built or executed. `macrosExpanded: false` is returned explicitly; results around
macro-generated code can be incomplete. This is not an MCP replacement for the
LSP executable; editor integration continues through `cjls`.

## Verify

```bash
cjpm test -m modules/cjmcp --no-progress --target-dir target/test
python3 -m unittest discover -s tests/mcp -v
```

The unit tests cover lifecycle, errors, notifications and tool validation. The
stdio test drives the actual release binary without closing stdin to make it
answer, checks UTF-8 ranges and cross-query results, then edits/adds/deletes files
and reloads. `CJMCP_BIN` overrides the test executable.
