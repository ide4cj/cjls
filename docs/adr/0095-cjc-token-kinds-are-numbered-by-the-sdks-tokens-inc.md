# ADR-0095: cjc's token kinds are numbered by the SDK's own Tokens.inc

Status: proposed
Amends ADR-0087: no table is generated, and no SDK version is required

## Context

- D87 numbers the tokens sent to `LSPMacroServer` by a table generated from `Tokens.inc` at the pinned nightly. It left open whether expansion needs that exact `cjc --version` or any SDK whose numbering the table matches. cjls had no way to read an SDK's numbering without `std.ast`, which a runtime package never imports.
- Every SDK ships `include/cangjie/Lex/Tokens.inc`, the file cjc's `TokenKind` is built from. Checked in the 1.3.0-alpha.20261002 archives for Linux x64, macOS arm64 and Windows x64: it is byte for byte the file at `cangjie_compiler` 514a5a209e42, and unchanged since 20260716. A kind's number is its line's place among the `TOKEN` and `EXPERIMENTAL_TOKEN` lines (`Token.h`).
- `std.ast` numbers the kinds the same way and names them alike. The one difference is `AT_EXCL`, which `std.ast` calls `AT_EXCLAMATION`.
- cjsyntax's tokens are not cjc's one for one. cjc's lexer makes a string one token of what its quotes enclose, and drops a multi-line string's first line break. It glues `>>`, `>=`, `>>=` and `??` itself, but leaves a `>=`'s `=` to a `=>` that no `=` or `>` follows (`>=>` is `>` `=>`; `>=>=` is `>=` `>=`). It glues `!in` only before a space or a line break. A macro gets no comment, and one `NL` per line break. Columns count bytes. This was read through `std.ast.cangjieLex`, where the sources at that commit disagree on `>=>`.

## Decision

- **The numbers are read from the SDK the server comes with** (`MacroServerPaths.tokensInc`, `TokenNumbers.read`), by the kind's name. No table is generated, and nothing depends on `cjc --version`. If the file is missing, or lacks a kind cjls sends, nothing is sent to that SDK's server, and an item under a macro stays opaque (#175).
- **`macro_server` turns cjsyntax's tokens into cjc's** (`macroTokens`), so `macro_server` depends on `cjsyntax`.
- **Both are held to the SDK the tests run on**: the numbers to `std.ast.getTokenKind`, the tokens to `cangjieLex`. That covers the cases above, every file of this repository, and std's sources (D65).

## Consequences

- A nightly that renumbers the kinds needs nothing from cjls. One that renames or removes a kind cjls sends turns expansion off, which shows in `TokenNumbersTest` when `.cangjie-version` moves. One that changes how cjc cuts tokens shows in `MacroTokensTest`.
- D87's open question about the SDK's version is closed.
