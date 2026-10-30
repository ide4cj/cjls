# Project discovery and normalization

`project_model` discovers build inputs and lowers them to loupe's plain
`ProjectModel`. It can read manifests and the filesystem, but does not run analysis
queries or own the server's mutable state. The server applies the resulting model
through its write boundary. See [architecture](../../docs/architecture.md#analysis-and-incremental-state)
and [analysis rules](../../docs/design/02-analysis.md).

## Discovery and partial loads

[project.cj](src/project.cj) owns discovery precedence and reports recoverable
problems alongside the model. A directory tries `cj-project.json`, then
`cjpm.toml`, then loose files; an unreadable manifest is reported before trying
the next source. Linked projects and directories discovered from an open document
enter through the same normalization. Keep selection and fallback behavior in
this layer, rather than duplicating it in LSP handlers (D33, D88).

Git and registry dependencies use the entry project's `cjpm.lock` (v0 or v1)
and sources already downloaded by cjpm. Ordinary/test dependencies use `requires`; build
script dependencies and their transitive imports use `scripts`. A dependency's
own lock does not override the entry project's resolution. For Git, the loader
checks the declared URL and selector against the lock, then reads the exact cached
commit, including members of Git workspaces. It never fetches or runs build
scripts during discovery. Missing or stale locks/checkouts produce recoverable
problems directing the user to `cjpm update`.

Ordinary and target-specific
`test-dependencies` are retained as `testDeps`, visible only in `*_test.cj` files
of the declaring module. They never widen production imports, downstream imports,
or build-script scopes; ordinary dependencies of a test dependency still resolve
inside that dependency. A dependency declared in both categories remains ordinary.
Discovery includes dependencies' own test graphs, as `cjpm check` and `cjpm test`
do, so their loading problems can still be reported; import visibility is separate
from discovering those sources. The JSON projection preserves optional `testDeps`.
Test-file re-exports stay within the declaring package's test context and do not
enter its production exports.

The repository cache follows `cangjie-repo.toml` precedence: project, user
`~/.cjpm`, then SDK `tools/config`. Relative cache paths are relative to the
configuration file; an empty or absent path defaults to `~/.cjpm` (HOME, else
USERPROFILE). Project-local config and lock changes reload the project.
Registry declarations accept a version string or `{version = "..."}`. Versions
are numeric `major.minor.patch` triplets; constraints are exact versions or
comma-separated unions of intervals, such as `1.2.3, [2.0.0, 3.0.0), (4.0.0,)`.
The loader checks the locked version against the constraint, then reads
`repository/source/<organization or default>/<name>-<version>` beneath the cache.
It verifies the downloaded manifest's qualified name and version. Missing,
malformed or incompatible entries remain recoverable loading problems. A v1
registry entry also needs a `registry+` source and cjpm's checksum metadata;
this loader does not revalidate the original archive checksum against extracted
sources (they are different byte streams).

The declaration forms and interval syntax were checked with the pinned
`cjpm 1.3.0-alpha.06` (SDK `1.3.0-alpha.20261014001050`): valid examples reach
registry lookup, while `^1.2.3`, `~1.2.3`, `1.2` and `01.2.3` fail validation.
Cache layout and v0/v1 interpretation follow the current
[cjpm source](https://github.com/cangjielanguage/cangjie_tools/tree/9a9a0ef227629ef765214d25a75d7b031b184af8/cjpm/src)
(`config/dep_version.cj`, `config/lock.cj`, `implement/dep_engine.cj` and
`implement/depot.cj`) and the
[manual](https://github.com/cangjielanguage/cangjie_docs/blob/main/docs/tools/source_en/cmd-tools/cjpm_manual.md#lock-file-description).
The source accepts an empty v1 checksum when the registry index omits it; the
manual describes stricter generation. Discovery accepts the source's format
without claiming archive verification.

The entry manifest's `[replace]` applies to reached ordinary/test dependencies,
including direct dependencies; replacement paths are relative to the entry manifest.
A dependency's own replacement table does not override it. Replacements do not
apply to the independently resolved build-script graph. Registry replacements
require one exact version, including unused replacement entries. Local and Git sources
supersede registry requirements for the same name, regardless of traversal order.
Different paths, incompatible Git declarations and path/Git mixtures are conflicts:
discovery reports the conflicting sources and keeps one deterministic selection
for recoverable analysis. Use entry `[replace]` for ordinary dependencies, or align
script dependency declarations, then run `cjpm update`. Git declarations must agree
on branch/tag presence, even for lower-priority selector fields; an unspecified
commit may share one explicit pinned commit. Checkout selection still uses
`commitId` before `branch` before `tag`.
The pinned `cjpm 1.3.0-alpha.06` confirms these rules, including a mixed build using
the replacement in ordinary sources and the original source in `build.cj`.

Source and script selections have separate module, package and import identities
(D155), even when they reach the same local path. Their contextual source inputs
share physical file text and locations; source edits update both. A physical
editor lookup prefers an ordinary membership regardless of discovery order,
otherwise the first active scoped membership. Package-driven analysis retains
each graph's transitive selection. References inspect each context and deduplicate
physical locations.
The JSON projection preserves the optional `resolutionScope` on modules.
Workspace dependency inheritance and mode-specific sections remain #516–#517.

Membership is explicit in the model. Loose-file loading has a byte budget and
prioritizes open documents; a partial result records that fact so the server does
not mistake an omitted file for an independent project (D80). A document truly
outside the model can become a lone-file module with std alone, matching
`cjc file.cj`; it does not inherit imports from an unrelated workspace (D139).
See [loose.cj](src/loose.cj) and [lone.cj](src/lone.cj). Source attachments to binary
packages acquire detached analysis contexts without becoming discovered projects
or competing import candidates (D65, D147).

## Target and SDK inputs

Source sets follow the feature chain selected by the target configuration;
non-selected files remain explicitly inactive. Do not combine all source
directories into one package or silently accept branches cjpm rejects. The chain
algorithm and its compiler observations are documented beside
[source_set.cj](src/source_set.cj); common/specific analysis belongs to loupe (D99).
In particular, preserve the serialized `features` key while keeping the Cangjie
field named `featureNames`: its source comment records the nightly that drops
the keyword-named field from macro input.

[host.cj](src/host.cj) supplies the default configuration and target naming, using
`platform` for host differences. A caller can supply a target configuration;
manifest selection must use it rather than an incidental host assumption.

[sdk.cj](src/sdk.cj) owns SDK/source lookup and injectable environment functions.
An editor's explicit option precedes environment, SDK-manager defaults and PATH
discovery. PATH symlinks must resolve to a real SDK layout: finding a compiler
launcher alone is insufficient. The selected home/source overlays are passed to
project loading so `${CANGJIE_HOME}` and std agree with that selection.
The editor's `cangjieStdxPath` overrides `CANGJIE_STDX_PATH` for project path
expansion; otherwise the process environment is preserved. stdx is loaded only
when declared in the manifest (for example, `path-option = ["${CANGJIE_STDX_PATH}"]`
in the target's `bin-dependencies`). No SDK-relative stdx path is assumed.
Changing this setting reloads projects. Missing variables are reported by path
expansion. Macro builds use the resulting binary paths from the analysis model.
Missing std sources reduce navigation, not binary analysis. Runtime discovery is
distinct from the build shell's [pinned SDK setup](../../docs/development.md#select-the-pinned-sdk).

Paths in `cj-project.json` expand a leading `~` (HOME, else USERPROFILE), `${VAR}`
and `$VAR` once through the loading environment; relative paths remain relative
to the manifest. Missing variables remain literal and are reported with the
other loading problems. This uses the same expansion as the server's path settings,
which require the result to be absolute and reject unresolved references.

## Choosing checks

Use [Development](../../docs/development.md#focused-and-full-cangjie-tests) for
commands and broader checks. [project_test.cj](src/project_test.cj) covers manifest
precedence, fallback, linked/found projects, budgets and loose-file grouping.
[lone_test.cj](src/lone_test.cj) exercises isolation of uncovered files;
[source_set_test.cj](src/source_set_test.cj) exercises feature chains, inactive
files and common/specific navigation. [sdk_test.cj](src/sdk_test.cj) uses injected
environments and temporary filesystem layouts to test lookup precedence and links.

The diagnostic and error-root gates also live here because they assemble real
projects. They are part of the full suite and need the corpora and pinned SDK
described in [analysis tests](../../docs/design/02-analysis.md#analysis-tests).
Do not bless new baseline entries as part of a documentation or loader cleanup.
Performance scenarios use the neighboring benchmarks under the shared
[measurement procedure](../../docs/procedures.md#benchmark-isolation).

The [local error-root audit](error_roots_audit.md) attributes every current
`local` root to its cause. Inline baseline explanations survive count updates;
new local groups need an explanation before the gate passes. Attribution does
not relax the requirement to eliminate the underlying gaps before Cleanup.
