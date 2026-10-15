# ADR-0126: The code style follows std where the compiler leaves a choice, and cjlint checks the official guide's rules that hold here

Status: accepted, 2026-10-15

## Context

- C1–C17 settle what a choice costs (a call across packages, a blocked GC, a flaky test); how the code reads was left to habit, and habits diverged over 94k lines: `prop size` beside `func isEmpty()` and `func text()` in one type, 1163 `import pkg.*` beside 850 single names, a package imported both ways across files, 231 Bool names with `is`/`has`/`can` and ~300 without, 138 `ArrayList` + `for` + `toArray()` beside `.map`/`|>`, 36 `case Some(x) => f(x)` / `case None => None`, 47 `getOrThrow()` in production code, 203 of `loupe`'s 348 public top-level declarations named by no other module, 630 public members and 118 public top-level declarations without a doc comment.
- Huawei's coding guide for Cangjie (仓颉语言编程规范, ids `G.NAM.01`, `G.VAR.01`, …) is not published; its rules live in `cjlint` (`~/.cangjie/tools/bin/cjlint`, 1.3.0-alpha.06), configured by `cjlint_rule_list.json`. std's own sources (`.corpora/cangjie_runtime/stdlib/libs/std`) are the other reference, and depart from the guide where it does not fit a library: 288 `import x.*` to 181 single names against `G.PKG.01`, `isEmpty()` a function, `size` a property.
- `cjlint -f modules/<m>/src` over every module (2026-10-15): 5493 findings in production code, 1862 in tests. 3398 are `G.PKG.01` (a `*` import); 686 `G.NAM.01` call every package of more than one segment misplaced (`cjls.server` in `src/server`); `G.CON.02` flags a `synchronized` inside a `try`, `G.EXP.03` the lazy right operand of `??` (`?? storage.runtime.ingredient(…)`), `G.FMT.15` `1e0` as a decimal without its leading zero, `G.ERR.02` any `IOException` thrown; and it lints macro expansions (`@Test`, `@Bench`, `@CalcaTracked`) at columns past the line's end. What holds with little noise: `G.VAR.01` (5 in production code), `G.EXP.06`/`G.EXP.07`, `G.NAM.03`–`05`, `G.DCL.02` (51), `G.ERR.04`, `G.ENU.01`, `G.EXP.01`, `G.OPR.02`, `G.ITF.03`.

## Decision

- **Where the compiler leaves a choice, the code writes it as std does**, and the guide's rule where std has none; a departure from either is a rule of `03-conventions.md`, saying why. The rules are C18–C31.
- **`import pkg.*`** for std, stdx and the workspace's packages, against `G.PKG.01`: as std writes it, an import per name changes with every name a file starts using, and a clash is settled by an alias already (C8).
- **An accessor is a property, not std's function** (`isEmpty`, `firstChild`, `parent` as `prop`): a read with no argument and no effect looks like one at the call, whatever it computes; only work that grows with the data, an effect or an exception makes it a function, and a std interface's own member keeps std's form.
- **Bool names are predicates; a public type and a top-level function always have a doc comment, a member when its name and type do not say it all.**
- **cjlint runs in CI with a rule list of the repository's own**, the rules above that hold here, not the SDK's default list; a finding inside a macro expansion or a generated file is dropped. It is turned on when the cleanup has brought those rules to zero, a job beside `Format`.

## Consequences

- A new rule of style is a row of `03-conventions.md` like any other; one cjlint checks names its rule id there.
- The cleanup is an epic of issues, one per rule or module, each a change with no behaviour of its own; `cjls fmt --check` and the tests are its checks, cjlint's list growing as rules reach zero.
- A cjlint rule that is noise here stays off; it is not bent around, nor the code bent around it.
