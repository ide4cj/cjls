# cjls

The server executable, its LSP adapters and generated protocol types. The
[architecture overview](../../docs/architecture.md) explains module boundaries
and source entry points; [Development](../../docs/development.md#build-and-run)
provides build, CLI, SDK and linking procedures. The
[manifest](cjpm.toml) and [router](src/handlers/router.cj) are the maintained
references for dependencies and supported methods.

## Handler integration

Follow [Contributing](../../CONTRIBUTING.md) to add a handler. The
[request slice](../../docs/design/01-request-slice.md) owns the snapshot,
cancellation, retry, diagnostics and outbound-request contracts (S1–S14).
[Conversion code](src/handlers/to_proto.cj) translates analysis results;
analysis belongs in `loupe`. Position conversion must read the same snapshot as
the query. A read-loop handler changes inputs and cannot run queries or await
an outbound response; background writes return through `Loop.write`.

The [router](src/server/router.cj) takes a spec value so its parameter and result
types constrain the handler. A context selects execution mode: `Context<P>` runs
on the read loop, while `ReadOnlyContext<P>` runs on a worker with a snapshot taken
on arrival. A context lambda needs its type annotation to select the overload.
Registration is explicit; duplicate methods and readonly lifecycle handlers are
rejected because later messages must observe lifecycle changes.

[`@LspHandler`](src/macros/lsp_handler.cj) adds a context-taking overload and
extracts each dependency through `FromContext` or `FromReadOnlyContext`, with
params last. Its readonly marker selects the context at expansion time: macros
see tokens rather than inferred types. Invalid dependencies fail compilation in
the generated adapter; a function taking the context directly needs no macro.
[Context definitions](src/server/context.cj) are the reference for extractors.

[`Server`](src/server/server.cj) owns protocol lifecycle, timing and failure
logging; handlers let cancellation escape to that boundary. It retries readonly
work on a fresh snapshot after writes and maps client cancellation to
`REQUEST_CANCELLED`. Preserve the retry/effect qualifications in
[S10](../../docs/design/01-request-slice.md#s10-outbound-request-boundaries).
It also schedules post-write work and push diagnostics, using the router's
translation; handlers do not schedule their own diagnostics.

## Wire and process boundaries

The serving entrypoint passes a logger down from [main](src/main.cj); stdout is
the LSP wire. CLI output is described in Development. Wire types preserve absent
fields through `@Serde[skipNone]`; see
[stdxx](../stdxx/README.md#absent-and-null) and the
[LSP generation procedure](../lsp_codegen/README.md#regeneration). Hand-written
extensions follow [the extension contract](../../docs/lsp-extensions.md).

Stdio uses `platform.StdinStream`, never `std.env.getStdIn()`: buffering can stall
an already-sent request. Blocking FFI must also permit GC; platform-specific
`readv`/`_read` and Windows binary mode belong in `platform`, following
[C5](../../docs/design/03-conventions.md#c5-blocking-foreign-calls),
[K2–K3](../../docs/sdk-issues.md#k2) and
[C17](../../docs/design/03-conventions.md#c17-platform-source-sets).
`FakeTransport` unit tests do not exercise OS stdio; use the relevant
[e2e checks](../../docs/development.md#end-to-end-tests) for changes there.
Heap relaunch and static linking follow Development's
[toolchain constraints](../../docs/development.md#toolchain-constraints).

## Background macros and generated documents

[`cjls.macro_host`](src/macro_host/) integrates the reusable macro host with
settings, snapshots, open documents and `Loop` writes. Edits end the current
round; outputs are applied together. std and workspace macros use separate SDK
servers ([K23](../../docs/sdk-issues.md#k23)). Only production state is given the
worker factory in `main`; test state starts no macro worker and holds no
process-lifetime thread (D141). See
[macro architecture](../../docs/architecture.md#macros-and-protocol-isolation).

[`CacheDirs`](src/server/cache_dir.cj) owns paths under the project's `.cache/cjls`
or the fallback user cache (D106). Ask it for a `CacheDir` instead of constructing
internal paths; this also covers macro builds and expanded-file output.

An [expanded document](src/handlers/expand_macro.cj) is reconstructed from the
snapshot and answered only while it matches the editor's text. Position requests
resolve through `isExpandedDocument` and the expanded view, as hover, definition
and document highlights do. It is not an independent analysis input: snapshots
list no expanded file and it has no diagnostics. The analysis side is described
by [A35](../../docs/design/02-analysis.md#a35-reading-macro-expansions).
