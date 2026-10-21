# ADR-0113: `hostArch` is the one `@When` of this repository's code, and a set's files are named for what they hold

Status: accepted, 2026-10-20
Amends ADR-0101: `cjls.macro_host`'s `@When` constants go to `platform`; what may keep a `@When` is named

## Context

- D101 left `hostArch` as `@When[arch == …]` in `platform`'s common set and the `@When` classes of tests of a module using `platform`; `cjls.macro_host` still had `@When[os == …]` constants (a shared library's suffix, the loader's variable, `PATH`'s separator), against C17.
- cjpm deduces a feature of the OS alone (cangjie_tools `config/cjmp.cj`, `FeatureDeducer.deduceTargetFeatures`: the triple's architecture is not read, nor is `--target`'s); `always-enabled-features` is `[package]`'s, on every target alike. A `user.` feature of an architecture is chosen by an OS's mapping (`os.linux` → `user.platform.x86_64`) or by `--enable-features` on every call.
- Linux is to be built for `aarch64` as well (the nightly has its SDK and stdx; Windows has `x64` alone): an OS no longer tells the architecture, and a set of an architecture under each OS's set (`common → posix → linux → {x86_64, aarch64}`) would be chosen by `--enable-features` alone, every `cjpm build` and `cjpm test` failing without it.
- A set of an architecture beside `posix`, both above `linux`, fails: cjpm gives the product both (`--common-part-chir` per parent), and cjc sees `common`'s declarations once per path (`function 'arch' has overload conflicts`; 1.3.0-alpha.20261014).
- Reading the architecture at run time (`uname`) answers what the machine is, not what cjc built for.
- `std.unittest`'s `@Skip[…]` takes a literal `true` or `false` alone: a test cannot be left out by a condition known at run time.
- Two files of one name in two sets of a package (`common/os.cj`, `darwin/os.cj`) build and test.

## Decision

- **`hostArch` is the one `@When` of this repository's code**, `@When[arch == …]` in `platform/src/common/os.cj`: cjc, building for the target, is all that knows its architecture.
- **Elsewhere a `@When` is only a test's of a module that is not multiplatform**, leaving out a test of another platform (D101); `platform`'s tests are in their OS's set.
- **A new exception is a decision of its own**, an ADR.
- **What `macro_host` told by `@When` is `platform`'s**: `sharedLibrarySuffix`, `libraryPathVariable`, and the `pathListSeparator` it had.
- **A set's file is named for what it holds** (`windows/job.cj`, `posix/stdio.cj`), the set being its directory.

## Consequences

- A triple of another architecture needs nothing of `platform`.
- A cjpm that deduces a feature of the architecture would let `hostArch` be a `specific` of sets of it, and the exception go.
