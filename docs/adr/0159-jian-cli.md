# ADR-0159: Declare the server CLI with jian

Status: proposed

## Context

The server's CLI keeps a command enum, an argopt parser and a handwritten usage
string alongside the functions that execute commands. Adding or changing an
option requires keeping these descriptions consistent. The executable also has
two entrypoint contracts: no arguments starts LSP over stdio, and
`--config-schema` prints one JSON document for editor clients (D32, D79).

## Decision

Declare commands and their typed arguments with
[jian](https://github.com/FilaCo/jian)'s macros in the executable module. Use a
callback with invocation metadata for the default LSP action and the standalone
schema option. Supply the logger through the application's typed context.
Generate help and usage errors from those same declarations.

Keep command execution in cjls and analysis in its existing libraries. Declare the
git dependency in the server manifest and retain its resolved commit in
`cjpm.lock`. Continuing with argopt would avoid a dependency, but would keep parsing,
dispatch and help as separate descriptions of the same interface.

## Consequences

The first build fetches jian; macro expansion is checked by building and testing
the consuming executable. Dependency updates need CLI and LSP lifecycle checks
on the supported SDK. The server remains statically linked.

Existing command names, directory/check options and exit codes remain available.
Command-specific help is generated; invalid input goes to stderr with exit 2.
The callback starts LSP only when no command was requested, so unknown names and
help cannot fall through to a server session. No CLI output is emitted while
serving LSP.
