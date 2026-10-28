# Negative semantic compiler oracle

This is the negative half of [#528](https://github.com/ide4cj/cjls/issues/528),
complementing the accepted-source corpus gate (#114). It retains all 92 isolated
programs from the 2026-10-28 [audit](https://github.com/ide4cj/cjls/issues/527),
corrected counterparts, and three cross-file declaration checks. Two additional
scenarios exercise file lifecycle and a dependency between packages.
The harness needs Python 3.10+ and no Python packages.

## Run from a clean checkout

Select the pinned SDK and matching stdx using
[Development](../../docs/development.md#select-the-pinned-sdk), then run:

```bash
cjpm build
python3 -m unittest discover -s tests/semantic -p '*_test.py'
python3 tests/semantic/oracle.py --sdk "$CANGJIE_HOME" --output target/semantic-oracle
```

PowerShell uses `python` and `--sdk "$env:CANGJIE_HOME"`. The default server is
`target/release/bin/cjls` (`cjls.exe` on Windows); `--server` selects another build.
Build that binary from the recorded checkout revision before running. The report
records the revision, local changes, server SHA-256 and scenario/baseline hashes;
a supplied binary's commit cannot be inferred from its filename. CI uses the
same commit's Build artifact. Use a new output directory for each run: existing
evidence is never overwritten. `--case return_wrong_type` selects one scenario;
repeat `--case` to select more. A selected run is not the full release matrix.

## Text scenarios

Scenarios have two entry forms. A small test keeps runner directives in its
native `.cj` header; a multifile/editing scenario uses a separate `.info`
descriptor referring to ordinary `.cj` sources. Both load into the same package,
file, step and diagnostic model. No suite configuration file is needed.

The format takes comment directives, auxiliary sources and expected compiler
failures from
[cangjie_test_framework](https://gitcode.com/Cangjie/cangjie_test_framework),
and explicit source ranges from the project's `loupe.fixture` approach. This is
a project-specific driver rather than a Maple/lit-compatible runner. Authors do
not need shell pipelines or raw JSON-RPC transcripts.

A complete single-file control, `example.cj`, can contain:

```cangjie
// ISSUE: 528
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
package audit
func f(): Int64 { 1 }
```

`%f` means the body of this `.cj` entry, following its leading comments/blank
lines. Leading block comments such as license headers are also supported. All
runner directives belong in the header, before Cangjie source. Headers can
reference additional `.cj` files for corrections or declarations; see
[return_wrong_type.cj](cases/return_wrong_type.cj).

Alternatively, `example.info` can describe the same control:

```text
// ISSUE: 528
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj inputs/main.cj
```

Here `inputs/main.cj` contains the ordinary `package audit` and function shown
above. References are relative to the descriptor's directory. Source files are
always native `.cj`; `.info` holds directives/comments only. Auxiliary sources
without runner headers are not independently discovered as tests. The entry's
relative path without its extension is its stable ID; defining the same ID in
both forms is an error.

| Directive | Meaning |
|---|---|
| `ISSUE: number` | Owning issue, once before the steps |
| `PACKAGE: name directory [depends=a,b]` | One package project, with sources in `directory/src`; declare dependencies before consumers |
| `STEP: name` | Inherit the preceding files and LSP expectations; declare fresh compiler contracts |
| `STEP: name FROM earlier` | Restore that earlier snapshot, expectations and compiler contracts |
| `CJC: package clean` | Require exit 0 with no compiler diagnostics |
| `CJC: package error: message` | Expected compiler headline; repeat for additional errors or warnings |
| `CJC: package warning: message` | Warning headline; warning-only compilation must exit 0 |
| `SOURCE: workspace/path.cj input/path.cj` | Replace/create a workspace file and its LSP expectations using a native fixture source |
| `SOURCE: workspace/path.cj %f` | Use this `.cj` entry's body; unavailable in `.info` |
| `EXPECT: id marker error: message` | One exact LSP error in the preceding SOURCE, at its named marker; `warning` is also supported |
| `DELETE-FILE: path.cj` | Remove an existing file and its expectations |
| `PLATFORMS: linux darwin win32` | Optional applicability, before steps |
| `SKIP-REASON: explanation` | Required when applicability is restricted |

A SOURCE's expectations end at the next source, compiler, deletion or step
directive. Unrecognized uppercase directives fail rather than silently dropping
a check. Fixture references must stay inside the descriptor's directory and end
in `.cj`. Missing inputs fail validation before any processes start.

Range annotations are legal Cangjie block comments:

```cangjie
func f(): Int64 { return /*@result*/"wrong"/*@/result*/ }
```

The corresponding header/descriptor expectation is:

```text
// EXPECT: return_type result error: mismatched types: expected 'Int64', found 'String'
```

Reserved markers `/*@name*/.../*@/name*/` are removed without adding whitespace
before either consumer receives the source. They define half-open ranges in
that resulting source, including empty, multiline and overlapping spans.
Coordinates are computed in UTF-16, including non-BMP characters. Marker names
are unique within a source; diagnostic IDs are unique within a step. Several
diagnostics can reference one marker. Replacing annotations without changing
the resulting text does not generate a document edit.

Native `.cj` files retain editor language recognition and highlighting. Repository
format checks target `build.cj` and `modules`, excluding these fixtures' deliberate
syntax errors and whitespace. The existing accepted-source gates load workspace
member packages, so fixture inputs outside those members do not enter their
corpus. Sources remain unescaped and readable; headers and range annotations are
removed only in the generated oracle workspace.

Every normal step needs an explicit compiler contract for every package. A
scenario with a rejected compilation also needs a clean compiler/LSP control.
There is no hardcoded number of files or editing steps. One package per project
is currently supported, with non-overlapping project directories and explicit
path dependencies. Arbitrary build commands, macro build pipelines and nested
subpackages are outside this initial format.
See [package_dependency.info](cases/package_dependency.info) for two-file package
compilation and downstream invalidation, and
[workspace_lifecycle.info](cases/workspace_lifecycle.info) for creation, correction,
deletion and multiple edits.

## Compiler and server execution

The compiler comes directly from `--sdk` or `CANGJIE_HOME`; its version must match
`.cangjie-version`. All files of a declared package are compiled together with
`cjc -p`, `--diagnostic-format noColor -Woff unused --output-type staticlib`.
Dependencies are built first and supplied through their `.cjo`/static libraries.
Each distinct step has an isolated source snapshot and build outputs. Exact
compiler headlines, their order/multiplicity and exit status must match. A crash
or unrelated parser error cannot count as an expected semantic rejection.
Restoring an identical snapshot reuses its recorded compiler result, identified
by `compiler_reused_from` in the report.

Each scenario starts a fresh server and generated cjpm workspace. After workspace
loading finishes, the driver opens the initial documents and keeps the session
for every step. Only changed source receives `didChange`; replacing annotations
without changing the resulting source sends no edit. Creation/deletion also
updates disk and sends document/watched-file lifecycle notifications. Every
remaining file receives a fresh diagnostic pull, and the complete workspace's
report is compared, including diagnostics in declaration/dependency files.

The three original cross-file checks edit only `declarations.cj` during correction
and restoration. The requesting file receives no redundant `didChange`, so it
cannot hide an invalidation bug. The package-dependency scenario also changes a
provider's return type while leaving its consumer's source unchanged.

Compiler and LSP calls have a 30-second deadline (`--timeout` overrides it).
On POSIX, failure kills the isolated process group, including children after the
parent exits. On Windows, `taskkill /T` kills a still-running parent's tree;
already-exited parents' orphan trees cannot be recovered through this API.
Compiler output goes directly to files so an orphan cannot hold output pipes
open indefinitely. Tests verify live-parent child termination with an OS lock
and confirm logs survive a timeout. CI bounds the entire job.

The output retains schema-2 `report.json`, per-scenario server wire/stderr,
per-step compiler source snapshots, commands, stdout/stderr and SDK/platform/
revision metadata, including failures. A failed scenario is recorded without
preventing later scenarios from running. Invalid scenarios fail validation before
launching the compiler/server and still produce a failure report.

## Expectations and known differences

Scenario expectations describe the desired LSP message, severity, source file,
range and multiplicity. Compiler and LSP expectations are separate: compiler
recovery cascades remain in the compiler contract, while the desired server
report contains semantic roots. The malformed `open final` syntax control retains
its exact parser diagnostics. Float32 overflow remains a warning-only compiler
control with an empty desired LSP report; it must not become an LSP error.

`baseline.json` contains **only known discrepancies**, attributed to their issue
and explicitly named steps. `missing` lists diagnostic IDs from those steps;
messages and ranges are resolved from the scenario, not duplicated. `extra`
contains exact extra diagnostics, including source file and UTF-16 range. IDs and
step references are validated before execution. Baselines never suppress an
entire failing test.

Comparison is a multiset operation: order is irrelevant, duplicates matter. New
differences and unexpected fixes both fail. There is no count threshold or
automatic baseline-update option. When implementing a check, review its
expectation against the pinned compiler, remove its baseline discrepancy and
retain the rejected/corrected example. Do not bless new differences for a green
run. Offline tests plant missing/duplicate diagnostics and check stale baseline
references, changed message/severity/range, source mapping and edit notifications.

## CI and applicability

The offline tests run in routine CI's scripts job. The **Semantic oracle** job
runs the complete compiler/LSP matrix on Linux, macOS and Windows after Build and
uploads evidence even on failure. The release workflow invokes this CI before
publication. The existing #466 macOS SDK GC exception remains temporarily
non-blocking; inspect its artifacts before claiming coverage there.

[#66](https://github.com/ide4cj/cjls/issues/66) has not decided new default tiers:
this adds a named differential tier without changing `cjpm test` selection.
Only the repository-pinned SDK is currently supported; the SDK window in
[#306](https://github.com/ide4cj/cjls/issues/306) remains pending. Extend explicit
compiler contracts when that window exists. No current scenario needs a platform
skip. Future skips require a reason and are recorded with SDK/platform; a green
report with skips establishes only its recorded applicability.
