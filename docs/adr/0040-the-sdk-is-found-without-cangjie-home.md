# ADR-0040: The SDK is found without `CANGJIE_HOME`, and is what `${CANGJIE_HOME}` expands to

Status: accepted, 2026-10-04

## Context

- `std` is the SDK's `modules/<target>/std` (D33), read from its `.cjo` (D38); without it nothing resolves (#68).
- An editor launches the server with the environment of the desktop: `CANGJIE_HOME` is set by `envsetup.sh` in a shell, and is rarely there. cjsdk installs toolchains under `~/.cjpm/toolchains`, its default one at `default`. An SDK found on `PATH` has `cjc` in `<home>/bin`, often through a link.
- A manifest names the SDK in its paths too: `path-option = ["${CANGJIE_HOME}/third_party/stdx/…"]`.

## Decision

- **The SDK is the first that is a directory**: `initializationOptions.cangjieHome` (the editors pass it from a setting of their own); `CANGJIE_HOME`; `~/.cjpm/toolchains/default`; two up from `cjc` on `PATH`, links followed. `project_model.findCangjieHome`, for the server and `cjls project` alike.
- **It is what `${CANGJIE_HOME}` expands to** in every path of a project (`withCangjieHome`), not only where `std` is taken from: a project and its `std` come from one SDK.
- **The user is told once**, at `initialized`, by `window/showMessage`: no SDK found, or one of whose `std` no package was read (another major, the budget). Every load logs where the SDK was found and why a package was left out.

## Consequences

- A server launched from a desktop finds the SDK a shell would, without a setting, if cjsdk installed it or `cjc` is on the desktop's `PATH`.
- The editors' setting is theirs to add (D32).
- An SDK changed under a running server is seen at the next load of the project, as a `.cjo` changed is (#141).
