# ADR-0104: The workspace's macro packages are built by cjc into .cjls/macros, and run under a deadline

Status: proposed
Amends ADR-0087: how the macro packages are built, and the guard's deadline
Amends ADR-0094: macros are on for any SDK whose token numbers cjls can read
Amends ADR-0095: the numbers come from `std.ast` when the SDK has no `Tokens.inc`

## Context

- D87 builds the macro packages in a target directory of cjls's own and guards the server. It leaves open how to build them, where, when, and how long a call may take. #176's step 3 wires it together.
- cjpm cannot build only some packages. A full `cjpm build -i --skip-script --target-dir <own>` of this repository took 1m35s cold, and 1m22s after an edit to `calca.macros`, because every package using the macro was compiled again. `-m <module>` fails on a module whose stdx is a workspace dependency. cjc called on one package with cjpm's own arguments took about 3 s for each of this repository's three macro packages. These are informal timings on a loaded machine.
- cjpm compiles a package of a macro package's imports with `--output-type=staticlib -o=lib<pkg>.a`, and the macro package with `-L <dir> -l<dep>… --compile-macro`. Both get `--import-path=<target> --no-sub-pkg --output-dir=<target>/<module>/`. A macro package's library links what it imports from the workspace statically, and needs only the SDK's runtime.
- Reference servers:
  - R4 builds nothing. At `initialize` it reads the libraries the user built in `target/<profile>/<module>`, and never looks again.
  - R9 compiles a macro package itself with `cjc --compile-macro`, into a directory of its own. It neither builds what the package imports nor checks for staleness.
  - R1 runs `cargo check` again when a proc-macro crate's file is saved.
  - None of R1, R4 and R9 has a deadline on a call. A macro that loops hangs R4's whole compile.
- `LSPMacroServer` never unloads a library: `dlopen` of a rebuilt file at the same path returns the old handle.
- `Tokens.inc` is not in every SDK. D95 checked only nightly archives. Of the release archives of 1.0.5 and 1.2.0, only Linux x64 1.2.0 ships `include/`. All six ship `tools/bin/LSPMacroServer`. `std.ast.getTokenKind` names every kind by its number in any SDK.

## Decision

- **cjls builds what the macros need with the SDK's cjc, package by package, with cjpm's own arguments** (`MacroBuilder`). That is the workspace's macro packages and the source packages they import, directly or not (`loupe`'s `macroBuildPlan`), each after what it imports. It does not run `build.cj` or build any other package.
- **They go to `.cjls/macros/<cjc --version>/<module>/`** under the workspace root. cjls writes a `.cjls/.gitignore` of `*`. The user's `target` is never touched (D87), a `cjpm clean` leaves the directory alone, and a new compiler starts from scratch, since cjpm's stamps ignore it.
- **A package is built again when its stamp changes.** The stamp hashes cjc's version, the names, sizes and times of the package's files, and the stamps of what it links. A macro package's stamp is `Package.macroLibrary`, part of every request's fingerprint. A new library therefore makes its calls pending again, and the server, which kept the old one, is restarted. A build runs when the project is loaded, and when a file of a package in the plan is saved or changes on disk. A package that fails keeps its last library: cjc writes nothing on an error.
- **A call has a deadline**, 10 s by default (the `macros.callTimeout` setting). Past it the server is killed, and the call is answered as failed, with a diagnostic on the call. The answer has the request's fingerprint, so the call is not sent again until its input or library changes. A server that exits is started again for the next call, which costs only the call in flight. A call whose macro package has no library is never sent (D87).
- **Macros are on for any SDK whose token numbers cjls can read.** These are its `Tokens.inc`, else what `std.ast.getTokenKind` names (D95). For the second, cjls compiles a program printing them with the SDK's cjc, once per `cjc --version`, into `.cjls/macros/<version>/`.
- **Every file of the workspace with calls of workspace macros is expanded**, not only the open ones: what the macros declare is seen from other packages.

## Consequences

- An edit to a macro package costs its own compile and those of what it imports and changed, about 3 s each here, but never a compile of its users.
- What cjpm does beyond cjc's arguments is not repeated: a `build.cj`'s generated sources, `compile-option`, cfgs and features. A macro package that needs them builds otherwise than cjpm builds it, or fails, and its calls stay opaque.
- A macro package importing stdx is linked against stdx's static libraries by name (`-l<pkg>`). Whatever else stdx's libraries need is not added.
- `.cjls/` is a directory of the user's project that cjls writes. Its `.gitignore` keeps it out of version control.
