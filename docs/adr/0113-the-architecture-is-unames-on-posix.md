# ADR-0113: The architecture is what `uname` tells the process on POSIX and fixed on Windows, and a set's files are named for what they hold

Status: proposed
Amends ADR-0101: the architecture is no longer `@When[arch == …]`

## Context

- D101 left `hostArch` as `@When[arch == …]` in `platform`'s common set, and `cjls.macro_host` kept `@When[os == …]` constants (a shared library's suffix, the loader's variable, `PATH`'s separator) outside `platform`, against C17.
- cjpm deduces a feature of the OS alone (cangjie_tools `config/cjmp.cj`, `FeatureDeducer.deduceTargetFeatures`: the triple's architecture is not read); `os.*` are its only builtins, and `always-enabled-features` is `[package]`'s, on every target alike. A `user.` feature for an architecture is enabled by `--enable-features` alone.
- cjpm takes sets as a DAG and gives the product each set above it (`--common-part-chir` once per parent), but cjc then sees `common`'s declarations once per path: a set of an architecture beside `posix`, both above `linux`, fails (`function 'arch' has overload conflicts`, `'common' function 'arch' can not find 'specific' match`; probed on 1.3.0-alpha.20261014). A feature an OS maps to (`os.linux` → `user.platform.x86_64`) has no set to choose, then.
- The workspace is built for one triple per OS, those the root `cjpm.toml` names stdx for: `aarch64-apple-darwin`, `x86_64-unknown-linux-gnu`, `x86_64-w64-mingw32`.
- `std.unittest`'s `@Skip[…]` takes a literal `true` or `false` alone: a test cannot be left out by a condition known at run time.
- Two files of one name in two sets of a package (`common/os.cj`, `darwin/os.cj`) build and test.

## Decision

- **`hostArch` is read from `uname` on Linux and macOS**, once, in `posix` (macOS's `arm64` named `aarch64`, as cjc does); the size of `struct utsname`'s fields is the OS set's. **On Windows it is `x86_64`**, the one triple cjls is built for there. Each product set's test holds it to `uname -m` (`PROCESSOR_ARCHITECTURE`).
- **What `macro_host` told by `@When` is `platform`'s**: `sharedLibrarySuffix`, `libraryPathVariable`, and the `pathListSeparator` it had.
- **A set's file is named for what it holds** (`windows/job.cj`, `posix/stdio.cj`), the set being its directory.
- **A test of a module using `platform` keeps its `@When` class** (D101): a module made multiplatform would build `-O1` (D102) and skip the tests of its `common` set.

## Consequences

- `@When` is in this repository's code only where tests of another platform are left out (`VfsPathOnWindowsTest`, `ErrorRootsGateTest`).
- Another architecture of Linux or macOS needs nothing of `platform`; one of Windows changes its `hostArch`, which its test tells.
- A `common` declaration may be in an intermediate set (`posix`'s `utsnameFieldSize`), given by each set below it.
