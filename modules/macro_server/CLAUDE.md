# `macro_server` — macros run in the SDK's `LSPMacroServer`

What the server is and how it is driven is [D87](../../docs/adr/0087-workspace-macros-run-in-the-sdks-macro-server.md); this module is its protocol, nothing of loupe or LSP.

- **`src/format.cj` is generated** by `modules/fbs_codegen` from `MacroMsgFormat.fbs` as `macro_msg_format.toml` says (`write = true`: the views and the `<Name>Data` writers); never edit it. A new nightly: take `schema/MacroMsgFormat.fbs` of the cangjie_compiler commit it was built from, put that commit in the config, regenerate (`cjpm build && target/release/bin/fbs_codegen modules/macro_server/macro_msg_format.toml`), and read `src/Macro/MacroEvaluationSrv.cpp` and `MacroEvalMsgSerializer.cpp` at that commit for what the server does with each field.
- **The wire** (`frame.cj`): a native `size_t` length, 8 bytes little-endian on every target cjls is built for, then a `MacroMsg`.
- **A call** (`MacroConnection.expand`): one `MacroCall` in a `multiCalls`, its `MacroResult` read, then `exitTask(false)` (no answer), so the diagnostics of a call do not reach the next. cjc reads `id`, `begin`, `end`, `methodName`, `packageName`, `libPath` and every vector without a null check: a call sets them all. `methodName` is `macroCall_{a|c}_<Macro>_<package, '.' as '_'>` (`a`: with attributes).
- **The process** (`startMacroServer`): POSIX only, through `/bin/sh` moving the stdio pipes to fds 3 and 4; Windows throws (#86).
- **Tests** run the SDK's own server (`CANGJIE_HOME`) on std's `@Derive`, whose library ships with the SDK: nothing is built. Token kinds come from `std.ast.getTokenKind`, which a test may import and the package never does (no `std.ast` in runtime packages).
