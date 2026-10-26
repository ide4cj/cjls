# ADR-0149: Completion groups overloads by the name it inserts and resolves their signatures together

Status: accepted, 2026-10-26

## Context

Completion currently lists every overload as a separate item with the same label
and the same name edit (D111). For names such as `print`, these identical rows
crowd out other names. R4 and R9 distinguish separate rows by their signatures;
clangd (R8) also supports bundling overloads. Choosing a name need not choose its
signature, especially while cjls inserts only that name.

## Decision

- After ranking and deduplication, `loupe` groups function and constructor
  declarations with the same label and completion kind. The group's position and
  relevance are the first member's; each declaration keeps its receiver type for
  generic substitution. Locals, properties and types remain separate kinds.
- A group retains every declaration, rather than dropping all but one by name.
  Its size needs no signature query. Signature rendering remains lazy, on
  `completionItem/resolve`, which renders every member and its documentation.
- The LSP item keeps the name as its label and edit. An overload count is shown
  through label details when supported and through `detail` for other clients.
  Group documentation contains all signatures and doc comments in the client's
  negotiated format; a singleton retains its existing presentation. Resolve leaves
  a stale item unchanged if its overload count changed: label details belong to
  the original list and cannot be replaced by resolve for every client.

## Consequences

This replaces D111's per-declaration presentation, preserving its ranking,
client-side matching and lazy-detail policy. Grouping is valid while all members
insert the same name. Future auto-imports or argument snippets must distinguish
different edits before grouping. Signature help (#204) remains separate work;
overloads are discoverable in completion documentation in the meantime.
