# ADR-0027: Builds are incremental, clean on a new compiler and for a release; CI caches `target`

Status: accepted, 2026-09-27

## Context

`cjpm build` without `-i` compiles every package every time: 18 s for a build with nothing changed, on an M-series Mac. CI builds from nothing on each of its three platforms, and `cjpm test` there compiles everything once more after `cjpm build` (1–3 min per platform, Windows the slowest). What cjpm's incremental mode (`-i`, cjpm 1.3.0-alpha.05) actually tracks, measured:

- **A package, by its sources' mtimes** — equality with the last build's, not "newer than": the content is not read, nor its size. A file changed with its mtime kept is not compiled again; one touched, added or removed is. Everything depending on a changed package is compiled again (no cut-off when its interface did not change); a macro package's users included.
- **The compile options**, per package (`options~` in `target/<profile>/incremental-cache.json`), and each output's timestamp.
- **Not the compiler.** Under another nightly, other path and other stdx included, nothing is compiled again and the build succeeds; a package changed afterwards is compiled by the new cjc against the old one's `.cjo` and linked with its `.a` — silently.
- **`cjpm build` and `cjpm test` in one target directory undo each other**: each switch compiles all 24 packages again. In directories of their own both stay incremental.
- A checkout gives every file a new mtime, so a restored `target` is useless as it is.

## Decision

- **Incremental everywhere**: `[profile.build] incremental = true` in the root `cjpm.toml` is `-i` on every `cjpm build`, `cjpm test` and `-m` build.
- **A new compiler is a clean build, by `build.cj`**: cjpm runs it before every build (`pre-build`, tests included); it compares `cjc --version` with `target/cjc-version` and, when they differ, deletes every `incremental-cache.json` under `target`, which cjpm reads as nothing built.
- **Tests build in `target/test`** (`cjpm test --target-dir target/test`), the `pre-push` hook and CI alike; `target/release` is the build's.
- **CI restores `target`** as the last green master build on that platform and nightly left it (`actions/cache`, the key the OS, the architecture, `.cangjie-version` and the commit), after giving every tracked file an mtime made of a hash of its content (`.github/actions/build-cache/stamp.py`): the same where the file is, another where it changed. **Only a push to master saves it**, so a PR never starts from another PR's build.
- **A release is built clean**: on a tag CI restores nothing, so the binaries attached are compiled from nothing by the pinned nightly.
- Otherwise clean is by hand, `cjpm clean`: after content was put back with its old mtime (`cp -p`, `rsync -t`, an archive unpacked), or `--skip-script`.

## Consequences

- A cache of ~210 MB (zstd) per platform and master commit; GitHub's 10 GB keeps about fifteen commits of three platforms, evicting the oldest.
- `cjpm test` in `target` by hand still works, at the price of a full build each time it alternates with `cjpm build`.
- If cjpm learns content hashes or the compiler's version, `build.cj` and `stamp.py` go.
