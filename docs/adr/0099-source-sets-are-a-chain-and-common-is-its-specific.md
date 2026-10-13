# ADR-0099: A multiplatform module's packages are the files of the target's chain of source sets, and a common declaration is its specific one

Status: proposed

## Context

- #318: a multiplatform module (CJMP, `[profile] experimental = true`) lays its packages out over `[[source-set]]`s (`src-dir`, `features`). `[[feature]]` maps a feature to the ones it enables (`os.linux` → `user.plat.posix`). `project_model` read only `src-dir`, so it named packages after the set directories (`plat.common`, `plat.linux`). Go to definition from a module depending on one found nothing.
- What cjpm and cjc do (1.3.0-alpha.20261002, probed on Linux, and cjpm's `source_set` suites):
  - cjpm deduces the host's `os.linux`, `os.darwin` or `os.windows`, adds `[package] always-enabled-features` and maps them through `[[feature]]`, transitively; a feature declared by `names` maps nothing, the `mapping` beside it ignored. It takes the sets whose features are all enabled, ordered from fewest features to most, each extending the one before. Two that do not extend each other fail the build: "Cannot compile multiple source sets without common parent source set". The deepest set is the product.
  - A package is the files of its directory under each set of the chain.
  - A `common` declaration of no body needs a `specific` one of the same name and kind further down the chain, else an error (`'common' function 'f' can not find 'specific' match`). The same goes for a constructor, a property, a variable, an enum's constructors, and a type with a member that needs one. A common one with a body needs none. A common class's members without `common` are members of the class the build has, though its specific does not repeat them. Overloads pair by signature.
- R1 has no counterpart. Kotlin's expect/actual is the nearest: the IDE resolves to the actual and shows the expect beside it.

## Decision

- **The package is the chain's files.** `project_model` reads the sets and features and picks the chain for the cfg's `os`, as cjpm does. A package gathers its files from every set of the chain, its `dir` the first set's, and the module's root is the first set's directory. The files of the other sets are `ModuleModel.inactive`, each with why: in no package, not read for the project, and when opened a file reported as wholly inactive and checked no further. A set the target enables off the chain is told as cjpm's error.
- **A common declaration is its specific one, paired in the def map by name and kind.** `collectDefMap` puts a `common` declaration aside, in `DefMap.commons`, when a `specific` one of its name and kind is in the package. The name then stands for the specific alone, so there is no ambiguity and no redefinition. A common type's self type is its specific (`selfTyOf`). A specific type's members are its own, plus those of its common type that it lacks (`commonMembersNamed`). Go to definition shows the specific and then the commons it completes (`commonsOf`). `noSpecifics` reports what needs a specific and has none, in cjc's words.
  - Rejected: pairing by signature, as cjc does. The def map sits under signatures (A22), so overloads would stay ambiguous until inference picked between identical candidates. With pairing by name and kind, a common overload is put aside as soon as any overload of its name has a specific.

## Consequences

- An overload set split between commons with a specific and without one resolves to the specifics alone, and the common left over is not reported. cjc rejects that code anyway.
- Generic common types keep their own type parameters as the specific's arguments, so their bodies type-check against the specific.
- One chain per project, the host's: the code of other targets is inactive, as with `@When` (#298, #300 would analyze it under its own cfg).
- `cj-project.json` keeps a package's files from several directories (`../posix/posix.cj`) and the inactive files with their reasons, so `cjls project` prints the chain.
