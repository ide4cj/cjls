# ADR-0026: Third-party test suites are fetched into `.corpora/` at a pinned commit, not vendored

Status: accepted, 2026-09-28. Supersedes D24's vendoring of JSONTestSuite.
Amends ADR-0024: the suite fetched

## Context

- fjson is held to JSONTestSuite (D24, 341 files), ftoml to toml-test (D25, 1010): another project's files, byte for byte, CRs and invalid UTF-8 included. Vendored, they are most of any change that touches them, stay in the history for good, and are kept identical to upstream by hand.
- A git submodule pins a commit but checks out the whole repository — JSONTestSuite's is 63 MB, its parsers — and the superproject's `.gitattributes` does not reach it: a Windows checkout with `core.autocrlf` rewrites the CRs the suites test.

## Decision

- **`tests/corpora/fetch.py` fetches every suite into `.corpora/<name>`** (ignored), each at the commit it names: a partial clone of that commit alone, a sparse checkout of the files the tests read (under 1 MB downloaded for both). The commit is the checksum. Line endings are never converted, whatever git's configuration: the fetch sets `core.autocrlf=false` and `* -text` in the suite's own repository. A suite already at its commit is not fetched again.
- **A test reading a suite fails without it**, naming the command to run — it never passes having checked nothing. The suites are read on first use, never by a global's initializer, so only the cases that use them fail.
- **The `pre-push` hook and CI run the fetch before `cjpm test`.** Moving to a newer suite is its commit changed in the script.

## Consequences

- `cjpm test` on a fresh clone needs the fetch once, and the network for it.
- The compiler's test suite (`CJSYNTAX_CORPUS`) stays outside: it is read only when named, never by `cjpm test`.
