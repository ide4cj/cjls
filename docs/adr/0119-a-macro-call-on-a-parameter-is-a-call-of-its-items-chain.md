# ADR-0119: A macro call on a parameter is a macro call of the item whose parameter list holds it, indexed after the item's own

Status: proposed
Amends ADR-0098: a `MacroCallId` is an item and an index among the calls on it; ADR-0114: a call on a primary constructor parameter is sent as written

## Context

- cjc takes a macro call on a parameter of a primary constructor (`@Serde[rename: "textDocument"] let document!: ?String = None`) and expands it first, inside out: the call on the type is given the parameter as the inner macro wrote it, and what the inner call `setItem`s among its children (#357).
- D98 keys a call by its item and its index among the calls on that item (`MacroCallKey`, which outlives a revision), and D114 sends a call on a parameter as written, since a parameter is no item: `@DeriveExt` then reads a `MacroExpandDecl` where it expects a parameter and reports every such type, in this repository `stdxx`'s tests and every `lsp_types` struct with a `@Serde` on a field.
- A parameter stays no item: a `let` of a primary constructor is a member resolved through its constructor (`MemberParam`, N69), and the item tree names declarations, not what they take. A `MacroCallId` with a field for the parameter would change every key the macro server's answers are stored by.
- cjsyntax parses the call as a `MacroExpandDecl` around the `Param`, in the `ParamList` of the declaration (`InParams`), so the calls on an item's parameters are found from its node alone.

## Decision

- **The macro calls of an item are chains** (`macroCallChainsOf`): first those on the item, outermost first, as before; then, for each parameter of the item's own parameter lists that has any, those on the parameter, outermost first, in the parameters' order. A `MacroCallId`'s index counts through them, so a `MacroCallKey` is unchanged, and `macroCallAt`, `macroCallChainAt` and `macroCallIndexOf` go between an index and a call. `Item.paramMacros` holds the parameters' chains by name as `Item.macros` holds the item's, and `macrosOf` resolves both in that order.
- **A call on a parameter is asked of the macro server as any other** (`workspaceCalls`): under its item's own calls' order, the parameters' chains before the item's chain, innermost first; read by nothing of its own. Its input is the parameter as written; its output replaces the parameter in the input of the calls around it, those on the item and then on the type (`MacroInputComposer.declaration`), and it is a child of each (D114). Its parents are the macros on the type, on the item, and the outer ones on the parameter.
- **A std macro on a parameter stays as written**: `@Derive` is expanded only on an item (`derivedBy`), and `stdCallsOf` reads an item's own chain alone.
- **`macroCallAt` on the head of a call on a parameter** is the call read on its type, as for a call on a member; `declarationUnder` gives the parameter.

## Consequences

- The item tree changes for a file with a macro call on a parameter (`Item.paramMacros`), and so does what reads it: a type whose constructor has one has unread macros until the call on the type is answered, as a member with a call has.
- A macro call on a parameter of a function or an `init`, which cjc also parses, is keyed the same way; what a macro adds there is not read.
- A `MacroCallId` of a chain's index past the item's own calls names a parameter's call, which nothing but this ADR's functions should take apart.
