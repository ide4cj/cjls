# ADR-0105: Semantic tokens augment the editor's grammar, in token types they share

Status: proposed
Amends ADR-0019: a client that augments its grammar gets no token the grammar names as well; `this` and `super` are variables

## Context

- Each editor highlights from a grammar of its own before the server answers and under its tokens: VS Code a TextMate grammar (`ide4cj/cangjie-vscode`), Neovim and Zed tree-sitter's queries (`ide4cj/tree-sitter-cangjie`). A server's token takes the place of the grammar's: Neovim draws it at priority 125 over tree-sitter's 100.
- cjls sent a token for every keyword, comment, literal and operator, which the grammars name as well, and named some of them otherwise: a theme showed one file differently once the server answered, and differently in each editor.
- LSP's `augmentsSyntaxTokens` is a client saying it lays the tokens over a grammar of its own. Neovim 0.12, `vscode-languageclient` and Zed's `combined` mode send `true`; Zed's `full` mode, which drops tree-sitter, `false`. R1 (`to_proto::semantic_tokens`) skips then a bool, char, string or numeric literal, a comment, a keyword, an operator and punctuation, unless a modifier is on it.

## Decision

- **The grammars and the server name a token alike**: one type of LSP's legend per class, the grammar's name for it below. What the tree alone tells, the grammar names as the server would; where it cannot, the grammar leaves the token or guesses, and the server's type is the answer.

| LSP type (modifier) | tree-sitter | TextMate |
|---|---|---|
| `keyword` | `@keyword`, `@constant.builtin` (`true`, `false`) | `keyword.*`, `storage.*`, `constant.language` |
| `comment` | `@comment` | `comment.*` |
| `string` | `@string`, `@string.escape`, `@character` | `string.*`, `constant.character.escape` |
| `number` | `@number` | `constant.numeric.*` |
| `operator` | `@operator` | `keyword.operator` |
| — (no token) | `@punctuation.*`, `@markup.raw`, `()` | `punctuation.*` |
| `type`, `class`, `struct`, `interface`, `enum`, `typeParameter` | `@type`, `@type.builtin` | `entity.name.type`, `support.type.primitive` |
| `function` | `@function` | `entity.name.function` |
| `method` (a member function, a constructor) | `@function.method` | `entity.name.function` |
| `macro` | `@function.macro` | `entity.name.function.macro` |
| `decorator` | — (an annotation is a macro call to the tree) | — |
| `property` (a member variable, a `let`/`var` parameter of a primary constructor, a `prop`) | `@property` | `variable.other.property` |
| `variable` | `@variable` | `variable.other`; `variable.other.constant` for `const` (`readonly`) |
| `variable` (`defaultLibrary`): `this`, `super` | `@variable.builtin` | `variable.language` |
| `parameter` | `@parameter` | `variable.parameter` |
| `enumMember` | `@constant` | `variable.other.enummember` |
| `namespace` | `@module` | — |

- **Where the tree cannot tell**, the server's type stands over the grammar's: a call of a type or an enum constructor (`Point(1)`, `Some(1)`), a lone name in a `case`, a call of a variable holding a function, an annotation against a macro call, a name at its use (D72).
- **A client that augments its grammar** gets no `keyword`, `comment`, `string`, `number` or `operator` token without a modifier; one with a modifier (a documentation comment, `defaultLibrary`) it gets. A client that does not, as before (D19).
- **`this` and `super`** are a `variable` with `defaultLibrary`, what the language declares, rather than a `keyword`.

## Consequences

- An editor's highlighting stays as its grammar drew it once the server answers, but for names; a grammar's change of a class is a change of this table.
- Each client checks its grammar against the server on a sample file, the divergences the tree cannot tell listed (`ide4cj/cangjie-zed`'s `test/`).
- A theme's colors for a type differ between editors; the table holds the types, not the colors. Neovim links no modifier by default: `cangjie.nvim` links `variable` and `type` with `defaultLibrary` to `@variable.builtin` and `@type.builtin`, `typeParameter` to `@type`, `macro` to `@function.macro`; `cangjie-vscode` maps the same two modifiers to `variable.language` and `support.type.primitive`, where VS Code would take `support.*`.
