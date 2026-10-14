# ADR-0113: The architecture is a specific of each OS's source set, and a set's files are named for what they hold

Status: proposed
Amends ADR-0101: the architecture is no longer `@When[arch == …]`

## Context

- D101 left `hostArch` as `@When[arch == …]` in `platform`'s common set, and `cjls.macro_host` kept `@When[os == …]` constants (a shared library's suffix, the loader's variable, `PATH`'s separator) outside `platform`, against C17.
- cjpm deduces a feature of the OS alone (cangjie_tools `config/cjmp.cj`, `FeatureDeducer.deduceTargetFeatures`: the triple's architecture is not read); `os.*` are its only builtins, and `always-enabled-features` is `[package]`'s, on every target alike. A `user.` feature for an architecture is enabled by `--enable-features` alone.
- A set has one set above it: cjc takes one `--common-part-chir`. A set of an architecture beside `posix`, both above `linux`, fails (`function 'arch' has overload conflicts`, `'common' function 'arch' can not find 'specific' match`; probed on 1.3.0-alpha.20261014).
- The workspace is built for one triple per OS, those the root `cjpm.toml` names stdx for: `aarch64-apple-darwin`, `x86_64-unknown-linux-gnu`, `x86_64-w64-mingw32`.
- `std.unittest`'s `@Skip[…]` takes a literal `true` or `false` alone: a test cannot be left out by a condition known at run time.
- Two files of one name in two sets of a package (`common/os.cj`, `darwin/os.cj`) build and test.

## Decision

- **`hostArch` is `common`, its `specific` in each OS's product set**, as `hostOs`: no set and no feature of an architecture. Each set's test holds it to what the system says this process runs as (`uname -m`, `PROCESSOR_ARCHITECTURE`), so a build for another triple of an OS fails there rather than naming the wrong architecture.
- **What `macro_host` told by `@When` is `platform`'s**: `sharedLibrarySuffix`, `libraryPathVariable`, and the `pathListSeparator` it had.
- **A set's file is named for what it holds** (`windows/job.cj`, `posix/stdio.cj`), the set being its directory.
- **A test of a module using `platform` keeps its `@When` class** (D101): a module made multiplatform would build `-O1` (D102) and skip the tests of its `common` set.

## Consequences

- `@When` is in this repository's code only where tests of another platform are left out (`VfsPathOnWindowsTest`, `ErrorRootsGateTest`).
- A triple of another architecture for an OS that has one (`aarch64-unknown-linux-gnu`) is a product set of its own, chosen by a `user.` feature of its architecture that every build for it enables with `--enable-features`, cjpm deducing none.
