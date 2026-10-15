# ADR-0125: cjc runs behind a shim that closes the descriptors it inherited

Status: proposed

## Context

- `std.process.launch` on Unix (`process_ffi_unix.c`, `CJ_OS_StartProcess`, cangjie_runtime at the commit `tests/corpora/fetch.py` pins) makes the child's stdio pipes and its `error` pipe with `pipe()`, no `O_CLOEXEC`; the `error` pipe's write end gets `FD_CLOEXEC` only in the child, after the `fork`. The parent then reads the `error` pipe to EOF before `launch` returns, to learn whether `exec` worked.
- A `fork` in another thread meanwhile copies those ends into its child, which keeps them through `exec` for its whole life. The first `launch` then returns only when that other child exits, and until it returns nobody reads its own child's stdout: a child writing more than a pipe's 64 KiB waits. Two such children holding each other's `error` pipe wait for good.
- cjpm scans up to 16 packages at once (`cjc -p <pkg> --scan-dependency`, `min(16, -j)`), each through `launch` with piped output read to EOF (`execWithOutput`); `cjls.lsp_types`' scan writes 547 703 bytes. A target directory with nothing to reuse (Coverage, Fuzz) scans every package at once: #342, jobs compiling 45 minutes without a line.
- A probe of 16 threads each `launch`ing a script that writes 600 000 bytes, read as cjpm does, hung within the first 40 launches every run, each blocked thread in `read` on an `error` pipe; 30 000 bytes, or the same script behind a process that closes every descriptor above stderr before `exec`, finished 3200 launches. `cjpm check` of this repository (every package scanned, 2 s a run) hung 3 runs of 100, behind the shim none of 300.
- cjpm starts `cjc` by name, from `PATH` (`execvp`); it reads `which cjc` only on macOS without `CANGJIE_HOME`, which `setup.py` sets.
- `-j 1` would scan one package at a time, but it also builds and runs the tests one at a time.

## Decision

- **CI puts `.github/actions/setup-cangjie/shim/cjc` ahead of the SDK on `PATH`** on Linux and macOS: it finds the next `cjc` on `PATH`, closes every descriptor above stderr and `exec`s it. What a concurrent `fork` leaked into it lives until the shim's `exec`, never as long as a `cjc`. Windows (`CreateProcessW`) is left alone: its jobs have not hung.
- The fix is the SDK's (`pipe2(…, O_CLOEXEC)`, or the `fork` under a lock with the pipes made); the shim goes with the nightly that has it.

## Consequences

- Every `cjc` in CI starts a Python first, some 20 ms.
- A local `cjpm` can hang the same way; the shim's directory first on `PATH` is the remedy there too.
- Another tool cjpm launches with piped output (`cjlint`, `git`) is not covered; none of them runs concurrently with the scans in CI.
