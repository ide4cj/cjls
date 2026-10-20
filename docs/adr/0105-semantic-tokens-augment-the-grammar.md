# ADR-0105: Semantic tokens augment the editor's grammar, in token types they share

Status: accepted, 2026-10-20
Amends ADR-0019: a client that augments its grammar gets no token the grammar names as well; `this` and `super` are variables; a constructor and a constant are told by modifiers of their own

## Context

- Each editor highlights from a grammar of its own before the server answers and under its tokens: VS Code a TextMate grammar (`ide4cj/cangjie-vscode`), Neovim and Zed tree-sitter's queries (`ide4cj/tree-sitter-cangjie`). A server's token takes the place of the grammar's: Neovim draws it at priority 125 over tree-sitter's 100.
- cjls sent a token for every keyword, comment, literal and operator, which the grammars name as well, and named some of them otherwise: a theme showed one file differently once the server answered, and differently in each editor.
- LSP's `augmentsSyntaxTokens` is a client saying it lays the tokens over a grammar of its own. Neovim 0.12, `vscode-languageclient` and Zed's `combined` mode send `true`; Zed's `full` mode, which drops tree-sitter, `false`. R1 (`to_proto::semantic_tokens`) skips then a bool, char, string or numeric literal, a comment, a keyword, an operator and punctuation, unless a modifier is on it.

## Decision

- **The grammars and the server name a token alike**: one type of LSP's legend per class, the grammar's name for it below. What the tree alone tells, the grammar names as the server would; where it cannot, the grammar leaves the token or guesses, and the server's type is the answer.

| LSP type (modifier) | tree-sitter | TextMate |
|---|---|---|
| `keyword` | `@keyword`, `@keyword.*`, `@constant.builtin` (`true`, `false`) | `keyword.*`, `storage.*`, `constant.language` |
| `comment` | `@comment` | `comment.*` |
| `string` | `@string`, `@string.escape`, `@character` | `string.*`, `constant.character.escape` |
| `number` | `@number`, `@number.float` | `constant.numeric.*` |
| `operator` | `@operator` | `keyword.operator` |
| — (no token) | `@punctuation.*`, `@markup.raw`, `()` | `punctuation.*` |
| `type`, `class`, `struct`, `interface`, `enum`, `typeParameter` | `@type`, `@type.builtin`, `@type.definition` | `entity.name.type`, `support.type.primitive` |
| `function` | `@function`, `@function.call` | `entity.name.function` |
| `method` (a member function) | `@function.method`, `@function.method.call` | `entity.name.function` |
| `method` (`constructor`): an `init`, a primary constructor's name | `@constructor` | `entity.name.function` |
| `macro` | `@function.macro` | `entity.name.function.macro` |
| `decorator` | — (an annotation is a macro call to the tree) | — |
| `property` (a member variable, a `prop`, a primary constructor's `let`/`var` parameter used as a member) | `@variable.member` | `variable.other.property` |
| `variable` | `@variable` | `variable.other` |
| `variable` (`readonly`, `constant`): a `const` | `@constant` | `variable.other.constant` |
| `variable` (`defaultLibrary`): `this`, `super` | `@variable.builtin` | `variable.language` |
| `parameter` (a primary constructor's `let`/`var` parameter where it is declared too) | `@variable.parameter` | `variable.parameter` |
| `enumMember` | `@constant` | `variable.other.enummember` |
| `namespace` | `@module` | — |

- **Where the tree cannot tell**, the server's type stands over the grammar's: a call of a type or an enum constructor (`Point(1)`, `Some(1)`), a lone name in a `case`, a call of a variable holding a function, an annotation against a macro call, a name at its use (D72).
- **A client that augments its grammar** gets no `keyword`, `comment`, `string`, `number` or `operator` token without a modifier; one with a modifier (a documentation comment, `defaultLibrary`) it gets. A client that does not, as before (D19).
- **`this` and `super`** are a `variable` with `defaultLibrary`, what the language declares, rather than a `keyword`.
- **A constructor and a `const`** are a `method` and a `readonly` `variable`, as LSP has them, told by modifiers of their own, `constructor` and `constant`, which the grammars name them by; the legend appends the two after `mutable` (D72). A modifier a client does not know it drops, and the token keeps its type's color; a type it does not know would lose the token's color whole, which is why R1 has a fallback without its own types. `readonly` alone would not tell a `const` from a `let`.
- **A primary constructor's `let` or `var` parameter** is a `parameter` where it is declared, as the grammars have it, and a `property` where it is used as a member.

## Consequences

- An editor's highlighting stays as its grammar drew it once the server answers, but for names; a grammar's change of a class is a change of this table.
- Each client checks its grammar against the server on a sample file, the divergences the tree cannot tell listed (`ide4cj/cangjie-zed`'s `test/`).
- A theme's colors for a type differ between editors; the table holds the types, not the colors. Neovim links no modifier by default: `cangjie.nvim` links `variable` and `type` with `defaultLibrary` to `@variable.builtin` and `@type.builtin`, `typeParameter` to `@type`, `macro` to `@function.macro`, `method` with `constructor` to `@constructor`, `variable` with `constant` to `@constant`; `cangjie-vscode` maps the same two modifiers to `variable.language` and `support.type.primitive`, where VS Code would take `support.*`, and declares the modifiers `constructor` and `constant` (`semanticTokenModifiers`) with their scopes.
