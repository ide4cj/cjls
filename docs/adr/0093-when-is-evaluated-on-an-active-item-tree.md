# ADR-0093: @When is evaluated on an active item tree and in lowering, against the package's cfg

Status: proposed

## Context

- #149: loupe saw both twins of a `@When` (two overloads, a redefinition, false `ErrorTy`s in std, D77). `Cfg` was in the project model (D33) and nothing read it.
- What cjc does (`src/ConditionalCompilation`, cangjie_compiler at the 1.3.0-alpha.20261002 nightly, and probes of it):
  - A false node is dropped after the parse and before imports, macros and Sema. That covers imports and declarations at any depth (members, enum constructors, extend members, prop accessors), **function parameters** and **declarations in a block**. Nothing else is checked in the dropped code.
  - A condition it rejects is an error: an unknown name, a value outside a closed set, `!` other than before `debug`/`test`, a right side not a plain string literal, a bad `cjc_version`. `&&` and `||` check both sides.
  - With no `--cfg`, cjc reads `cfg.toml` in the directory of the package it compiles. cjpm passes no `--cfg` and `-p <the package's directory>`: verified with `cjpm run -V`, where `src/cfg.toml` set the condition.
- R1 keeps an item that `#[cfg]` disables in its `ItemTree` with the condition. The item tree is keyed by (file, crate). The `DefMap` collector and body lowering leave the item out, and an `Invalid` condition counts as active. R1 greys inactive code with an `Unnecessary`-tagged diagnostic whose reason comes from the DNF.
- In loupe every reader of a file's declarations goes through `itemTreeOf`, not the def map alone. That includes def maps, imports, members, extends, macro calls and expansions. Bodies and signatures are lowered from the syntax.

## Decision

- **The item tree keeps every item and its condition** (`Item.condition`, `ImportItem.condition`, a `CfgExpr` lowered with nothing of the tree). It stays independent of the cfg. A tracked `activeItemTree(file)` is that tree with what is false left out, members with their item. `itemTreeOf` returns it for a source file. A file of no `@When` returns its item tree unread of the cfg.
  - Rejected: the def map evaluating it, as #149 proposed and R1 does. Every other reader of the item tree would then have to evaluate the condition too.
- **Body and signature lowering skip** a parameter, a declaration of a block, or an accessor under a false `@When` (`ActiveFilter`). The filter reads the cfg only once it meets a `@When`, so a body with none does not depend on the cfg.
- **The cfg of a file** (`cfgOfFile`) is the project's. Its module's replaces it key by key, and its package's replaces both: the `cfg.toml` of the package's directory, read by `project_model` (`withPackageCfgs`) as cjc reads it. The host's cfg has `os`, `arch`, `env` and `backend`. It also sets `test`, since a package's tests are among its files (R1's `cfg.setTest`). It leaves `debug` unset, as a build without `-g` does. `cjc_version` is not set yet.
- **Evaluation is three-valued**, as R1's. A condition whose value the cfg does not set, or one cjc rejects, is unknown. Unknown code is **active**, and what cjc rejects is still an error.
- **`whenDiagnostics(file)`** reports:
  - each piece of inactive code, outermost only, as a `Hint` tagged `unnecessary` (`Unnecessary` on the wire): `code is inactive due to @When: os is "Linux"`. The reasons are the conditions that make it false, with their values.
  - what cjc rejects whatever the build, in cjc's words. A condition neither cjc knows nor the cfg sets is no error, though cjc reports it in a build that does not set it: a `--cfg` of `compile-option`, of a profile or of the command line may set it, and the analysis sees none of them.
  - nothing inside inactive code.

## Consequences

- A change of the cfg runs `activeItemTree` of the files with a `@When` again, and the bodies that met one. The parse and the item trees are left alone. A file whose active tree comes out equal stops there.
- One cfg per package. Code false under it has no semantics: references and rename miss it, as in R1 (#298 analyzes it under a cfg it is active in, #300 all configurations).
- A user condition set only by a `--cfg` is unknown, so its code is active, and a misspelt one goes unreported. Reading `compile-option` and the settings is #297's, and it brings the error back where the cfg is known whole.
- Completion in `@When[…]` waits for completion itself.
