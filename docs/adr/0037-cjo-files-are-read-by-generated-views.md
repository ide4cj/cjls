# ADR-0037: A `.cjo` is read through views generated from its vendored schema, on a runtime of our own, with no verifier; the enums a patch may extend are open

Status: accepted, 2026-10-02

## Context

- `std` and every binary dependency (`stdx`) are compiled packages and their `.cjo`: no sources. Name resolution (#48) needs their declarations, so the server reads the `.cjo`, as R4 (through cjc's `CjoManager`) and R9 do (#68; Q11, #49).
- A `.cjo` is a flatbuffer, `CJOF`, `root_type Package`, its schema `schema/CjoFormat.fbs` of cangjie_compiler. The SDK does not ship the schema.
- The SDK's `flatc --cangjie` generates accessors that are not `public`, allocates a class per table access, copies a vector whole into `Array<Option<…>>`, and throws on an enum value it does not know.
- `include/cangjie/Modules/CjoVersion.h`: a file of another major is laid out otherwise; a patch may append to `TypeKind`, `DeclKind`, `ExprKind`, `PackageKind` and to any union. A file without `cjoVersion` is a mismatch to cjc.
- `Decl.attributes` is the raw bitset of cjc's C++ `Attribute` (`AttributePack.h`), which the schema does not describe.

## Decision

- **`modules/cjo`** (`static`, no dependencies, D3): a read-only flatbuffers runtime (`FbTable`, a lazy `FbVector<T>`, strings, unions; no builder) and `struct` views over the bytes and an offset. `openCjo` checks `CJOF` and the major of `cjoVersion`, and refuses a file without one.
- **The views are generated** by `fbs_codegen`, as D10's: it reads the subset of `.fbs` one schema of one file uses, and needs no `flatc`. The schema is vendored from the cangjie_compiler commit of the pinned nightly; the output is checked in through `cjfmt`, and `GeneratedFilesTest` fails when it is not what the generator makes.
- **No verifier.** `Array<Byte>` checks every index, and a length that runs past the file is refused where it is read: a broken file throws `CjoException` (or `IndexOutOfBoundsException`) from the view that reads it. Its reader catches that per package and leaves the package out.
- **Open enums.** The enums `CjoVersion.h` lets a patch extend, named in the config, have `Unknown(value)`; so does every union. A closed enum throws on a value it lacks: that is a broken file.
- **`Attribute` is mirrored by hand** from `AttributePack.h` at the vendored commit, its bits checked by tests on the SDK's own files.

## Consequences

- A new nightly means vendoring the schema of its commit, regenerating, and checking `Attribute` against `AttributePack.h`; a new major means a reader of its own.
- Opening a file costs a header check; what is never read is never checked, and a view read twice is read twice.
- A value a newer patch added reads as `Unknown`, not as an error: a consumer of a view matches it with a `case _`.
- An enum's methods are written in an `extend`: in its body a constructor named like a type (`LitConstKind.String`) hides it. A constructor named like a type the package declares is refused by the generator until the config renames one (`Generic` → `Generics`).
