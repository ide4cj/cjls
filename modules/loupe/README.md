# loupe

Reusable incremental language analysis, independent of LSP. The
[architecture overview](../../docs/architecture.md#analysis-and-incremental-state)
explains its layers and source entry points. Current constraints are in the
[analysis rules](../../docs/design/02-analysis.md); the
[request slice](../../docs/design/01-request-slice.md) explains how the server uses
snapshots. [Analysis tests](../../docs/design/02-analysis.md#analysis-tests) describe
fixtures and SDK/corpus prerequisites. The [manifest](cjpm.toml) and [source](src/)
are the maintained dependency and API references.
