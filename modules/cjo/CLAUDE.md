# `cjo` — the `.cjo` files cjc writes

`openCjo(bytes)` gives the `Package` of a `.cjo`, read through views over the bytes; why there is no verifier and which enums are open is [D37](../../docs/adr/0037-cjo-files-are-read-by-generated-views.md).

- **`src/format.cj` is generated** by `modules/fbs_codegen` from `CjoFormat.fbs` as `cjo_format.toml` says (`open`, `rename`, `wrap`); never edit it. Regenerate with `cjpm build && target/release/bin/fbs_codegen modules/cjo/cjo_format.toml` (it runs `cjfmt`); `GeneratedFilesTest` in `fbs_codegen` fails when what is checked in is not what it makes. `fbs_codegen` reads the subset of `.fbs` one file of a schema uses and refuses the rest (`include`, `rpc_service`, explicit `id`); a constructor named like a type it refuses until the config renames one.
- **A new nightly**: take `schema/CjoFormat.fbs` of the cangjie_compiler commit it was built from (its release notes name it) into `CjoFormat.fbs`, put that commit in `cjo_format.toml`, regenerate, and go through `include/cangjie/AST/AttributePack.h` at that commit for `src/attributes.cj`: an attribute inserted moves every bit after it, and nothing but the tests on the SDK's files would notice.
- **The runtime** (`src/flatbuffers.cj`): `FbTable` reads a field by its id (a union takes two: its type, then its value); `FbVector<T>` reads an element when it is asked for, and refuses a length that runs past the file when it is made. A view is a `struct` of the bytes and an offset, so reading a field twice reads it twice: keep what a loop reads more than once.
- **What the schema does not say** (measured on all of std and stdx, nightly 20260918):
  - `begin.file`: with `pkgId == 0` an index into `allFiles` counted from 1 (0: no file); with `pkgId > 0` the file is of package `imports[pkgId - 1]`, counted from 0 among that package's files.
  - A re-export (`public import`) is an `ImportSpec` with `reExport` (3 public, 1 internal) in `allFileImports`; what it re-exports is not in `allDecls`.
  - What cjc added is marked `Attribute.CompilerAdd`: at the top level only the `macroCall_*` of macro packages; among members implicit `init`s, their parameters and the like.
  - A `BuiltInDecl` (`Array`, `CPointer`, …) has no real position: file 1, line 0.
- **Tests** read the SDK's own std (`CANGJIE_HOME`, any target). A case the SDK's files do not have (an unknown enum value or union member, a foreign major, no version, a vector longer than the file) patches the bytes of a real file at the offset its vtable gives: there is no builder, and none is wanted for tests.
