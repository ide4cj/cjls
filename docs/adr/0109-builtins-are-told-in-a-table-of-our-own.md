# ADR-0109: What the language builds in is told in our words, a table of our own

Status: accepted, 2026-10-20

## Context

Hover tells a declaration by its signature and doc comment (#199). What the language builds in has neither: `Int64`, `Unit`, `VArray` are keywords of the grammar, not names; `CPointer`, `CString`, `CFunc` are declared only by `std.core`'s `.cjo` (`ItemKind.BuiltIn`), without sources; `@Frozen`, `@When`, `@Overflow…` are annotations the parser knows by name (`BuiltinAnnotationName`), and `@sourceLine()` a macro of the compiler's. Hover answered nothing on them, or a bare `type CPointer<T>` (#344).

## Decision

- **A table of our own** (`loupe`'s `BuiltinDoc`, in Cangjie in `builtin_docs.cj`): per built-in its name, how it is written and a sentence or three, read at a glance. What cjc does with it is the specification (D15), the language guide where it agrees.
- **No link, no corpus.** A hover does not send its reader to the guide, and the tests do not fetch it: the texts are held by review, as code is.
- **English only.** The client's `locale` is a table more, when asked for.
- **What is told**: the types that are keywords, those of the compiler's own, every annotation the parser takes as the compiler's, the three macros of source location. Not keywords (`spawn`, `unsafe`, …).
- **A macro of the workspace named as one of the compiler's** is the workspace's: the compiler's text is shown only for a call `macroDefinitions` resolves to nothing.

## Consequences

- A type, annotation or macro the compiler adds is a row of the table, an annotation also a name of `contextualKind`; `BuiltinHoverTest` holds the table to those names, a copy of the list.
- The texts follow cjc, not the parser: `@ConstSafe`'s says it is std's alone, which `cjsyntax` does not check.
- The texts are ours to keep true: a cjc that changes a built-in changes its row.
