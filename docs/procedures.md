# Verification procedures and integrations

[Development](development.md) owns setup and check commands. Repository skills
under [`.agents/skills/`](../.agents/skills) add narrow procedures for
[changed-file coverage](../.agents/skills/change-coverage/SKILL.md) and
[benchmark evidence](../.agents/skills/benchmark/SKILL.md). Humans can follow these
Markdown procedures too; no agent session or private memory is required.

## SDK environment

Use [Select the pinned SDK](development.md#select-the-pinned-sdk) in each shell or
inherit that environment from the launcher. Worktrees share an installed SDK,
not mutable `target/`, `.corpora/` or coverage outputs. `CANGJIE_HOME` and `CANGJIE_STDX_PATH` pointing to the
matching static stdx directory matter as well as the compiler on PATH.

Coverage's `-g` build and release builds exercise different compiler/runtime
behavior. Follow [toolchain constraints](development.md#toolchain-constraints)
and their SDK evidence when interpreting results. Coverage cannot establish that
a release-only failure is fixed, and a passing build does not retire a workaround.

## Benchmark isolation

Use [the performance commands](development.md#fuzzing-and-performance). Compare
separate revisions on the same identified machine, with the same SDK, flags,
corpus and benchmark selection. Comparing two copies in one binary can introduce
code-layout effects. Keep build caches per worktree; finish compilation before
the timing window. Do not measure competing candidates concurrently.

Coordinate the measurement window with other machine users and observe load
throughout the run. Record CPU, OS/architecture, SDK version, power mode, command,
revision and local edits, repetitions and raw output. On Linux, `/proc/loadavg`
provides one load signal; it does not establish stable CPU frequency, thermal
state or exclusive resource access. Other platforms need their own load monitor.
Virtual machines, background jobs and unknown sharing limit claims even with low
load. If interference occurs, retain the result as noisy and rerun before citing
an improvement. Correctness checks do not depend on having a quiet machine.

The former private `filaco-dev` procedure combined one machine's paths, remote
access assumptions, `flock` and Linux load sampling. Its quiet-run helper is not a
repository prerequisite. A portable locking/monitoring runner is deferred: no
single lock can exclude unrelated jobs, and a fixed load threshold is not a
portable quality guarantee. Until one is justified, use explicit coordination
and disclose the limits above. This migration grants no remote access or GitHub
write permission.

## Worktree lifecycle

Create a worktree for an independent task, giving it a descriptive branch/path:

```bash
git worktree add -b docs/example ../cjls-example master
git worktree list
```

Choose the intended starting ref and inspect existing local work before creating
one. Load the SDK in the new worktree and fetch corpora when required. Keep each
worktree's build/test outputs separate. Sharing an SDK installation is safe;
sharing mutable targets between sessions is not.

Cleanup is an explicit owner-coordinated operation after the session ends.
Inspect `git worktree list --porcelain`, then `git -C <path> status --short`
(including untracked files), preserve needed logs/results, and establish that no
agent, shell, editor or build process still uses it. A clean tree or old Git index
does not prove inactivity. Do not remove an unknown owner's worktree.

After the owner has finished and the work is preserved, use:

```bash
git worktree remove <path>
git branch -d <branch>
```

Avoid `--force`. Squash merges may make `branch -d` refuse deletion; verify the
PR's merged state, exact head commit and absence of subsequent local work before
considering explicitly authorized forced branch deletion. Missing upstreams and
reused branch names are not merge evidence. Do not fetch, publish, delete branches
or write to GitHub merely because an old permission list allowed it. The former
startup cleanup hook has been removed. No automatic replacement infers inactivity
from timestamps.

## Editor and LSP integration

The server remains available to editors over stdio; build/run and e2e commands are
in [Development](development.md#build-and-run). An agent-facing LSP tool or plugin
is not required to build, inspect or verify cjls. Use source search for navigation
and the real-binary e2e suite for protocol behavior in a fresh session.

A Codex-specific LSP adapter is explicitly deferred: no repository-owned adapter
or equivalent agent tool has been implemented or verified. Do not claim source
search replaces semantic rename/references, or that e2e checks establish an editor
plugin's integration. Test a configured editor when the requested change depends
on it. [Module notes](README.md#module-notes) explain local constraints;
[scenario navigation](development.md#find-a-path-through-a-change) connects them
to check selection and review evidence.
