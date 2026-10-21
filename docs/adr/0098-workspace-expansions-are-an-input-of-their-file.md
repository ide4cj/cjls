# ADR-0098: The macro server's answers are an input of the source file, their origins relative to the top-level item

Status: accepted, 2026-10-20

## Context

- D87 runs the workspace's macros in the SDK's `LSPMacroServer`, off the loop (#176's step 3). Its answers have to reach the analysis as something it can read, and the analysis has to say what to ask. Until the server answers, and whenever it cannot, the last expansion that succeeded stands (#175).
- calca has no input keyed by a value. A row is created and held by its id, and `MacroCallId` is interned, so a collected one would leave a dangling key in an input (D18). `ItemId` is a plain value that an edit elsewhere in the file leaves alone (D34). But it belongs to `loupe.hir`, above `loupe.db`, where the inputs are.
- calca stamps each field of an input in a column of its own. Setting one field runs again only what read that field.
- How cjc nests calls, checked with cjc 1.3.0-alpha.20261002 by macros that print their input:
  - `@A @B class X {}`: `B` runs first, and `A`'s input is `B`'s output, without `@B`.
  - `@A class Y { @I func f() {} }`: `I` runs first. `A`'s input is `Y` with `I`'s output where `@I func f() {}` was. `A`'s `getChildMessages("I")` reads what `I` set.
  - A token a `quote` makes carries the position of its call's `@`.
- A token's position on the wire is a line and a column. Only cjls cuts tokens as cjc does (`macroTokens`, D95), and `loupe` knows nothing of `macro_server` (D5, 00-layers).

## Decision

- **The answers are a field of `SourceFile`, `macroOutputs`**, keyed by the item's `ItemId` as text and the call's index (`MacroCallKey`, which `loupe.db` can name). Setting it runs again the readers of the outputs, never those of the text. A `MacroOutput` keeps the fingerprint of the request it answered, the last expansion that succeeded and the items it set, and the diagnostics of the last run. A run that failed keeps the expansion. `@CalcaInput` takes a field with an initializer for it: a named parameter of the constructor, after the others.
- **`loupe` writes the requests** (`macroRequests`): the macro, the text of its attribute and of its input, the names of the calls around it, what the calls nested in it set, and a fingerprint of all of it. A request is current when the output stored for its call answered that fingerprint. cjls cuts the tokens and sends the requests that are not current (`pendingMacroRequests`).
- **Calls go innermost first, as cjc's do** (`workspaceCalls`): under a top-level item, its members' calls, then its own. A call's input is the text of the source, with each nested call of a workspace macro replaced by that call's output. A call nested in its input with no expansion yet keeps it from being asked. A call of std's macro nested in it stays as written until std's macros run in the server too (#176's step 4).
- **The outermost call on a top-level item is the one read.** Its output replaces the item, as cjc's does, and is the file `ItemFile.Expansion` of #175. Nothing under that item is unread any more (`hasUnreadMacros`). An inner call is expanded only into the input of the calls around it.
- **Text says where it comes from by spans** (`MappedText`). A span comes either from the source, as a range relative to the start of the top-level item (its outermost call's `@`), or from the call, for what its macro wrote. An edit outside the item leaves the spans right. One inside it makes the request new anyway. cjls maps a position the server answers back to a range of the input it sent, and that range to its span. A span from a nested call's macro becomes the head of that call (`@` to the end of its attribute) in the input of the call around it.

## Consequences

- A call on a member whose type has no workspace macro is asked, but its output is read by nothing. In cjc, it replaces the member in its type. `hasUnreadMacros` still says so.
- A call of a workspace macro inside the output of another is not expanded, since `MacroCallId` is of a source file.
- Where `parentNames` and `childMsges` go deeper than one level, cjc's order is not checked. The requests give the calls around, outermost first, and the outputs of the nested calls their input was made of.
- Every request of a file is written again when one of its outputs is set. Only those whose fingerprint changed go out again.
