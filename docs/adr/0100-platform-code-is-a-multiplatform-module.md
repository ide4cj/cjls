# ADR-0100: What differs between platforms is one multiplatform module, `platform`, of `common` and `specific` declarations

Status: proposed

## Context

- Platform code was `@When[os == …]` beside the code using it, in four modules: `cjls` (stdin, the relaunch with a larger heap and its Windows job, `cjc.exe`, the heap dump), `loupe.vfs` (a path's spelling), `project_model` (the host's `cfg`, `PATH`'s separator), `macro_server` (the server's process, 450 lines of Win32). The Windows job was written twice.
- An item `@When` leaves out is not compiled at all: a type error in Windows code builds green on Linux and macOS, and `cjc --cfg='os=Windows'` is refused (`user defined condition's key can not be the same with builtin condition`). Only CI's Windows sees it.
- Cangjie multiplatform (`[profile] experimental = true`) lays one package out over source sets chosen by `os.*`: a `common` declaration has no body, each platform's `specific` gives one, and a missing one is a compile error. `cjpm build --no-feature-deduce --enable-features=os.windows` compiles the Windows set on any host.
- Source sets are a module's: every file of a CJMP module is in one. On `1.3.0-alpha.20261002` a `*_test.cj` in a non-product set (`common`, or `posix` between `common` and `linux`/`darwin`) is neither compiled nor run, and cjpm says nothing; only the leaf, product set's tests run.

## Decision

- **One module, `platform`, holds what differs between the platforms cjls runs on**, at the bottom of the layers, on std alone: `common` declarations in `src/common`, `posix` (what macOS and Linux share, a user feature `os.linux` and `os.darwin` map to), `linux`, `darwin`, `windows`. The modules using it are not multiplatform; they call its API.
- **Not every module that has platform code made multiplatform**: the code each shares across platforms would go to `common`, where its tests are skipped, and the tests would be copied into each OS's set.
- **The architecture stays `@When[arch == …]`**, in `platform`'s common set: cjpm has features for `os.*` alone.
- **A platform test is in its OS's set** (`job_windows_test.cj`); what is pure text (`windowsCommandLine`) is too, and runs on CI's Windows only. Tests of a module using `platform` keep their `@When` classes (`VfsPathOnWindowsTest`).

## Consequences

- `cjpm build -m modules/platform --no-feature-deduce --enable-features=os.windows` (`os.darwin`) type-checks another platform's code locally.
- The module builds `-O1` (D101), and the workspace is `experimental` (cjpm wants it of the root as well).
- `cjpm test` of a module on `platform` neither imports nor links it from the product set's directory, where `cjpm build` does: the module's `build.cj` copies `libplatform.a` and `platform.cjo` up to where the test looks, after each build under `target` (a `--target-dir` elsewhere is not seen to).
- A `common` variable needs its `specific` in the very next set (`posix`), a function or a class anywhere down the chain: constants are functions (`hostOs()`). A `specific` function warns of a parameter it does not use, where a plain one does not.
- cjls does not yet read source sets (#318): `import platform` is unresolved in the editor, and a file of a set is analysed as a package of its own directory.
