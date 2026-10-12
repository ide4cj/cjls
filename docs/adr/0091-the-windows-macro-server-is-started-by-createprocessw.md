# ADR-0091: On Windows the macro server is started by CreateProcessW, inheriting its two pipe handles alone

Status: proposed
Amends ADR-0087: Windows is not left opaque

## Context

- D87 left Windows open: `LSPMacroServer.exe` takes five arguments, the two pipe `HANDLE`s it reads and writes as decimal numbers, `0|1` for parallel, and `cjc` (`src/main-macrosrv.cpp`). It has no ppid to watch. `std.process` passes a child its stdio and nothing else, and on Windows no shell can move a handle the way `/bin/sh` moves fds 3 and 4.
- cjc's own client (`MacroEvaluationClient.cpp:571-699`) does it this way:
  - it creates both pipes inheritable, all four ends;
  - it starts the server with `CreateProcess(…, bInheritHandles = TRUE, …)`, its stdout and stderr on the client's stderr;
  - it assigns the server to a kill-on-close job after it has started.
- A handle made inheritable is inherited by every process this one starts while it lives, whoever starts it. A child cjls starts at the same moment through `std.process`, which inherits handles, would hold the server's pipe ends. Then the server's exit would never reach this process as EOF.
- `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` (`STARTUPINFOEXW`) limits what a child inherits to the handles it lists, which must be inheritable.
- On Windows a DLL's dependencies are searched along `PATH`: it plays the part `LD_LIBRARY_PATH` plays for D87.

## Decision

- **The server is started by `CreateProcessW` through FFI** (`macro_server/src/process_windows.cj`):
  - two pipes are created uninheritable, and only the server's ends are made inheritable;
  - the server inherits those two and a duplicate of this process's stderr, as its stdout and stderr, through `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` and nothing else;
  - it starts with `CREATE_SUSPENDED | CREATE_NO_WINDOW`, an environment of this process's with the SDK's `runtime\lib\<host>` first on `PATH`, and the command line of `main-macrosrv.cpp`, each argument quoted as `CommandLineToArgvW` reads it back.
- **It is assigned to a kill-on-close job of its own before it is resumed**: it dies with this process even in a macro that loops and never reads. If Windows gives no job, it runs without one and exits at its next read, at EOF.
- This process closes the server's ends as soon as it has started: the server's exit is then EOF on the pipe this process reads.
- The pipes are read and written with `ReadFile`/`WriteFile` into memory of their own (`LibC.malloc`), never through `acquireArrayRawData`: a read blocks while the server works (C5).

## Consequences

- The connection, the framing and the guard D87 decides are the same on every platform; only `startMacroServer` differs.
- What can be tested off Windows is tested everywhere: the UTF-16, the quoting and the environment block (`windows_command.cj`). `MacroServerTest` runs the SDK's server on every platform, in CI on Windows too.
- Under the server D78 starts, the macro server is in D78's job as well: both jobs end it.
