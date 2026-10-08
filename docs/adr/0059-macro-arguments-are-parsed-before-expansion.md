# ADR-0059: An expression macro's arguments are parsed as an argument list when they parse as one, before any expansion

Status: accepted, 2026-10-08
Amends ADR-0050: a macro call's arguments lowered when they parse

## Context

- Until expansion (#176), `@M(…)`'s arguments are tokens (`MacroArgs = '(' AnyToken* ')'`), and D50 lowers a macro call in a body to nothing: no name inside `@Expect(…)`, `@Assert(…)`, `@AssertThrows(…)` resolved or reached by go to definition (#174). In this repository that is 2 232 calls, most of every test body.
- cjc (R3) keeps a macro call's arguments as tokens (`ParseMacroCallArgsWithParen`, a `vector<Token>`), runs the macro, and parses its output; the tokens it passes through keep their positions, and the LSP maps them back (`origin2newPosMap`). A call it cannot expand is left as it is: it never parses the arguments without the macro. Nor does rust-analyzer (R1): a macro call's input is a token tree until it is expanded.
- std.unittest's `@Expect` and `@Assert` parse their input themselves as comma-separated expressions (`parseCommaSeparatedExpressions`), `delta: d` among them; `@AssertThrows` and `@ExpectThrows` take an expression or a block `{ … }` with no `=>`, which no expression of the language is. `@Types(dsl)` and a user's macros may take what is no code at all.

## Decision

- **In the parser**: `MacroArgs` holds an `ArgList` when the tokens between the parentheses parse as one with no error, and the tokens otherwise, as before (`MacroArgs = ArgList | '(' AnyToken* ')'`); the attempt is rewound on the first error, so it adds none. One tree: highlighting, the source map and go to definition see the arguments as any call's, and the tokens a macro is given are still all there. A second parse of the tokens at lowering, a tree of its own, was the other way: a file id, a map of positions and a highlighting of its own, for what one tree gives.
- **An argument `{ … }` needs no `=>`**, as a trailing lambda: `@AssertThrows({ … })`'s block is a lambda of no parameters. A departure from R3's grammar, inside a macro's arguments only.
- **Code is what parses**: no list of macros known to take expressions. A macro whose arguments do not parse (`@Types(T in [Int64])`) keeps its tokens; one whose arguments happen to parse is resolved as if it took expressions.
- **A body lowers a macro call's arguments** (`Expr.MacroExpr(args)`), of the innermost call when `@A[x] @M(…)` nests two; they are scoped and inferred each alone, the call's type an error. No diagnostic comes from them: a name the macro itself declares would be reported missing.

## Consequences

- Every macro call with arguments in this repository parses (`@Expect` 1 981, `@AssertThrows` 197, `@Assert` 38, `@PowerAssert` 11, `@Fail` 5). Of [tree-sitter-cangjie-testing](https://github.com/ide4cj/tree-sitter-cangjie-testing)'s 6 029 files, 11 105 parse and 189 stay tokens: declarations given to a macro (`@M(class C {})`), and std.unittest's tests of `@PowerAssert`'s invalid syntax (147).
- A name inside resolves to what it would mean outside the macro, which is what std's assertion macros mean, not what every macro does. Once a macro is expanded (#176), resolution goes through its output, the parsed arguments the fallback of a call not expanded; std's macros known without running them (#175) may tell which take no code.
- `MacroAttr` (`@AssertThrows[E]`, `@TestCase[x in …]`) stays tokens: std's syntax, #175's.
