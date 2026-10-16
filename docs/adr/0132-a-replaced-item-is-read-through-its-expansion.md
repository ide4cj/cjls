# ADR-0132: An item a macro's output replaces is read through that output alone; its source maps to it by spans

Status: proposed
Amends ADR-0098: a replaced item's source is a view of its expansion, mapped by the spans, never read for itself
Amends ADR-0123: the type errors in the bodies of an output read are reported, where their spans put them

## Context

- A macro may do anything to the item it replaces: rename, drop or add members, change a signature, wrap a body, write declarations beside it. D98 already makes the output of the outermost call the item (`ItemFile.Expansion`), each piece of its text `FromSource` with a range or `FromCall`.
- Two bugs of one kind came from reading a replaced item two ways at once:
  - The hover of a type (#430) looked for the `extend`s of the expansions of a *source* declaration, while the name resolved into the server's output.
  - In #431, a source body of a replaced item is inferred: `?E` in its signature finds the output's `E`, the constructors and `this` through `parentOf` the source's. Two `DeclTy`s, both printed `E`.
- What reads an expansion today:
  - `packageExtends` and the package's scope go through its files, expansions among them;
  - `expandedDeclOf` maps a source *declaration name* to the output's declaration, by its range, and hover alone uses it;
  - `bodyWithSourceMap` lowers bodies of source files only, so nothing in an output's bodies is typed or reported (D118's stub bodies rely on it).
- cjls's own expansions of std (#175) differ: `@Derive`'s adds `extend`s after the item and replaces nothing, `@Test`'s replaces its class. The fixtures of std's macros read these, never a server's output, which hid both bugs; `DiagnosticsGateTest` runs without the server too.
- R1 reads a token in a macro call by descending into the expansion (`descend_into_macros`: the tokens made from it) and maps what it finds back (`original_range`). Nothing in a feature knows what a macro did.

## Decision

- **A replaced item is read through its output alone.** Every query about it — signature, members, supertypes, bodies — takes the output's declarations. Its source is never lowered nor inferred for itself (`bodiesOf` leaves it out, #431).
- **A source position maps to the tokens copied from it**: those of the output under a `FromSource` span covering it, none, one or several. A request at that position (hover, go to definition, highlight, references, the scope completion reads) answers for them, merged. `expandedDeclOf` becomes the case of a declaration's name (#432).
- **What is found in an output maps back by its span**: in text copied from the source, to that range; in text the macro wrote, a diagnostic to the call's head, as `macroDiagnostics` puts the macro's own, and navigation into the expansion's file (D103).
- **No feature asks what a macro added.** It reads the general queries, which see an output as a file: a type's supertypes are those of its declaration and of the `extend`s of the package (`packageExtends`), whoever wrote them (#433).
- **An output older than the text maps a position only where the source under its span is still the text it copied.** Elsewhere in the item being edited there is no answer until the server answers again (D104's deadline).
- **cjls's own expansions of std stay** (#175, D123): they stand until the server answers, and whenever it cannot. `@Derive`'s adds and replaces nothing, so its item is read as the source; `@Test`'s replaces and is read as this decision says.
- **A fixture of a std macro is checked in both readings**, cjls's own and a server's answer, and the diagnostics gate also infers this repository as the server expands it (#434).

Rejected: reading a source body of a replaced item with its type around mapped to the output's (#431's (b)). Narrower, but two readings stay, and each new feature has to know it. Knowing per macro what it adds (#430's `addedSupersOf`): it covers one effect of one macro.

## Consequences

- Bodies of an output are lowered and inferred, those the server wrote included: the 306 `@Derive` of this repository add their `==`, `hashCode` and `toString` to the inference of a cold start. cjls's own stub bodies (D118) stay empty.
- A token the macro dropped has no answer. Neither does one inside an item being edited, until its output is current.
- Text the macro wrote without spans, its names made from strings among it, is reached only through the expansion's file.
