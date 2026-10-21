# Development

This guide is the shared entry point for humans and agents building and checking
cjls. Run commands from the repository/worktree root. POSIX examples use **Bash**;
start `bash` first if your interactive shell is fish. Keep wildcard test filters
quoted. Windows examples use PowerShell unless specified otherwise.

## Set up a checkout

A separate clone or Git worktree provides independent build directories and a
corpus checkout for parallel work. Do not concurrently run commands that write
the same build cache or share a mutable `target/` between checkouts. The SDK
installation may be shared.

When using worktrees, check for uncommitted/untracked work and active
users/processes before removing one. Git index timestamps alone do not
establish that it is idle.

### Prerequisites

- Git and Python 3 (the repository scripts and POSIX compiler shim use Python).
- The SDK nightly in [`.cangjie-version`](../.cangjie-version), with matching
  static stdx, verified against [`.cangjie-sha256`](../.cangjie-sha256).
- On Linux, LLVM's libc++ and libc++abi development libraries for static linking
  (Debian/Ubuntu packages `libc++-dev` and `libc++abi-dev`; use your distro's names).
- [uv](https://docs.astral.sh/uv/) for e2e/performance Python dependencies;
  [cocogitto](https://docs.cocogitto.io/) (`cog`) for commit/PR-title checks.
- GitHub CLI (`gh`) for GitHub tasks and allocating ADR numbers across open PRs.

CI supports Linux x64, macOS arm64 and Windows x64; its installer and job matrix
are in [setup-cangjie](../.github/actions/setup-cangjie/setup.py) and
[ci.yml](../.github/workflows/ci.yml). A different platform needs toolchain and
manifest support before the examples can be assumed to work.

### Select the pinned SDK

An SDK manager is optional. If using one, select the repository's exact nightly,
ensure matching stdx is installed, and expose `CANGJIE_HOME` as well as executables.
Finding `cjpm` on PATH alone does not establish that the manifest can find stdx.

The repository installer offers the same SDK/stdx layout as CI. In Bash:

```bash
sdk_tag=$(cat .cangjie-version)
sdk_dir="$HOME/.cache/cjls-sdk/$sdk_tag"
python3 .github/actions/setup-cangjie/setup.py "$sdk_tag" "$sdk_dir"
source "$sdk_dir/cangjie/envsetup.sh"
export PATH="$PWD/.github/actions/setup-cangjie/shim:$PATH"
cjc --version
cjpm --version
```

The installer prints environment exports; sourcing the installed SDK's
`envsetup.sh` loads them into this shell. The extra PATH entry uses CI's compiler
shim to close inherited descriptors before launching cjc (#342). It is for POSIX
hosts. In PowerShell:

```powershell
$sdkTag = (Get-Content .cangjie-version).Trim()
$sdkDir = Join-Path $env:LOCALAPPDATA "cjls-sdk/$sdkTag"
python .github/actions/setup-cangjie/setup.py $sdkTag $sdkDir
. (Join-Path $sdkDir 'cangjie/envsetup.ps1')
cjc --version
cjpm --version
```

Confirm the compiler version matches the pin. `CANGJIE_HOME` must identify this
SDK, with stdx under `third_party/stdx/<os>_<arch>_cjnative/static/stdx`, as the
root [manifest](../cjpm.toml) specifies. Exported variables belong to the current
shell: a new terminal or agent command process must load the environment again,
or inherit it from its launcher. No Claude session hook is required.

To enable repository Git hooks once per clone:

```bash
git config core.hooksPath .githooks
```

`commit-msg` requires `cog`; `pre-push` checks formatting, fetches corpora and
runs the full Cangjie suite, which builds the tested packages. They are [plain scripts](../.githooks).

## Build and run

```bash
cjpm build
target/release/bin/cjls --config-schema
```

The server is `target/release/bin/cjls` (`cjls.exe` on Windows). `cjpm run` starts
it over stdio; it waits for LSP traffic. The standalone commands are useful for
inspection:

| Command after building | Purpose |
|---|---|
| `target/release/bin/cjls project --dir <dir>` | Print the detected project as `cj-project.json` |
| `target/release/bin/cjls fmt --check .` | Report source files that need formatting; exit nonzero if any |
| `target/release/bin/cjls fmt <path>...` | Format selected files in place |
| `target/release/bin/cjls fetch-src --dir <dir>` | Download the detected SDK's std sources for navigation |
| `target/release/bin/cjls --config-schema` | Print the settings JSON Schema |

The Cangjie runtime is linked statically and the server runs without an SDK
environment; generators still need the SDK because they invoke `cjfmt`. Linux
executables still use system glibc and libstdc++. Release builds use Ubuntu 22.04
and check the executable in a clean Ubuntu 22.04 container with `libstdc++6`
installed; a local build on a newer system may require newer system libraries.
To run the same compatibility check locally (requires Docker):

```bash
bash .github/scripts/check-linux-compat.sh target/release/bin/cjls
```

## Choose checks for a change

| Change | Start with | Broader verification |
|---|---|---|
| Documentation only | Local links, command/source consistency, `python3 scripts/docs.py check` | Docs-script tests when changing that tooling |
| Library or analysis behavior | A focused unit/fixture regression test | Full Cangjie suite and formatting |
| Routing, lifecycle, threading or wire behavior | Unit tests of the responsible layer | Relevant e2e tests with the built binary |
| Grammar or generated code | Affected module's generation/conformance tests | Full suite and formatting; corpus/oracle checks where applicable |
| Performance-sensitive behavior | Correctness test, then `@Bench` | Relevant server perf scenarios and query-count thresholds |

Test selection here describes existing behavior. Test tiers/default corpus
selection are being reconsidered in [#66](https://github.com/ide4cj/cjls/issues/66).
Do not treat a focused run as the full suite or silently exclude gates from it.

### Focused and full Cangjie tests

For a small change, start with the relevant test class. Example:

```bash
cjpm test --no-progress --target-dir target/test '--filter=ConnectionCloseTest.*'
```

The filter is `<TestClass>.<testCase>` with `*` wildcards. Cases needing corpora
require the fetch below first. Before a full suite on a fresh worktree, fetch the
pinned external suites:

```bash
python3 tests/corpora/fetch.py
cjpm test --no-progress --timeout-each=2m --target-dir target/test
```

The fetch populates `.corpora/` with the external sources pinned in the script.
It is needed once per worktree and when a pin changes; missing corpora fail the
tests that need them. Fetching needs network access. Full test dependencies are
recorded by [fetch.py](../tests/corpora/fetch.py).

Keep build output in `target/release`, tests in `target/test`: build and test in
the same target directory invalidate each other's cache (D27). `--no-progress`
avoids a known progress-reporter stall; CI's timeout bounds a hung test, not a
timing assertion in test code. Tests use the manifest's 2 GB heap setting.

Unit tests sit beside code as `*_test.cj`. Analysis tests use
[`loupe.fixture`](../modules/loupe/src/fixture) (D43). To update expected output
intentionally, in Bash:

```bash
UPDATE_EXPECT=1 cjpm test --no-progress --target-dir target/test '--filter=<Class>.<case>'
```

Read the resulting diff. Diagnostics and error-root baselines are checks, not
values to bless automatically: new roots require attribution to a known gap and
idiomatic code stays idiomatic (D108, D121). See
[analysis rules](design/02-analysis.md) and
[testing conventions](design/03-conventions.md) for the contract. The full suite
also checks analysis after SDK macro expansion; see the
[macro host notes](../modules/macro_host/CLAUDE.md) for that gate.

### Formatting and documentation

```bash
cjpm build
target/release/bin/cjls fmt --check .
python3 scripts/docs.py check
```

For changes to `scripts/docs.py`, also run:

```bash
python3 -m unittest discover -s scripts -p '*_test.py'
```

The docs check validates ADR headers/IDs and duplicate rule IDs; it is not a
Markdown link checker or proof that prose matches code. Inspect links and affected
examples separately. Documentation-only edits need no Cangjie rebuild unless
validating a command or code example requires it.

### Coverage

Use a separate instrumented cache (D49, D51, D120):

```bash
python3 tests/corpora/fetch.py
cjpm test --coverage -g --no-progress --timeout-each=2m --exclude-tags gate --target-dir target/cov
cjcov -r . -s modules -x -j --html-details -o coverage
python3 .github/scripts/coverage.py coverage/coverage.json
```

`-g` disables release optimization; never benchmark that build. Coverage excludes
the `gate`-tagged corpus checks; ordinary full tests retain them.
The [coverage reporter](../.github/scripts/coverage.py) defines exclusions for
generated, macro and test-support code. Its percentage is the project's measure.
Read uncovered changed lines in `coverage/index.html`. Do not infer correctness
from a percentage. `coverage/`, `cov_output/` and `*.gcda` are untracked outputs.

### End-to-end tests

```bash
cjpm build
python3 tests/corpora/fetch.py
uv run --project tests/e2e --locked pytest tests/e2e
```

These drive the real binary over stdio with editor capabilities. `CJLS_BIN`
overrides the executable; `CJLS_E2E_SDK` overrides the SDK used by SDK-dependent
cases (otherwise `CANGJIE_HOME`). Keep the SDK and std corpus available: those
cases can skip when missing; review skips before claiming full coverage.
Editor-client tests live in their own repositories; paired branch conventions
are in D32 and [the org guide](https://github.com/ide4cj/.github/blob/main/CONTRIBUTING.md).

### Fuzzing and performance

In Bash, with the corpora already fetched:

```bash
cjHeapSize=2GB cjpm test --no-progress --fuzz --target-dir target/fuzz '--filter=*CoverageGuided*.*'
cjpm bench '--filter=VfsPathBench.*'
```

Use `std.unittest`'s `Arbitrary`/`Shrink` for random inputs, and `@Bench` in
`*_bench_test.cj` for measurements (C7, C10). One benchmark filter per invocation;
only the last is used if repeated. Benchmark candidates separately, record SDK,
platform and load, and quote timings only from a quiet machine. No benchmark
is run merely to verify a documentation edit.

Server performance uses [tests/perf](../tests/perf):

```bash
uv run --project tests/perf --locked cjls-perf run --server cjls -o perf.json
uv run --project tests/perf --locked cjls-perf check perf.json
uv run --project tests/perf --locked cjls-perf compare before.json perf.json
```

Create `before.json` from the baseline revision before comparison. Scenario/server
definitions are in that project; some require std's corpus sources. Query counts
are gated by `thresholds.toml`; noisy CI timings are reports, not thresholds (D81).
Benchmark locking and machine-specific helpers remain a migration task in #455;
there is no checked-in portable replacement for the old private `quiet-run.sh` yet.

## Generated code

Edit inputs and regenerate; never patch generated output to fix a behavior.
Build generators before changing/removing output so a broken generated package
does not prevent running the generator. Read the relevant module notes first.

| Output | Inputs and procedure |
|---|---|
| `modules/cjsyntax/src/syntax_kind.cj`, `src/ast/nodes.cj` | `syntax_kinds.toml`, `cangjie.ungram`; [cjsyntax notes](../modules/cjsyntax/CLAUDE.md) |
| `modules/cjls/src/lsp_types/` | `metaModel.json`, `lsp_codegen.toml`; [lsp_codegen notes](../modules/lsp_codegen/CLAUDE.md) |
| `.cjo` and macro protocol flatbuffer views | schemas/configs; [cjo](../modules/cjo/CLAUDE.md), [macro_server](../modules/macro_server/CLAUDE.md), [fbs_codegen](../modules/fbs_codegen/CLAUDE.md) |

Generator tests compare checked-in output; syntax conformance checks trees
against the ungrammar. The compiler corpus/oracle harness is not fully checked
in yet (#114); do not claim it ran from the normal suite. Generator CLI/check
mode and formatting changes are tracked separately in #112 and #359.

## Toolchain constraints

Preserve these existing constraints until evidence on the pinned SDK justifies
a change. The future versioned SDK registry/probes are tracked in #332.

| Constraint | Reason / reference |
|---|---|
| `cjls` links `--static` | The server must run without SDK env |
| Preserve the Linux release baseline and runtime-container check | System glibc/libstdc++ remain dynamic; C32, D142 |
| Per-target release `-O2`, except `platform`'s `-O1` | `-g` builds must stay unoptimized; CJMP at `-O2` breaks linking (D51, D102) |
| Keep module/root `-Woff unused`; other warnings remain enabled | Existing generated/macro warnings; `-m` reads module settings (D97) |
| No LTO, `-dead_strip`, or `std.ast` reachable from runtime packages | Runtime failures or linking the compiler parser into the server (D20) |
| Read `list[i]` before removing a tuple/struct element | Known `-O2` miscompile of `list.remove(at: i)[1]` |
| Blocking foreign functions are neither `@FastNative` nor named as known libc functions | Otherwise the GC can stall (C5, D13) |

Macros generate unqualified names: their consumers must import the names used
by expansions. Enum constructors leak into package scope; avoid collisions
(e.g. `As<Member>` union variants). Macro-generated statics must not initialize
through user code; package initialization order is undefined. Check changes by
building a consumer, not only the macro package. See
[stdxx notes](../modules/stdxx/CLAUDE.md) and affected module notes.

### Troubleshooting

| Symptom | Check first |
|---|---|
| `cjpm` found but stdx or runtime library missing | SDK selection, `CANGJIE_HOME`, stdx layout and SDK environment in this process |
| Compiler processes hang | POSIX shim is ahead of the real cjc on PATH (#342) |
| Tests fail naming a missing corpus | Run `tests/corpora/fetch.py` in this worktree |
| Source changes appear ignored | cjpm tracks mtimes, not content; `cjpm clean` is needed after restoring old mtimes |
| SDK change uses stale objects | Root `build.cj` detects compiler version changes (D27); check selected compiler |

`*.cj.macrocall` and `lib-macro_*.dylib` beside sources are build output: do not edit
or commit them. Clean only the current worktree's outputs when needed.

## Prepare a review

Use Conventional Commits (`type(scope): subject`). `cog` checks commits and PR
titles because PRs are squash-merged. Keep the change, its regression tests and
invalidated docs together. Explain the problem, resulting behavior, key design
choice, verification and remaining limitations. Explain non-obvious algorithms
and tradeoffs so a reviewer can assess the change.

Update docs for a new constraint or real decision; do not repeat API inventories.
See [when to write docs](README.md#when-a-change-writes-here). Allocate an ADR with
`python3 scripts/docs.py new-adr <slug> "<decision>"`; do not edit the generated
ADR index. Open questions live in issues labeled `question`.

CI runs builds/tests on its supported platforms, format/docs/commit checks,
fuzzing, e2e and performance; [coverage](../.github/workflows/coverage.yml) is a
separate workflow (D49). Weekly and nightly releases are maintained by the
[release workflows](../.github/workflows); `nightly-build` is updated in place,
never deleted (D39). A toolchain bump updates both pins, the corpus source commit
and schema inputs as required; see D62/D65 and the affected generator notes.

The [documentation migration plan](https://github.com/ide4cj/cjls/issues/455)
tracks remaining module-note, SDK-knowledge and automation work. Historical ADRs
remain the record of why choices were made; current rules are in `docs/design/`.
