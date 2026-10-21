# macro_host

Builds and runs workspace and SDK macros without LSP or server state, so analysis
gates and other loupe clients can use the same pipeline. Server thread ownership,
settings and open-document handling stay in `cjls.macro_host`.
[D104](../../docs/adr/0104-workspace-macros-are-built-by-cjc-and-run-under-a-deadline.md)
and [D123](../../docs/adr/0123-std-macros-run-in-the-macro-server.md) explain the
workspace and std paths. The [manifest](cjpm.toml) defines dependencies;
[sdk.cj](src/sdk.cj) validates the selected SDK and its token numbering.

## Build and expansion invariants

Builds use the project's SDK toolchain under its `envsetup` environment. A build
holds the output directory's OS lock; cache cleanup must take the same lock
([D106](../../docs/adr/0106-the-servers-directory-is-the-projects-cache-cjls.md)).
Plans group macro packages by their project's output directory, including linked
source packages. Results are keyed by `Package`, since different projects may
use the same package name ([#338](https://github.com/ide4cj/cjls/issues/338)).
The caller chooses the project cache path and version-derived directory;
unchanged stamps skip rebuilding. Tests use a fake toolchain as well as SDK cjc.

Calls record input text in a `WireLayout` so answer positions map back to original
sources ([D98](../../docs/adr/0098-workspace-expansions-are-an-input-of-their-file.md)).
Only libraries built at the analysis snapshot's stamp, or shipped std libraries,
are eligible. Requests stop when the snapshot changes; answer fingerprints keep
results attributable to their original inputs. [host.cj](src/host.cj) starts a
server lazily, restarts after failure, and kills calls exceeding their deadlines.
Unit-test deadlines are fired explicitly rather than depending on wall-clock races.

Preserve separate std/workspace server processes and the current separation of
request selection and sending. Their SDK failure evidence and limits are
canonical in [K23](../../docs/sdk-issues.md#k23) and
[K22](../../docs/sdk-issues.md#k22); this documentation migration did not reproduce
or retire either workaround.

## SDK and corpus gates

Tests require `CANGJIE_HOME` for the server, compiler and token numbering.
[drift_test.cj](src/drift_test.cj) compares loupe's std macro expansions with SDK
std declarations. The served diagnostics gate builds workspace macros in a fresh
directory, expands calls through the real SDK server and checks this repository
has no findings. Its shared `gateFindings` pipeline also powers Optics.

Before `OpticsGateTest`, load the pinned SDK and fetch the pinned corpora from the
repository root:

```bash
python3 tests/corpora/fetch.py
cjpm test --no-progress --timeout-each=2m --target-dir target/test '--filter=OpticsGateTest.*'
```

The gate requires `.corpora/Optics/cjpm.toml`, builds its macros, and expands and
analyzes the workspace. Every finding must match
[optics_diagnostics_known.txt](optics_diagnostics_known.txt), including its reason;
the known list only shrinks ([D137](../../docs/adr/0137-optics-is-the-gate-of-workspace-macros.md)).
`UPDATE_EXPECT=1` rewrites the list and preserves existing reasons; new entries
receive `?` and need attribution, never automatic acceptance. Review every diff
under the [analysis rules](../../docs/design/02-analysis.md).
Both diagnostics gates are tagged `gate`: ordinary full tests include them;
coverage excludes them. Follow [Development](../../docs/development.md) for SDK
setup, compiler shim, full-suite prerequisites and coverage commands.
