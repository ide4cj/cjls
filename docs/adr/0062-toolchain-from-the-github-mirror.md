# ADR-0062: The toolchain is downloaded from the GitHub mirror, checked against sha256 pinned from gitcode

Status: accepted, 2026-10-08
Amends ADR-0011: the nightly is downloaded from GitHub and checked against `.cangjie-sha256`

## Context

- The nightlies are released on gitcode ([Cangjie/nightly_build](https://gitcode.com/Cangjie/nightly_build/releases)); [cangjie-bot/nightly_build](https://github.com/cangjie-bot/nightly_build/releases) mirrors them on GitHub, tags and asset names alike. An archive downloaded from both had one sha256; from this workstation the mirror took 2.2 s for 22 MB, gitcode 8.7 s. CI runs on GitHub, where every cache miss downloads 0.2–0.3 GB of SDK per platform.
- `cangjie-bot` is a personal account (2025), not Cangjie's organization: nothing says who runs it. `release.yml`'s binaries are compiled by what `setup.py` downloads.
- Only the Windows archives come with a `.sha256`, and on the host that serves them.

## Decision

- **`setup.py` downloads from the GitHub mirror first, then gitcode**, on a failed request or a sha256 that is not the pinned one.
- **`.cangjie-sha256` pins every archive `setup.py` downloads**, for the tag in `.cangjie-version`, in `sha256sum`'s format. `setup.py pin <tag>` writes it from gitcode's archives, not the mirror's: a toolchain bump is both files in one commit. An archive not in it is not downloaded. Rejected: trusting the mirror (a personal account then chooses the compiler of the releases), the mirror alone (a mirror can lag or go).

## Consequences

- A bump downloads every platform's archives once (`pin`, about 0.75 GB) where it changed a line.
- A mirror serving other bytes is a warning and a slower download, not a broken toolchain.
- `setup.py` with a tag other than the pinned one stops, naming `pin`.
