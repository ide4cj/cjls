# ADR-0028: CI stamps a package's files with one mtime, made of the whole directory

Status: accepted, 2026-09-29

## Context

D27 gives every tracked file an mtime made of a hash of its own content before CI restores `target`. The first PR after it that added a package (#64: `cjls.lsp_ext`, imported by `cjls.handlers`) failed on all three platforms with `can not find package 'cjls.lsp_ext'`, and built from a clean `target`. Measured with cjpm 1.3.0-alpha.05:

- **A package's imports are read again only when the newest mtime among its files changed** (`read~<package>` in `incremental-cache.json`). A file edited or added whose mtime is not the newest leaves the old import graph in place, with no warning. cjpm then compiles the package, because it compares every file's mtime for the compile, alongside the packages it now imports and not after them.
- A checkout by hand never hits this: a file it writes gets the time of the checkout, which is the newest. A stamp made of the file's content is any time from 2001 to 2009, and for a package of *n* files it is the newest only once in *n* times.

## Decision

- **One mtime per directory**: `stamp.py` hashes the names and contents of the tracked files directly in a directory (a package's sources) and gives all of them that mtime. Any file of a package edited, added or removed gives every file a new mtime, the newest included. Unchanged packages keep theirs, so a restored build stays incremental (0 packages compiled for an unchanged commit; 3 for #64).
- Not taken: the time of the last commit to touch a file, which a checkout of depth 1 does not have and a PR on an older master would make older, not different; "now" for the files that differ from the cached commit, which compiles the last master commit's packages again in every PR.

## Consequences

- A package is compiled again when anything in its directory changes, a non-source file included.
- If cjpm reads imports when any of a package's files changed, this ADR and the per-directory hash can go; D27's own `stamp.py` goes when cjpm learns content hashes.
