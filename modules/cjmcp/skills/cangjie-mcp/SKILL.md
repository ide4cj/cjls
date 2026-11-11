---
name: cangjie-mcp
description: Analyze, read and edit Cangjie sources through cjmcp runPython when exploring, changing or reviewing code.
---

For a different worktree pass its absolute root in every runPython call. Omission
always uses the server's --dir. Verify the returned root and sessionId; revision
and last_output belong to that session, which can be evicted from the four-root
cache. Do not pass native IDs between sessions.

Follow server instructions for common queries; discover `runPython` if deferred.
Use the supplied queries and recipes directly. For an unfamiliar operation, read
its short task recipe below. Open [API discovery](references/discovery.md) only
when a specific missing API detail blocks the next query; reference browsing is
not a preparation step. Reuse answers already available in the task context.
Plan each read-only script around the user's requested evidence, not one API
operation. When the supplied API is sufficient, carry selection, analysis and
verification through in one call; keep intermediate objects in Python and return
the answer with supporting source/ranges. Include workspace health in that call.
Use follow-ups for a concrete missing contract, partial result, excessive output
or a decision that depends on seeing the result, rather than exposing each step.
Minimize total task token use, including query code and returned data, without
sacrificing correctness or verification. A call-count target must not truncate
the search or weaken evidence. Separate post-edit verification as required by
the editing recipe.

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
