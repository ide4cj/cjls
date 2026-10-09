# ADR-0067: Loose files without a package line, two or more of which declare main, are a program per main, each with the main-less files of its directory

Status: accepted, 2026-10-09
Amends ADR-0033: loose files without a `package` line are one `default` only with one `main` at most

## Context

- D33 put every loose file without a `package` line into one package `default`: right for a program over files compiled together (`cjc a.cj b.cj`), wrong for a directory of programs compiled one by one, as cjc's test suite is (`// EXEC: %cjc %f`). In `cangjie_test`'s `ShiftOverflowUInt8Int16` each of 12 files has a `main` and the same top-level names: go to definition on one answered 12 locations, one per file (#211).
- cjc (1.3.0-alpha.20261002) on a directory `a.cj`, `b.cj` (a `main` and `let my_const` each) and `util.cj` (a `helper` both call): `cjc a.cj b.cj util.cj` and `cjc -p .` fail (`redefinition of declaration 'my_const'`, `function 'main' has overload conflicts`); `cjc a.cj` alone fails (`undeclared identifier 'helper'`); `cjc a.cj util.cj` compiles and runs. Two `main`s are never one program, and a helper is compiled into each program that uses it. `func main` is a `main` to cjc too, which reports the `func`.
- A `main` is a top-level item anywhere in the file, not in its first 4 KiB as the `package` line is. A file is read whole by the load anyway (D31's budget counts its size already); what the walk adds is reading it a second time, from the page cache, and finding the `main`.
- R1's detached files: a file of no crate is a crate of its own; a file in several crates is analyzed in the first.

## Decision

- **Two or more `main`s among the files without a `package` line make a program of each** (the issue's rule): a module `default` rooted at the file (modules share a root or a name, never both: D33), its package `default` in the file's directory. With one `main` or none the files stay one `default`, as D33 had them.
- **A file without `main` goes into each program of its own directory** (as `cjc a.cj util.cj`), rather than a `default` of its own, which no program would see, its helpers unresolved in every test. A directory's, not the root's: a root of 90 000 programs with helpers of their own here and there would put every helper into every program. The files without `main` of a directory with no program stay the `default` of the root. A layout this splits wrongly is described by a `cj-project.json`.
- **A file in several packages is allowed by `loupe.db`**: a `Package` holds `FileId`s, the files of the project are read once (`ProjectModel.files`), and `packageOfFile` answers the first package listing the file, as R1 analyzes a file in the first of its crates; from a helper, names resolve in the first program of its directory.
- **`main` is found by `cjsyntax`'s lexer** (`declaresMain`), not the parser and not a scan of our own: the keyword `main` outside every bracket and string. The lexer follows cjc's for strings, their interpolations, raw strings and nested comments, which a scan would have to again; the parser builds a tree the walk would throw away. Only a file without a `package` line, holding the bytes `main`, is lexed. `project_model` depends on `cjsyntax` for it.

## Consequences

- A directory of programs answers go to definition in each file's own program; a program over files with one `main` is one `default`, as before.
- Whether a file declares `main` is read when the project is found: adding or removing one in an editor changes nothing until a `.cj` comes or goes, as for a `package` line edited.
- The walk reads the whole of each file without a `package` line holding `main`, and lexes it; the rest still stops at 4 KiB.
