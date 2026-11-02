---
name: cangjie-mcp
description: Explore, change, or review Cangjie code using a connected cjmcp runPython tool for declarations, usages, types, selected callees, macro expansions and diagnostics. Use when semantic context is needed; configuration and prose-only edits can use normal file tools.
---

# Work with Cangjie analysis

Discover the connected `runPython` tool (including deferred schemas) and use its
server instructions. Tool names may have a client-specific namespace. If no
cjmcp connection exists or the call fails, report the concrete limitation and
continue with source tools and compiler/tests where possible; this skill does
not install or start a server.

Before exploring or changing code, check `workspace.root`, `workspace.problems`
and `workspace.hasExpandedMacros`. The root must match the checkout/worktree
being edited. Save editor buffers: cjmcp analyzes disk inputs.

Choose the smallest semantic query that answers the task:

- Locate code with `analysis.symbols(query, limit)` or `workspace.structure(path)`.
  Resolve ambiguous matches before querying usages.
- Understand a change's impact with references, implementations and relevant
  source from `analysis.text(path)`. For overloads and call behavior, inspect
  `analysis.infer(def).callees` and resolved types instead of matching names.
- Investigate a diagnostic with hover, signatures, inference and macro source
  mappings as needed. Query only the relevant declarations.

Capture `analysis = workspace.analysis()` within each script. Batch related
queries and filter in Python; bound traversal and output. Return paths, byte
ranges, relevant source and a concise interpretation, with counts when output
is truncated. Convert native attributes to JSON values; do not return proxies.
Use `dir(type(value))` to discover an unfamiliar result. Read
[Python recipes](references/python-api.md) for call shapes, source slicing,
references, inferred expressions and selected callees; load only relevant parts.

Make edits through the client's usual tools. In a new `runPython` call, reacquire
the analysis handle and IDs, check changed-file diagnostics and affected usages.
Inputs synchronize before a script, not halfway through it; `reload()` cannot
refresh a running script. Use revision text for UTF-8 byte ranges. Do not mix IDs
across revisions or interpret macro-relative ranges as original-file offsets.

Run the repository's relevant compiler/tests to validate the change. Report
analysis gaps and loading/macro problems that limit the conclusion. Empty
results are not proof of absence. Use ordinary search for docs, literals,
configuration or unsupported analysis, and avoid repeating successful semantic
queries with name searches. cjmcp supplies analysis, not a dedicated rename,
refactoring or build/test runner. Python can perform external effects; after an
error, inspect what ran before retrying a script with side effects.
