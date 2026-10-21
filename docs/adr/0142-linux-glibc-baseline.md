# ADR-0142: Build Linux releases on Ubuntu 22.04 and check them without the SDK

Status: proposed

## Context

The Linux release built on `ubuntu-latest` failed to start for a user on Ubuntu
22.04, reporting missing `GLIBC_2.38`. Cangjie's `--static` links its runtime into
the executable but leaves dependencies on system glibc and libstdc++. Testing on
the same current runner did not expose the incompatibility.

## Decision

- Build Linux release artifacts on `ubuntu-22.04`; retain the Cangjie static
  runtime and existing optimization settings. Building against the baseline
  userspace avoids introducing newer glibc symbol requirements at link time.
- Before uploading the artifact, run it with `--config-schema` in `ubuntu:22.04`
  with only the distribution's `libstdc++6` added. The SDK and runner libraries
  are unavailable there, so missing libraries or symbol versions fail CI.
- Include the runner label in build-cache keys. Objects built against a newer
  Linux userspace must not be restored into the baseline build.
- Keep the existing end-to-end tests on current runners to exercise the same
  artifact on newer systems too.

## Consequences

- Linux releases target Ubuntu 22.04's userspace; locally built executables can
  have newer system-library requirements.
- SDK upgrades must continue to build and run on this baseline. Fully static
  glibc or musl builds would need separate toolchain validation.
- The compatibility check needs Docker and network access to install the
  distribution runtime library. It checks startup, while the e2e suite checks
  protocol behavior.
