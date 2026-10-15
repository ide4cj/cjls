# ADR-0128: A `*_test.cj` file imports std.unittest and its macros with no line, as `cjc --test` does

Status: proposed

## Context

- #255: `cjpm test` compiles a package with tests so that its files call std.unittest.testmacro's macros (`@Test`, `@Expect`) with no import. loupe found a macro only through a file's imports (`resolveMacroPath`, `expandedCalls`), so such a call was a `TodoTy(MacroCall)` (D77) and an `@Test` class no `TestClass` (#264). 135 calls of this repository were of it: 8 test files of `cjls` and `cjformat`'s `corpus_test.cj` import nothing of std.unittest.
- cjc 1.3.0-alpha.20261014, checked in #255's PR (N159–N162):
  - N159: `cjc -p` leaves a package's `*_test.cj` files out unless `--test` or `--test-only`. `cjpm test` compiles the package with `--export-for-test` and then its tests with `--test-only` against it; `cjpm build` compiles it with neither.
  - N160: `--test` (and `--export-for-test`) gives every file of the package `import std.unittest.*` and `import std.unittest.testmacro.*`: `TestSuite`, `TestClass`, the re-exported `Configuration`, `KeyFor`, `Arbitrary` and every macro of testmacro resolve with no line, in a `*_test.cj` and in any other file. std.unittest.common's own `PrettyText` does not, nor std.unittest.mock's `mock` and `@On`.
  - N161: without them, a file that is no test calling `@Expect` is "undeclared identifier 'Expect'" to `cjpm build`, whose library `cjpm test` links.
  - N162: no `TestCases` is declared in std (#255 named it as a type `--test` leaves unseen; it is none).
- loupe's database knows a file by its `FileId` alone. The project model (D33) has the paths, the `Package` input the ids.

## Decision

- **Which files of a package are tests is an input**, `Package.testFiles`: those of its `files` named `*_test.cj`. `setProject` reads it off each path when it lowers a `PackageModel`, beside `files`, and sets it only when that set of names changed. It is cjc's rule on a name, the same whichever way the project was found (`cjpm.toml`, `cj-project.json`, loose files), so no `PackageModel` carries it.
- **A test file's scope has two globs no line writes** (`testImportsOf`): `std.unittest` and `std.unittest.testmacro`, beside the prelude on the level of the imports (D47), with no import site. Everything that finds a name through the file's imports sees them: `resolveMacroPath`, `expandedCalls`, inference's table of std.unittest's macros (D77), the names of an expansion of `@Test`.
- **A file that is no test sees neither**, though `cjpm test` compiles it with `--export-for-test`: `cjpm build` does not, and a call of `@Expect` there breaks the build (N161). The analysis answers as the build does; a test's view stays within the tests.

## Consequences

- An `@Expect` of a test file is a `Unit`, an `@Test` class there a `TestClass` with its `asTestSuite`, with or without the import.
- A package without `std.unittest` among its binaries (a fixture that reads no `.cjo` of it) gets neither glob, as one without `std.core` gets no prelude.
- A file renamed to or from `*_test.cj` is a new path, so its package's `files` and `testFiles` are set again together.
