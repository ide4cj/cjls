# cjo

Reads the compiler's `.cjo` packages through generated views over their bytes.
[D37](../../docs/adr/0037-cjo-files-are-read-by-generated-views.md) explains lazy
validation and open enums. Opening checks the file identifier and format major;
invalid headers/versions raise a `CjoException`. Malformation discovered later
raises the re-exported `FbException` from [fbs](../fbs/README.md).
Views retain bytes and offsets rather than decoded fields, so cache repeated
field reads in loops when needed.

## Updating the SDK schema

[format.cj](src/format.cj) is generated from [CjoFormat.fbs](CjoFormat.fbs) through
[cjo_format.toml](cjo_format.toml), whose `open`, `rename` and `wrap` settings
preserve compatibility and the handwritten attribute wrapper.

For a new nightly, use the cangjie_compiler commit named by its release notes:
copy that commit's `schema/CjoFormat.fbs`, record its provenance in the config,
and review `include/cangjie/AST/AttributePack.h` against
[attributes.cj](src/attributes.cj). An inserted attribute shifts every later bit;
schema regeneration alone does not update this handwritten mapping.
Build the generator before altering generated output, then run from the root:

```bash
cjpm build
target/release/bin/fbs_codegen modules/cjo/cjo_format.toml
```

Follow [generator verification](../fbs_codegen/README.md#regeneration-and-verification).
The [reader tests](src/open_test.cj) require `CANGJIE_HOME` and read the SDK's
own std files on the host target. Unsupported versions, unknown enum/union
members and corrupt vector extents are tested by patching real compiler output
at vtable-derived offsets, keeping the oracle independent of `FbBuilder`.

## Compiler serialization details

The former module notes recorded these observations from all of std and stdx
on nightly `20260918`; they are historical evidence, not verification on every
new pin. Check the compiler and SDK-file tests when changing their interpretation.

- With `pkgId == 0`, `begin.file` indexes `allFiles` from 1 (0 means no file).
  With `pkgId > 0`, it indexes files of `imports[pkgId - 1]` from 0.
- Re-exports appear as `ImportSpec` entries in `allFileImports` (`reExport` 3
  for public, 1 for internal), rather than adding their declarations to `allDecls`.
- `Attribute.CompilerAdd` identifies synthesized declarations: top-level
  `macroCall_*` in macro packages, implicit constructors and their parameters.
- Primary constructors are serialized after `DesugarPrimaryCtor`
  (`src/Sema/Desugar/DesugarInTypeCheck.cpp` in the compiler): an `init`
  `FuncDecl` marked `Constructor`, `PrimaryConstructor`, `CompilerAdd`, and
  member-parameter fields marked `VarInfo.isMemberParam` and `CompilerAdd`.
  Neither the original `PrimaryCtorDecl` nor its `identifierForLsp` is written.
- `BuiltInDecl` entries such as `Array` and `CPointer` have placeholder positions
  (file 1, line 0), not navigable source locations.
