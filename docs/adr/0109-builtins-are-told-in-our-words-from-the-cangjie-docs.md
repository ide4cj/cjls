# ADR-0109: What the language builds in is told in our words from the Cangjie docs, linked at a pinned commit

Status: proposed

## Context

Hover tells a declaration by its signature and doc comment (#199). What the language builds in has neither: `Int64`, `Unit`, `VArray` are keywords of the grammar, not names; `CPointer`, `CString`, `CFunc` are declared only by `std.core`'s `.cjo` (`ItemKind.BuiltIn`), without sources; `@Frozen`, `@When`, `@Overflow…` are annotations the parser knows by name (`BuiltinAnnotationName`), and `@sourceLine()` a macro of the compiler's. Hover answered nothing on them, or a bare `type CPointer<T>` (#344).

The only text of them is the language guide, [cangjie_docs](https://github.com/cangjielanguage/cangjie_docs) (CC BY 4.0): no spec, no API reference of std; one page per family of types (the integers share one heading), one heading per annotation in `builtin_compilation_flags.md`, some only in prose (the Java and Objective-C mirrors). The Chinese guide has the same files, other headings.

## Decision

- **Our words, a sentence or three, and a link to the section they come from** (`loupe`'s `BuiltinDoc`, a table in Cangjie in `builtin_docs.cj`), not the guide's paragraphs: a hover is read at a glance, and the guide's sections run to pages. The link is `HoverItem.link`, which `cjls` writes after the text (`[Cangjie docs](…)` in Markdown); CC BY's attribution is that link.
- **The link names the commit the texts were written from** (`CANGJIE_DOCS_COMMIT`), and `tests/corpora/fetch.py` fetches the guide at it (D26): `BuiltinDocsTest` holds every link to a page and a heading of it, GitHub's anchor of the heading, and the fetched commit to the one linked. Moving the pin is reading what changed under it; a heading renamed fails there, not in an editor.
- **English only.** The client's `locale` and the Chinese guide (`source_zh_cn`) are a table more, when asked for.
- **What is told**: the types that are keywords, those of the compiler's own, the annotations the guide tells of (not `@Intrinsic`, `@ConstSafe`, `@NonProduct`, which are std's), the three macros of source location. Not keywords (`spawn`, `unsafe`, …): a keyword's hover would be a link to a chapter.
- **A macro of the workspace named as one of the compiler's** is the workspace's: the compiler's text is shown only for a call `macroDefinitions` resolves to nothing.

## Consequences

- A type, annotation or macro the compiler adds is a row of the table; one the parser learns (`contextualKind`) is hovered only once it has one.
- The texts are ours to keep true: a cjc that changes a built-in changes its row, which the guide at the pin no longer checks.
