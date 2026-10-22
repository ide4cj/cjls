# platform

Host-specific behavior in one multiplatform package. The
[manifest](cjpm.toml) maps `os.linux` and `os.darwin` through the non-product
`user.platform.posix` source set; Windows has its own product set.
[Common sources](src/common/) declare shared APIs with `common`, and platform
sets supply `specific` bodies. Shared implementations such as stream and child
process wrappers live in common. [C17](../../docs/design/03-conventions.md#c17-platform-source-sets)
is the canonical source-set and conditional-compilation rule (D101, D113).

Files carry their source set's `features` header (`@NonProduct` for intermediate
sets) and are named for their responsibility; the directory already identifies
the set. Architecture selection remains `hostArch`'s `@When[arch == …]` because
cjpm deduces OS features only. `hostOs()` is a function because a `common let`
would require its `specific` in the immediate `posix` set. Unused `specific`
parameters trigger warnings; warning configuration follows
[Development](../../docs/development.md#toolchain-constraints) (D97).

## SDK workarounds and verification

The canonical defect evidence, observed versions and limitations live in
[SDK issues](../../docs/sdk-issues.md):

- [K14](../../docs/sdk-issues.md#k14): preserve per-target release `-O1` for this
  module; `-O2` common output has caused duplicate std definitions (D102).
- [K15](../../docs/sdk-issues.md#k15): [build.cj](build.cj) removes stale lifted
  `.a`/`.cjo` files before building, then copies new product files into the path
  dependency tests search. Both stages matter. It scans this checkout's `target/`
  because cjpm supplies no target directory; arbitrary external output paths are
  not covered.
- [K16](../../docs/sdk-issues.md#k16): tests in common/posix sets are silently
  ignored. Put tests in a product OS set; common code is also exercised through
  consumers. A passing suite does not prove shared-set tests ran.

C17 gives the command to type-check another OS locally. This does not execute
that OS's tests; use its CI job for runtime verification.

Windows uses Win32 FFI: piped children start suspended with `CreateProcessW`,
inherit the intended pipe handles and stderr only, and join a kill-on-close job
before resuming (D78, D91). `relaunch` starts the server as a child after
`tieChildrenToThisProcess`. Keep blocking foreign calls consistent with
[C5](../../docs/design/03-conventions.md#c5-blocking-foreign-calls) and
[K2](../../docs/sdk-issues.md#k2); stdin's additional scheduling/read constraints
are [K1](../../docs/sdk-issues.md#k1) and [K3](../../docs/sdk-issues.md#k3).
