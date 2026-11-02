---
name: cangjie-mcp
description: Use a connected cjmcp runPython tool to explore, change or review Cangjie code with semantic analysis.
---

Follow the server instructions; discover `runPython` if its schema is deferred.
For core queries, start the task directly without loading more documentation.
If MCP is unavailable, report the failure and use source tools/compiler/tests.

Read only the recipe needed for an unfamiliar operation:

- [Navigation](references/navigation.md): declaration source and usages; API
  discovery only when a required member is unknown.
- [Inference](references/inference.md): expression types, unknown-type states
  and selected callees; load the relevant section.
- [Runtime details](references/runtime.md): revision errors, macro preparation,
  threading and execution failures.

Batch and filter in Python. Return paths, relevant source/ranges and truncation
counts. Do not load all recipes or dump the API as a session warm-up.
