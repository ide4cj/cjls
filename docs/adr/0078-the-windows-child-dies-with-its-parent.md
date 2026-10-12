# ADR-0078: On Windows the server puts itself in a kill-on-close job before it starts its child

Status: proposed
Amends ADR-0031: on Windows the child dies with the parent

## Context

- D31: without `cjHeapSize` the server starts over; on Windows as a child on the same stdio, the parent waiting. A parent an editor kills (`TerminateProcess`, after a `shutdown` it thinks timed out) left the child running until its stdin reached EOF (#86).
- A Job Object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` terminates every process in it when its last handle closes, and a process exiting, however, closes its handles. A process in a job puts every process it starts in it too, unless it starts it with `CREATE_BREAKAWAY_FROM_JOB`; jobs nest since Windows 8, so a parent already in an editor's job can still join one.
- `std.process.launch` gives the child's pid, not its handle; it calls `CreateProcessW` with handle inheritance on and no breakaway flag. A job's handle made with no security attributes is not inherited.
- Putting the child in the job after `launch` (`OpenProcess` of its pid) leaves a window in which a killed parent leaves the child outside it; `CreateProcessW` through FFI, suspended until assigned, closes it at the cost of quoting a command line and wiring stdio by hand.

## Decision

- **The parent puts itself in a new kill-on-close job, then launches the child**, which is born in it: no window, no handle of the child, `std.process` kept. The job's only handle is the parent's, never closed: when the parent ends, the child is terminated.
- If the job cannot be made or joined, a `WARN`, and the child is launched as before.

## Consequences

- Whatever the child starts is in the job too and dies with the parent; the server starts nothing today.
- `tests/e2e/test_heap.py` kills the parent and waits for its child to end, on every platform (on POSIX there is no child); `KillOnCloseJobTest` closes a job holding a `cmd.exe` and waits for it.
