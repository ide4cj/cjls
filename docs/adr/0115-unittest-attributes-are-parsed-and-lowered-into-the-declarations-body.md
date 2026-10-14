# ADR-0115: A macro attribute is parsed by its shape and std.unittest's are lowered into the body of the declaration they are on

Status: proposed
Amends ADR-0059: `MacroAttr` is no longer tokens alone

## Context

- D59 parses a macro call's `(…)` as an argument list when it parses as one, and leaves `[…]` tokens: nothing in `@TestCase[x in data()]`, `@Configure[generationSteps: 10]`, `@Types[T in <Int64>]` resolved, was highlighted by meaning or reached by go to definition (#191). In this repository: 82 `@TestCase[…]`, 25 `@Configure[…]`, 10 `@Bench[…]`, 7 `@Test[…]`, 5 `@Strategy[…]`, 4 each of `@Measure`, `@Timeout`, `@Types`.
- std.unittest.testmacro (its sources at the nightly's commit) reads them itself: `x in src, …` (`parseDSL`), `x` a parameter by name or `config.<ident>`; `k: v, …` (`parseNamedCommaSeparatedExpressions`), `k` standing for `KeyK.k` (`createOptionFQName`); `T in <A, B>` (`types_macro.cj`); expressions (`@Timeout`, `@Measure`). `@Tag[A]` stringifies its identifiers; `@Skip[true]` is a literal. cjc's expansion evaluates `src` in a lambda of the test class's `asTestSuite()`: the class's members in scope, never the function's parameters.
- What the `[…]` is depends on the macro, which the parser does not know by meaning. #191 left open the parser's way (a node per shape) or a reparse at lowering once the macro's name resolved to std's (as #175 does for `@Derive`).

## Decision

- **The parser tries the shapes, as D59 does `(…)`**: between commas, `T in <A, B>` (`TypesArg`: a `Type` and a `TypeArgList`), `x in src` (`DataArg`: two `Expr`s), `k: v` and an expression (`Arg`); any error, and the attribute is tokens as before. One tree for highlighting, the source map and go to definition; a reparse at lowering was a tree, a file id and a map of positions of its own, as D59 found.
- **Lowered by the macro's name, not its resolution**: a body is syntax alone (D50), so it lowers the `[…]` of `@Test`, `@TestCase`, `@Bench`, `@Strategy`, `@Configure`, `@Timeout`, `@Measure`, `@Types` on the declaration (`Body.attrs`), and of no other: `@Tag`'s, `@Skip`'s, `@Derive`'s and a user's macro's identifiers resolve to nothing. Inference infers them only if the name resolves to std.unittest.testmacro's; a name in them resolves without it, as D59's arguments do.
- **The `[…]` is the declaration's code**: its item is the declaration the macro is on (`ItemIdMap.idAround`), its expressions in the declaration's body. `x` of `x in src` is a name in the scope of the parameters, `src` one at the body's root, where the members of the type around and the file are; `k` of `k: v` an access `KeyK.k` at the `Arg`, whose name resolves as one after a `.`; `@Types`' type parameter and types are types of the body. `config.x` is not lowered.
- **Inferred each alone**, as D59's arguments: `src` is given no `DataStrategy<T>` to meet, `v` no option's type.

## Consequences

- #191's open questions: the parser's way; `x in src` of `@Test[…]` on a class is not reported (#53's); `@Types` checks its types, never instantiates the declaration per type.
- A name inside the `[…]` of a macro of one of those names that is not std's resolves as if it were: the cost of lowering by name, as D59's of parsing by form.
- `@AssertThrows[A | B]` now parses as one `Arg` of a `|`; its types are still read from its tokens (`attrTypes`), `[pkg.E]` not yet.
