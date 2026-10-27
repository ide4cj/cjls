# ADR-0152: Project formatter policy has three explicit settings

Status: accepted, 2026-10-27

## Context

D150's fixed policy makes width and indentation unsuitable for projects with
different conventions. Expanding even a short value-producing `if/else` also
makes assignments harder to scan. CLI, editor and generated source must agree.

## Decision

- Supersede only D150's prohibition on configuration and mandatory multiline
  simple `if/else`. Retain its document IR, preservation and range contracts.
- Support exactly `line_width` and `indent_width` (positive integers) and
  `simple_if` (`"compact"` or `"multiline"`) in `cjformat.toml`. Defaults remain
  100 Unicode scalar columns, four spaces and multiline control bodies.
- Compact mode permits a complete `if/else` on one line only when both blocks
  contain exactly one expression, there are no comments, and the whole expression
  fits. Otherwise use the existing multiline layout. Nested `else if` remains
  multiline. Never remove braces or change tokens.
- The library takes immutable options explicitly, including range formatting.
  A separate `cjformat.config` package searches from a source/output file's parent
  to the filesystem root. The nearest config replaces its ancestors; omitted keys
  use defaults. Reject unknown keys, wrong types, invalid values and malformed TOML.
- CLI and LSP load this project policy per formatting operation. LSP client
  indentation options do not override it; virtual documents use defaults. Changes
  saved to config take effect on the next request, without restarting the server.
  Formatting reads config from disk, including when a config buffer has unsaved edits.
  Report invalid config as a CLI failure or LSP request failure, without formatting
  that document. Generators resolve policy from the final output path, not cwd or
  a temporary destination used to verify freshness.

## Consequences

The repository migration records its policy explicitly and regenerates all source
with it. No chain, assignment or pattern style switches are added. Files under a
nested config may have a different policy. No config merging, editor-only overrides,
extra CLI flags or settings UI are introduced in this version.
