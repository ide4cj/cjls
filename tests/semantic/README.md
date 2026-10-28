# Negative semantic compiler oracle

This is the negative half of [#528](https://github.com/ide4cj/cjls/issues/528),
complementing the accepted-source corpus gate (#114). It retains all 92 isolated
programs from the 2026-10-28 [audit](https://github.com/ide4cj/cjls/issues/527),
adds a corrected counterpart to every rejected program, and exercises three
cross-file declaration changes. Fixtures are JSON strings so malformed Cangjie
stays verbatim and the repository formatter does not rewrite diagnostic offsets.
The harness needs Python 3.10+ and no Python packages.

## Run from a clean checkout

First select the pinned SDK and matching stdx using
[Development](../../docs/development.md#select-the-pinned-sdk), then run from the
repository root:

```bash
cjpm build
python3 -m unittest discover -s tests/semantic -p '*_test.py'
python3 tests/semantic/oracle.py --sdk "$CANGJIE_HOME" --output target/semantic-oracle
```

PowerShell uses `python` and `--sdk "$env:CANGJIE_HOME"`. The default server is
`target/release/bin/cjls` (`cjls.exe` on Windows); `--server` selects another build.
Build that binary from the recorded checkout revision before running. The report
identifies the checkout revision, local changes and binary SHA-256; a supplied
binary's commit cannot be inferred from its filename. CI uses the same commit's
Build artifact. Use a new output directory for each run: existing evidence is
never overwritten. `--case return_wrong_type` selects a focused fixture; repeat
`--case` to select more. A selected run is not the full release matrix.

The compiler is taken directly from the explicit SDK root (or `CANGJIE_HOME`),
and its version must match `.cangjie-version`. Every compilation uses
`--diagnostic-format noColor -Woff unused --output-type staticlib`, with one
isolated package per fixture/phase. Error and warning headlines and their
multiplicity must match the compiler contract, and rejection requires exit 1.
A crash, unrelated parser error or warning-only exit is not success.

The server completes workspace loading before documents are opened. Each negative
fixture runs through broken → corrected → restored input and fresh pull reports.
For the cross-file cases, only `declarations.cj` changes during correction and
restoration: the requesting document receives no `didChange`, so an invalidation
bug cannot hide behind a redundant document update. Both files' diagnostics are
checked. Compiler and LSP calls have a 30-second deadline (`--timeout` overrides
it). On POSIX, failure kills the isolated process group, including children after
the parent exits. On Windows, `taskkill /T` kills a still-running parent's tree;
Windows cannot recover an already-exited parent's orphan tree through this API.
Compiler output goes directly to files, so an orphan cannot keep a compiler pipe
open indefinitely. A regression test verifies live-parent child termination by
reacquiring the child's OS file lock and confirms logs survive a timeout. CI also
bounds the entire job. Source files, compiler command/stdout/stderr, full LSP wire traffic,
server stderr, SDK version/target, platform and revision metadata remain in the
output directory, including on a failed run.

## Expectations and known differences

`fixtures.json` owns source text, compiler error/warning categories and the desired
LSP diagnostic message, severity and exact UTF-16 range `[line, column, line,
column]`. ASCII fixtures make compiler columns and UTF-16 columns comparable.
Missing checks start with the compiler's primary message/range, as the linked
implementation issues request. Compiler recovery cascades are retained in the
compiler contract, but only the semantic root belongs in the desired LSP report.
The malformed `open final` syntax control retains its existing exact parser
reports; it is not evidence of a missing modifier check. Float32 overflow is an
accepted, warning-only compiler control: this error oracle requires the existing
empty LSP result and must never upgrade that warning to an error.

`baseline.json` records **only discrepancies**, attributed to their owning issue:
missing desired diagnostics and extra actual diagnostics. Comparison is a
multiset operation, preserving multiplicity; order is irrelevant. There is no
count threshold and no automatic baseline-update option. An added error, changed
range/category/severity, removed duplicate or newly implemented diagnostic fails.
When implementing a linked check, review the expectation against the pinned
compiler, remove the corresponding baseline discrepancy and retain the fixture
and corrected control. Do not bless new differences to make a run green.

The offline tests deliberately remove and duplicate a currently correct
`return_wrong_type` diagnostic and require both regressions to fail. They also
check wrong ranges/categories/severity, stale baseline entries and warning
classification. These are harness tests; they do not replace the actual server
matrix or focused analysis tests accompanying semantic implementations.

## CI and applicability

The offline harness tests run in routine CI's scripts job. The **Semantic oracle**
job runs the complete compiler/LSP matrix on Linux, macOS and Windows, after the
built binary is available, and uploads `report.json`, sources and logs even on
failure. The release workflow calls this CI workflow before publication, so the
same matrix runs before an announced release. Existing Cangjie valid-source,
macro-expansion and e2e gates are unchanged. As with the other macOS checks, its
SDK GC failure remains temporarily non-blocking under #466; inspect its artifact
before claiming platform coverage.

[#66](https://github.com/ide4cj/cjls/issues/66) has not decided new default tiers:
this adds a named differential tier without changing what `cjpm test` runs.
The supported SDK matrix is currently the repository pin. The SDK window in
[#306](https://github.com/ide4cj/cjls/issues/306) remains pending; extend the explicit
version contracts when that window exists, rather than silently accepting another
compiler's output. No fixture currently requires a platform skip. Future
platform-specific cases must declare `platforms` and a `skip_reason`; skips are
recorded per case with SDK/platform in `report.json` and printed in the summary.
A green report with skips establishes only its recorded applicability.
