---
name: cangjie-mcp
description: Use Cangjie syntax and semantics through cjmcp runPython to explore, review and edit sources.
---

Use the analysis database and task recipes first, targeted bundled `.pyi` lookup
second, and textual heuristics only for a concrete gap. Syntax nodes determine
shape/nesting/ranges; resolved identities determine usages, types and hierarchy.
Text search also serves literals, comments, candidates and residual-name checks;
it does not prove symbol relationships. Keep selection and computation in Python,
return bounded evidence, and verify changed relationships in a fresh call.

For a simple lookup, use the server's query map directly. For a traversal or
refactor, read the matching recipe below before constructing your own workflow.
Reuse already-read guidance. Open API discovery only for the missing contract;
do not browse the reference as a preparation step or infer that an unfamiliar
operation is unavailable. For refactors use **refactoring + editing**.

| Task | Recipe |
|---|---|
| Syntax nodes, semantic objects, project/context traversal | [semantic](references/semantic.md) |
| Declarations, usages and bounded source | [navigation](references/navigation.md) |
| Change a member and verify its uses; checked file edits | [refactoring](references/refactoring.md), [editing](references/editing.md) |
| Calls, inferred types, written signature ranges | [calls](references/calls.md), [inference](references/inference.md), [source maps](references/source-maps.md) |
| Members/builtin docs, formatting, counts/rankings | [members](references/members.md), [formatting](references/formatting.md), [aggregation](references/aggregation.md) |
| Macro expansion and navigation | [expansions](references/expansions.md) |
| Missing API contract; execution/revision failure | [discovery](references/discovery.md), [runtime](references/runtime.md) |

Pass the absolute edited root in every call outside the configured `--dir`;
omission selects `--dir`, not the previous root. Verify root/sessionId and keep
native IDs, revisions and last_output within that session. Eviction from the
four-root cache closes a session; reopening gives a new ID.

For a deferred Codex tool, discover the configured name:

```javascript
text(ALL_TOOLS.find(t => t.name === "mcp__cangjie__runPython"));
```

If absent, search names/descriptions for `cjmcp` or `runPython`; the product name
alone can miss a configured namespace. Keep Git, builds, tests and non-Cangjie
files in shell; Cangjie source work stays in runPython.
