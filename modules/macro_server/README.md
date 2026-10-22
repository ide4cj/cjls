# macro_server

Protocol adapter for the SDK's `LSPMacroServer`, independent of loupe and LSP.
[D87](../../docs/adr/0087-workspace-macros-run-in-the-sdks-macro-server.md)
explains process isolation; the [macro host](../macro_host/README.md) owns build
and expansion orchestration.

## Updating the SDK protocol

[format.cj](src/format.cj) is generated from
[MacroMsgFormat.fbs](MacroMsgFormat.fbs) through
[macro_msg_format.toml](macro_msg_format.toml) (`write = true` generates views
and writers). On a nightly update, copy `schema/MacroMsgFormat.fbs` from the
compiler commit named in its release notes, record that commit in the config,
and inspect that commit's `src/Macro/MacroEvaluationSrv.cpp` and
`MacroEvalMsgSerializer.cpp` for how fields are consumed. Build the generator
before changing generated output, then run from the repository root:

```bash
cjpm build
target/release/bin/fbs_codegen modules/macro_server/macro_msg_format.toml
```

Follow [generator verification](../fbs_codegen/README.md#regeneration-and-verification).
If SDK token kinds change, update `KINDS` in [token_numbers.cj](src/token_numbers.cj)
from `include/cangjie/Lex/Tokens.inc`; `TokenNumbersTest` checks this fallback
against the selected SDK. Prefer the SDK's own file when available. The built-in
table supports archives without it; 1.0 uses its first 156 kinds plus `ILLEGAL`,
with newer contextual keywords sent as identifiers (D95, D104).

## Wire and process constraints

Frames carry a native `size_t` length, 8 bytes little-endian on supported targets,
then a `MacroMsg`. Calls are serial: one `MacroCall` in `multiCalls`, one
`MacroResult`, then `exitTask(false)` without an answer to clear call diagnostics.
cjc reads `id`, `begin`, `end`, `methodName`, `packageName`, `libPath` and vectors
without null checks, so calls populate all of them. Symbols are named
`macroCall_{a|c}_<Macro>_<package with dots replaced by underscores>`; `a` denotes
attribute calls. See [connection.cj](src/connection.cj).

[process.cj](src/process.cj) supplies SDK-specific arguments and library paths
to `platform.startPiped`. The arguments identify read/write pipe ends, serial
mode (`0`), cjc and, when needed, the parent process to watch. These are separate
pipes from stdin/stdout: POSIX uses `/bin/sh` to move them to fds 3/4; Windows
inherits only their handles and stderr through `CreateProcessW`, suspended until
assigned to a kill-on-close job (D91, D101). See [platform](../platform/README.md).

Search the selected SDK's runtime directory, then its `tools/lib`, before
inherited library paths, matching `envsetup`. Another SDK's inherited library
path can override `RUNPATH` and load the wrong `libcangjie-lsp`; this was observed
with 1.0.5 in [#310](https://github.com/ide4cj/cjls/issues/310).
The former notes record the same arguments, descriptors and protocol schema
working with 1.0.5, 1.2.0 and the then-pinned nightly; this is historical
compatibility evidence, not verification of future SDKs.

## Tokens and verification

Tokens must match cjc's lexer, including whole strings, `>=>` and `!in`.
[MacroTokenWriter](src/macro_tokens.cj) records the differences from cjsyntax;
`std.ast.cangjieLex` is the test oracle when compiler source and behavior differ.
Printing an expansion preserves token kinds and values, with ranges in printed
text alongside server positions, except for generated identifiers: cjc re-lexes
their values in `ProcessCombinedToken`, so `Token(IDENTIFIER, "Int8")` becomes the
primitive type keyword. Print the value unchanged; only backquotes already in it
keep it an identifier. Literal quoting is checked by re-lexing; spaces are omitted
only for pairs known not to glue.

Tests need `CANGJIE_HOME`: they run the SDK server on its shipped `@Derive`
library without building a workspace macro. Test support selects a runtime with
the host architecture and shared-library suffix, so foreign runtimes bundled in
the SDK cannot affect selection. Lexer comparisons also need the std
corpus in `.corpora/cangjie_runtime`; fetch it as described in
[Development](../../docs/development.md#focused-and-full-cangjie-tests).
Only tests import `std.ast`; runtime packages must keep it out of their dependency
graph ([toolchain constraints](../../docs/development.md#toolchain-constraints)).
