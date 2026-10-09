# ADR-0067: The sources of std are fetched by `cjls fetch-src`, from `cangjie_runtime` at the commit the nightly's release notes name, into the SDK's `src`

Status: proposed

## Context

- Go to definition into `std` needs its sources of the SDK's version, found at `initializationOptions.cangjieSrc`, `CANGJIE_SRC` or `<CANGJIE_HOME>/src` (D65); nothing put them there (#210).
- Nothing in the SDK names the commit it was built from (searched: its files, `cjc`, the runtime's libraries). `cjc --version` prints the version, `1.3.0-alpha.20261002001050`, which is a nightly's tag. Its release notes, on gitcode and on the GitHub mirror (D62) alike, list `- **cangjie_runtime**: \`5d555bcc34d6\`` among the commits: so did all 200 of the mirror's newest when checked. Both serve them through an API without a login (`api.github.com/…/releases/tags/<tag>`, `api.gitcode.com/api/v5/…/releases/tags/<tag>`).
- GitHub's mirror serves `cangjie_runtime` at a commit, short or full, as one `.tar.gz` (3.2 MB at that commit, `std` 675 entries of it); gitcode's archives ask for a login. A partial clone needs the full commit and `git`.
- A release SDK (`1.0.0`) has no release notes there; `cangjie_runtime` has tags `v1.2.0` and the like, unchecked against the releases' builds.
- The server is launched by an editor: a download from it would need a setting to turn it off, and fails where it cannot be seen. R1 never downloads `rust-src`; rustup does, on a command.

## Decision

- **A command, never the server**: `cjls fetch-src [--dir <dir>]` takes the SDK as the server finds it (D40), its version from its `cjc --version`, the commit from the first release notes of that tag that name one (the mirror's, then gitcode's), downloads `cangjie_runtime` at it from the mirror and keeps `stdlib/libs/std` and the `LICENSE`.
- **Into the SDK's `src`** by default, where D65 looks without a setting, so the sources go with the toolchain they are of (R1's `rust-src` in the sysroot); `--dir` for an SDK not writable, named then by `CANGJIE_SRC` or the editor's setting. Rejected: a cache of cjls's keyed by version, a second place to look and to clean.
- **Stamped** by `cangjie_runtime.commit`: the same commit is not downloaded again, another one's sources are replaced, and a directory without the stamp is the user's and left alone. Laid out next to the target and renamed into it, so a failure leaves what was there.
- **`curl` and `tar` of the host**, which Windows 10, macOS and Linux ship: stdx's TLS loads OpenSSL at run time, which Windows and macOS lack, and an HTTP client, gzip and tar of our own are more than this needs.
- **The mirror unchecked**: no sha256 is published for an archive of sources, and these are only read, never compiled; sources of other text than the `.cjo`'s answer nothing (D65's check of the name).

## Consequences

- `cjls fetch-src` once per nightly installed gives go to definition into `std`; a release SDK's is not fetched, and the command says so (`CANGJIE_SRC` for sources of one's own).
- Tests fake the network, `tar` and `cjc`; no test downloads.
- Not yet: `stdx` (`cangjie_stdx`, also in the notes), a release SDK's commits (perhaps `cangjie_runtime`'s `v<version>` tags), a cjsdk component doing the same.
