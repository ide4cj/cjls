# ADR-0164: hard keywords keep the grammar's color, enum cases share the server's enumMember type, and clients laying tokens over their grammar get no interpolation delimiters

Status: proposed

Amends ADR-0105: `init`, `this` and `super` keep their keywords, enum cases are the grammar's own capture, and interpolation delimiters leave the augmented set (A38, D148)

## Context

- ADR-0105 named a plain `init` a `method` with the `constructor` modifier and put the grammar's `@constructor` under it; the grammar keeps `init` a hard keyword (`@keyword.function`, as `~init`'s keyword too), so on a client that augments its grammar the keyword turned into a constructor the moment the file had a package behind it.
- ADR-0105 made `this` and `super` a `variable` with `defaultLibrary` — the value a body is on, what the language declares — so the keyword the grammar paints `@keyword` was overridden wherever the server answered.
- ADR-0105 had enum cases in the grammar as `@constant`, one capture shared with `const` declarations; a theme coloring the server's `enumMember` tokens their own way — as catppuccin does — showed the same file's enum cases two colors.
- A38 (D148) kept interpolation delimiters in the augmented set as operators, for visibility without a grammar; a grammar of Neovim's or Zed's scopes them itself (`interp_open` and `interp_close` as `@punctuation.special`), and the server's operator took their place once it answered.

## Decision

- **`init` and `~init` are hard keywords, the tree's tag stands**: the server tags neither, and a client that augments its grammar gets no token of them; a grammar-less client gets the `keyword` token. The only `constructor` modifier left is the primary constructor's name, which the grammar captures `@constructor` as well.
- **`this` and `super` are keywords**: they are hard keywords of the language, the tree paints them `@keyword`, and the server tags neither on a client that augments its grammar; a grammar-less client gets the `keyword` token. The `variable` with `defaultLibrary` is left with nothing to say.
- **Enum cases are the grammar's `@enum_member`**, a capture of their own, apart from `const` (`@constant`); `cangjie.nvim` resolves the capture to the group the server's `enumMember` tokens take, so both systems color a case with one group whatever the theme makes of it. The server's `enumMember` type is unchanged.
- **A client that augments its grammar gets no interpolation delimiter**: the grammar scopes `${` and `}` itself, as it scopes punctuation; a client without a grammar keeps them as operators (A38).

| Token | tree-sitter (amending ADR-0105's table) |
|---|---|
| `method` (`constructor`) | `@constructor` — a primary constructor's name only; a plain `init` and `~init` are `@keyword.function` |
| `keyword` (`this`, `super`) | `@keyword`, dropped on an augmenting client |
| `enumMember` | `@enum_member`, resolved by `cangjie.nvim` to the group the server's `enumMember` tokens take |
| — (no token, augmenting) | `interp_open`/`interp_close` as `@punctuation.special` |

## Consequences

- A client checks the color of an `init`, a `this`, a `super`, an enum case and a `${` on its sample file against its grammar alone: the server agrees by sending nothing or the shared group.
- `cangjie.nvim` links the grammar's `enumMember` capture and pins the server's token types to the grammar's groups; a client without that glue keeps ADR-0105's fallbacks. Its ADR-0105 link for a `variable` with `defaultLibrary` stays, for a server older than this decision.
- Grammar-less clients see an `init` as a keyword and interpolation delimiters as operators, as before.
