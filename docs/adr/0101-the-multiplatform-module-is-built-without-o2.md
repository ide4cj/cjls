# ADR-0101: The multiplatform module is built `-O1`, not `-O2`, and the workspace root names no `-O`

Status: proposed. Supersedes D51's sections in the root's `cjpm.toml`.

## Context

- The platform code moves to a multiplatform module (CJMP, D100). cjpm compiles its `common` set to CHIR (`--output-type=chir`), then the product set with it (`--common-part-chir`). On `1.3.0-alpha.20261002` (Linux) and `20260918` (macOS), at `-O2` (and `-Os`) the common CHIR keeps the bodies of the std functions it imports (298 against 24 at `-O0`/`-O1`), and the product compile emits those it does not call itself as global definitions: whatever links the library fails, `multiple definition of _CNat7printlnHRNat6StringE` against `libcangjie-std-core.a`. `print`, `println`, `ArrayList`'s and `HashMap`'s generic bodies leak; `String.split`, `Path`, `StringBuilder` do not.
- At `-O1` the common CHIR holds declarations only: no leak, and the server links and runs. cjc refuses a common part and a product part at different levels; `--fno-chir-function-inlining` and its siblings change nothing.
- The root's `[target.<triple>.release]` reaches every member's cjc line, the CJMP module's included, before the module's own; every other module names its `-O2` itself (D51).

## Decision

- **The CJMP module's `[target.<triple>.release]` is `-O1`**; a `-g` build is `-O0`, as everywhere.
- **The root names no `-O`**; every other module keeps its `-O2`.

## Consequences

- The platform module is not inlined across packages: system calls and small wrappers, nothing on the analysis' paths.
- A nightly whose common CHIR leaks nothing at `-O2` gives the module D51's `-O2`.
