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

Membership is explicit in the model. Loose-file loading has a byte budget and
prioritizes open documents; a partial result records that fact so the server does
not mistake an omitted file for an independent project (D80). A document truly
outside the model can become a lone-file module with std alone, matching
`cjc file.cj`; it does not inherit imports from an unrelated workspace (D139).
See [loose.cj](src/loose.cj) and [lone.cj](src/lone.cj). Source attachments to binary
packages are navigation destinations, not another resolution scope (D65).

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
