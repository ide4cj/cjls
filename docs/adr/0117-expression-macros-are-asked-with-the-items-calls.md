# ADR-0117: A workspace macro called in an expression is asked with its file's other calls, keyed by its item, its macro's name and its ordinal, and read where it stands

Status: proposed
Amends ADR-0098: a call in an expression is a call of the file, keyed and asked as one on an item

## Context

- D98 asks the macro server for the calls on items alone (`workspaceCalls`). A call in an expression (`let x = @M(1 + 2)`) is lowered by D59 as its arguments, its type an error, and expand macro does not answer it (#358).
- What cjc does, checked with cjc 1.3.0-alpha.20261014 by macros that print their input:
  - **Inside out, left to right.** In `@B(@M(2) + @InB(3))`, `M` runs, then `InB`, then `B`, whose input is `(2) + 0 + 3`. `InB`'s `assertParentContext("B")` holds, and `B`'s `getChildMessages("M")` reads what `M` set.
  - **A call in a body is nested in its item's calls.** In `@A class X { func f(): Int64 { @M(1) } }`, `M` runs first: its `assertParentContext("A")` holds, `A`'s input has `(1) + 0` in place of the call, and `A` reads `M`'s `setItem`.
  - **What the output parses as depends on where the call stands.** In a block's statement position, it is statements: `@S(nothing)` writing `func local() … let fromS = local() + 1` declares both, and the rest of the block uses them. In any other position, it is an expression: `let x = @S(nothing)` is "expected expression … found keyword 'func'", reported at the call as "the error originates in the macro `S`".
  - **Not only bodies.** A global's initializer, a member variable's, and a parameter's default value are expanded too.
  - **A false `@When` hides its calls.** A local function under one has its calls never sent: cjc's stages are `PARSE`, `CONDITION_COMPILE`, `IMPORT_PACKAGE`, `MACRO_EXPAND` (`CompilerInstance.h`), and semantic analysis comes after them.
  - **A call a macro writes is expanded too.** `@Q(7)` writing `@B(7)` runs `B`.
- cjc resolves a macro's name through the imports alone (`MacroCall::GetAllDeclsForMacroName`: the file's imported declarations, or a package an import names), as `resolveMacroPath` does (A31). A local declaration never shadows one.
- What keys such a call, and when it is asked, elsewhere:
  - **R1** keys it by its `AstId` (`span/src/ast_id.rs`): its kind, a hash of the macro's name and its parent item's id, and an index among those of one hash. A call in a body counts under the item around the block. It is expanded while the body is lowered (`collect_macro_call`), the proc-macro process called inside the query, behind a `Mutex`, and parsed by where the call stands (`ExpandTo::from_call_site`).
  - **R3/R4**: cjc collects every call of a package, those in expressions included (`MacroExpansion::CollectMacros`), and expands them all before any semantic step. R4 compiles the package again on a change, with no cache of what the macros answered (none in `cangjie-language-server/src`).
  - **Swift** keys the call by its AST node (`ExpandMacroExpansionExprRequest`, cached) and expands it while the body is type-checked (`CSApply`), its macros typed, unlike Cangjie's.
- A query cannot wait for the macro server: its answers are an input set off the loop (D98).

## Decision

- **A call of a workspace macro in an expression is a call of its file**, found in the syntax tree under each item and asked with the calls on items (`workspaceCalls`, `macroRequests`). No body is lowered to find them: where a call is and what it calls are read from the tree and the imports, as cjc reads them before any semantic step. A call under a false `@When` is not asked (`ActiveFilter`), nor one inside the tokens of arguments that do not parse (D59).
- **Its key is its item, its macro's name and its ordinal** among the calls of that name in the item, in the order their `@`s are written: R1's. Its item is the innermost item around it, a member or a top-level declaration. A local function is no item, so its calls are its item's. A call added in a body moves only the keys of later calls of the same macro there. `MacroCallKey` says which of the two kinds a key is, so an item's key never names a call in an expression.
- **Order, parents and children are cjc's.** Calls in expressions go innermost first and left to right. Those under an item go before the item's own calls, in the input of which their outputs stand (D98's `MacroInputComposer`). A call's parents are the calls around it, those on its items included. Its children are every call nested in its input (D114).
- **The output is parsed by where the call stands**: as a block's statements in a block's statement position, else as an expression. Anything else is a parse error of the expansion, reported on the call's head as cjc reports it.
- **The body reads the expansion where the call stands.** It lowers the expansion into the same scopes: cjc pastes the tokens, so no name is hygienic. The call's expression is the expansion's, and a statement-position expansion's declarations are in scope after it in the block. A call with no expansion keeps D59's lowering of its arguments.
- **std's macros stay as D59 and #250 read them**: std.unittest's `@Expect` and `@Assert` are no workspace macros, and are asked of no server until std's macros run there (#176's step 4).

## Consequences

- A call in an expression costs a request the first time and after each change to its input, as one on an item does. The 2 232 std.unittest calls in this repository cost none.
- A call a macro writes is not expanded, unlike cjc's `@Q(7)`, as D98 already says of items: a `MacroCallId` is of a source file.
- A body reading an expansion lowers nodes of two files, so its source map says which file each node is in (R1's `InFile<AstPtr>`). That is #369.
- A call on a primary constructor parameter (#357) is also on no item. This key fits it: the parameter's item, the macro's name, its ordinal.
