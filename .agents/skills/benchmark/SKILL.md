---
name: benchmark
description: Collect or compare cjls microbenchmark and server performance evidence when timings or performance claims are requested.
---

Read [benchmark isolation](../../../docs/procedures.md#benchmark-isolation) and
use the commands in [Development](../../../docs/development.md#fuzzing-and-performance).
The SDK environment and separate worktree/cache prerequisites apply to each run.

Measure the same benchmark at separate revisions with the same machine, SDK,
build flags, corpus and filter. Build before measuring and coordinate an exclusive
measurement window with other users of that machine. One benchmark filter per
invocation; repeated filters silently select only the last. Never use a `-g` or
coverage build to support release performance claims.

Record commit, dirty state, compiler version, OS/architecture, CPU, power mode,
command, repetitions and concurrent load for both candidates. Observe load during
the run; quiet endpoints do not exclude a burst between them. Keep raw results.
Report noise, virtual-machine limits or unknown machine sharing alongside numbers;
rerun noisy results before quoting an improvement. A local lock coordinates only
participants using that lock, not unrelated builds. The repository supplies no
portable machine-wide lock or automatic quietness guarantee.

Machine-specific remote hosts, private scripts and old permission lists grant no
access or publishing authority. Use remote resources only within the user's
current authorization. Benchmarking is unnecessary for a documentation-only edit.
