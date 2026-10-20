---
name: change-coverage
description: Generate fresh cjls coverage and inspect added or modified source files when asked about untested changes or reviewing test evidence.
---

Run from the worktree root. Load the pinned SDK and fetch corpora as described in
[Development](../../../docs/development.md#coverage); `cjpm`, `cjcov` and Python 3
must be available in this process. Keep the instrumented cache in `target/cov`.

1. Run `python3 scripts/change_coverage.py run`. This uses CI's test exclusions
   (`--exclude-tags gate`), generates HTML/JSON, and records input provenance only
   after successful tests and generation with unchanged inputs.
2. Run `python3 scripts/change_coverage.py report --base origin/master`. Choose an
   existing local base ref; the script does not fetch. It includes working edits
   and new files, reuses CI's coverage selection, and distinguishes excluded files
   from missing report entries. Missing or stale artifacts fail the command.
3. Read the added/changed lines in `coverage/index.html` and its per-file pages.
   Report each included file's `hit/total` and describe uncovered behavior, such
   as an error branch. A hit count alone cannot establish that a case is tested.
   Identify cases needing e2e coverage separately (C7).

`--base` selects files relative to the merge-base; it does **not** compare coverage
with the base revision. If a before/after comparison is requested, generate a
separate report in each revision's worktree using the same SDK and test selection.
Do not present one report as a baseline comparison.

The input fingerprint covers tracked/untracked Cangjie files, TOML manifests,
SDK pins and corpus-fetch pins, and binds the report's content. It does not prove
that an installed SDK or fetched corpus is intact. Keep those pinned, and rerun
after changing the environment. Raw `cjcov` output lacks this provenance: use the
`run` command for changed-file reporting. Outputs remain untracked under
`coverage/`; failed tests leave no valid provenance.
