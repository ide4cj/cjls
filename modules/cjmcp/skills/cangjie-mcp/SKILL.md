---
name: cangjie-mcp
description: Analyze, read and edit Cangjie sources through cjmcp runPython when exploring, changing or reviewing code.
---

Follow server instructions for core queries. Discover `runPython` if deferred.
Use it for all Cangjie source analysis, reading and editing; do not use shell
commands or subprocesses as a substitute, including shell-launched Python.
Trust cjmcp analysis and report unavailable or partial results without a shell
fallback. Compiler/tests remain the required validation of changes.

Batch a self-contained read-only task into one script, including health fields
with the useful query. Keep intermediate objects in Python and return bounded
JSON evidence with totals and omitted counts. Sort rankings before limiting output;
compute global maxima first and preserve all ties. Use the documented API before
introspection; another call is warranted for errors, missing evidence or a fresh
revision after edits. Do not replay scripts with effects without inspecting state.

Read only the recipe needed for an unfamiliar operation:

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
