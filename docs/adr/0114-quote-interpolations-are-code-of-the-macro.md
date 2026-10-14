# ADR-0114: A quote's interpolations are code of the macro, the rest of it tokens

Status: proposed

## Context

- [#195](https://github.com/ide4cj/cjls/issues/195), part of #47: inside a macro's body, `quote(... $(e) ... $x ...)` runs `e` and reads `x` where the macro runs; they are its values (`Tokens`, an `std.ast` node). Since #257 a `quote` was its own `Expr.QuoteExpr` of no children, an `std.ast.Tokens` (D77); D50 lowered it to nothing, so no name in an interpolation resolved, was highlighted by meaning or reached go to definition.
- The parser had `$(e)` as a `QuoteInterpolation` around an `Expr`, `$x` as a lone `DollarIdent` token of the `QuoteExpr`.
- cjc (`src/Parse/ParseQuote.cpp`, `ParseQuoteDollarInterpolation`): `$x` is a `RefExpr` of `x`, its `$` and a raw identifier's backquotes dropped (`isQuoteDollar`); `$(e)` the `Expr` in a `ParenExpr`, both among the quote's `exprs`. The tokens around them are resolved where the macro's output is parsed: Cangjie's macros are not hygienic.

## Decision

- **`$x` is a node in the tree, as cjc makes it one**: `(QuoteInterpolation (RefExpr (NameRef $x)))`, `NameRef` holding either an `Ident` or a `DollarIdent`, and `NameRef.text()`, `identText` the name without `$` and backquotes (A20). Every request reading names (`tokenAt`, `classifyName`, `highlight`, `highlightRelated`) takes a `DollarIdent` as a name (`isIdent`) and reaches it through the `RefExpr` it reads anywhere else. The other way, a token of the `QuoteExpr` mapped to an expression at lowering, would have been a case of its own in each of them.
- **`Expr.QuoteExpr` holds its interpolations** in the order written, `$(e)` lowered as `e` and `$x` as the `PathExpr` of `x`; a `quote` in one is lowered the same way. `exprScopes` walks them, inference infers each with nothing expected, so a name in one resolves and its diagnostics are reported like any code's.
- **The rest of the quote stays tokens**: nothing in it resolves, not even by a guess, nothing in it is reported, an escaped `\$x` included.

## Consequences

- A range of `$x` (a highlight, a related highlight) covers its `$`.
- What cjc checks of an interpolation and the analysis does not yet: its type implementing `ToTokens`, and the expressions it rejects there (`parse_invalid_quote_dollar_expr`: a `return`, a loop, a `throw`, a `try`, a jump).
