# ADR-0079: The settings are one typed model whose schema the server prints, read as R1 reads them

Status: proposed

## Context

- Three settings were read by hand from `initializationOptions` (`linkedProjects`, D33; `cangjieHome`, D40; `cangjieSrc`, D65), with no schema, and never again after `initialize`. D32 makes the server the source of its settings' JSON Schema, for the clients to generate theirs from (#107).
- LSP leaves open where a client's settings come from: `initializationOptions` once, `workspace/configuration` (pull) by section, `didChangeConfiguration` (push), whose params are anything (VS Code sends `null`; LSP's issue 676 says to ignore them and pull).
- R1 takes `initializationOptions` as its first settings; on `didChangeConfiguration` it ignores the params and pulls the section `rust-analyzer`; an answer of `null` or `{}` leaves the settings as they are, any other object replaces them whole (`Config::apply_change`, checked at its master of 2026-10).

## Decision

- **One `Settings` type** (`cjls.server`), each setting declared once with its key, schema, default and reader; `cjls --config-schema` prints the JSON Schema (draft-07, which VS Code reads) built from those declarations. A setting's description lives there, not in `docs/lsp-extensions.md`.
- **The section is `cjls`**, the prefix the VS Code client already gives its own settings; a client passes as `initializationOptions` what that section holds, as R1's clients do.
- **Read as R1 reads them**: `initializationOptions` first; then, from a client that answers `workspace/configuration`, the section pulled on `didChangeConfiguration`, its params ignored; `null` or `{}` keeps the settings, any other object replaces them whole, a setting it leaves out at its default. A client that cannot be asked pushes them under `settings.cjls`.
- **Beyond R1**: the section is also pulled once at `initialized`, after the load began with `initializationOptions` (a load is not held on an answer that may never come; a different answer loads again), and `didChangeConfiguration` is registered for the section when the client takes a registration, without which VS Code sends none. Only the last pull's answer is taken.
- **A value not of its schema is at its default**, an item of a list left out alone, and the user told by `window/showMessage` besides the log, as R1 tells config errors. Keys the server does not know are left alone: a client's section holds its own settings too (`cjls.server.path`).

## Consequences

- A new setting is a declaration in `server/settings.cj`, a field of `Settings`, and what reads it; the clients regenerate their settings from `cjls --config-schema` (D32), the descriptions included.
- Every setting today says where the project or the SDK is found, so any change loads the workspace again; a setting that does not will have to say which work it redoes.
- Settings per folder (`scopeUri`) are not asked for: nothing differs per folder yet.
