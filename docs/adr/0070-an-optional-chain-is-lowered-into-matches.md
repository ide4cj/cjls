# ADR-0070: An optional chain is lowered into the matches cjc desugars it to, Some and None lang items

Status: proposed

## Context

- D66 left `?.` of an error type (#48 step 8g): `a?` was an `OptionalExpr` of none, and so was every link after it.
- cjc (R3) parses an optional chain as an `OptionalChainExpr` around all of its links: an atom and its postfixes (`.b`, `(…)`, `[…]`, a trailing lambda, `++`), or the assignment whose left it is (`a?.b = x`, `a?.b += x`). Before the check, `DesugarOptionalChainExpr` lowers it into nested `match`es, one per `?`: `a?.b.c?.d` is `match (a) { case Some(v) => match (v.b.c) { case Some(v) => Some(v.d) case None => None } case None => None }`, an assignment `v.d = x` in the first arm and `()` in the second. That `match` is of `SugarKind::QUEST`, checked apart (`SynQuestSugarMatchCaseBody`): its selector must be an `Option`, and it is of its first arm's type, the second checked against that, with no join. The whole is synthesized whatever is expected of it, then checked (`ChkOptionalChainExpr`). R1 lowers `?` (Rust's try) the same way, into a `match` on lang items in its HIR.
- cjsyntax has no node around a chain: `a?` is an `OptionalExpr`, the left of the link after it.
- cjc 1.3.0-alpha.20261002 (N133–N135, in #48 step 8g's PR):
  - A chain is an `Option` of its last link: `a?.b`, `a?.f()`, `a?[0]`, `fn?(1)`, `a?.h {x => x}`, `a?.f` (a method as a value), `a?.d.e`; each `?` after the first adds none (`a?.od?.e` a `?Bool`), a link of an `Option` one more (`a?.o` a `??Int64`). A parenthesis ends it (`(a?.d).e` an error); an operator is outside it (`a?.b + 1` an error, `a?.b ?? 0` an `Int64`).
  - It is synthesized alone: `let x: ?Int8 = a?.id(1)` is an error, a `?Int64`; `let x: ??Int64 = a?.b` is boxed. Its left must be an `Option` ("cannot use optional chaining on non-optional value"); `??C`'s `aa?.b` is an error, `b` no member of `?C`.
  - An assignment to it is `Unit`: `a?.b = 1`, `a?.b += 1`, `a?.b++`, `a?[0] = "s"`, `a?.od?.e = false`.
  - A `Some` or `None` the package declares changes nothing.

## Decision

- **Lowered into the `match`es cjc desugars it to, in the HIR** (option B of step 8e, as R1's `?`), not typed in inference from the chain as written (A), which would have to walk the links after each `?` itself.
  - The lowering finds where a chain ends, which the syntax does not mark: the left of a link (and of an assignment) is lowered as a link of the same chain, any other expression ends the one it is in. Each `?` binds `$v`, a local no source can name, to the value of what it applies to.
  - The `match` is `QuestMatchExpr`, cjc's `SugarKind::QUEST`, and is inferred as `SynQuestSugarMatchCaseBody` infers it.
- **`Some` and `None` are lang items** (`LangItem.OptionSome`, `OptionNone`, A28), named in the HIR by `LangExpr`, as R1's `Path::LangItem`: constructors, found among `Option`'s members. The pattern `Some($v)` needs none: a pattern's constructor is the selector's type's.
- **A node's expression is the one as written**: a desugaring's expressions are added after those they are made of, of the same node, and `exprAt` gives the first (A29). `a?.g("s")`'s node is the call `$v.g("s")` there; the `match` around it, of the node's value (`?String`), after.

## Consequences

- On this repository's source at 5ae6776, this change's test binary and master's run over it:
  - Of 169 460 expressions (169 822 with the `match`es added), those of an error type went 12 990 → 12 599, those holding one 883 → 879. 389 get a type (members 115, `?`s 90, calls 70, operators 44), none loses one; 25 that held an error hold none now (`….map {p => p.name()?.text() ?? ""}` an `Iterator<String>`).
  - Of its 88 chains, 83 are typed; 3 have a left of no type (`inflight.remove(id)?`, `param.name()?` twice), 2 a member a macro declares (`binarySources`, `typeAliasType`, D47's gap).
- A cold pass over every body, master's binary then this change's in turns, on this workstation busy (load 6–12): 12 runs each, of two modes in both. Master's: 7 at 16.6–17.0 s, 3 at 17.2–18.0 s, 2 at 21.4–21.8 s, median 17.0 s; this change's: 5 at 16.6–16.9 s, 1 at 17.2 s, 6 at 20.8–22.1 s, median 19.0 s. The fast modes are the same; whether the slow one is more frequent wants a quiet machine. `InferenceBench` (the memos read; load 16–26) 21.40 ms ±14.5% and 21.25 ms ±13.7% before, 20.77 ms ±5.4% and 22.49 ms ±12.4% after: unchanged within noise.
- Not yet: branches joining an `Option` and its argument (`if (c) { a?.b } else { 1 }`, `?Int64` to cjc) are an error, `Int64` not boxed; the mismatches are not reported (8c′), "cannot use optional chaining" among them.
