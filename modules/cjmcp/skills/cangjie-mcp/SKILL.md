---
name: cangjie-mcp
description: Analyze, read and edit Cangjie sources through cjmcp runPython when exploring, changing or reviewing code.
---

For a different worktree pass its absolute root in every runPython call. Omission
always uses the server's --dir. Verify the returned root and sessionId; revision
and last_output belong to that session, which can be evicted from the four-root
cache. Do not pass native IDs between sessions.

Follow server instructions for common queries; discover `runPython` if deferred.
Use this skill for an unfamiliar operation, loading only its relevant recipe.
Minimize total task token use without sacrificing correctness, evidence or
verification. Batching queries is one technique; use additional calls when they
reduce irrelevant output or resolve uncertainty. Keep intermediate data in Python.

Read only the recipe needed for an unfamiliar operation:

- [Composable semantics, project and syntax](references/semantic.md)
- [Declarations and usages](references/navigation.md)
- [Call hierarchy](references/calls.md)
- [Expression types and selected callees](references/inference.md)
- [Signature source maps](references/source-maps.md)
- [Formatting edits](references/formatting.md)
- [Read and save source edits](references/editing.md)
- [Members, outlines and builtin docs](references/members.md)
- [Counts, rankings and all tied maxima](references/aggregation.md)
- [Macro navigation](references/expansions.md)
- [Unknown API members](references/discovery.md)
- [Revision or execution failures](references/runtime.md)
