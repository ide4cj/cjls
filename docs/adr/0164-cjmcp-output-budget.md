# ADR-0164: Reject oversized Python responses and retain them for recovery

Status: accepted, 2026-11-03

## Context

The jian #49 probe returned 102,896 normalized response bytes in three source
exploration calls, about 77% of all runPython response bytes. External truncation
led to another source read. Existing semantic queries and UTF-8 slices were
sufficient for selecting evidence, but guidance offered only per-fragment manual
cuts and no response-wide protection. Scripts can write files before returning;
replaying a rejected script would repeat effects.

## Decision

Keep semantic selection and checked edits in existing APIs. Add a Python
presentation helper over (path, TextRange) pairs, with a shared UTF-8 JSON budget,
whole excerpts, line/range metadata, explicit totals and continuation offsets.

Default runPython to a 24,000-byte compact UTF-8 JSON payload budget, covering all
output channels and revision before the MCP wrapper. Preserve code-only calls
and the normal response shape. Oversize output becomes an explicit tool error,
never an incomplete success. Keep one rejected JSON payload in the session as
last_output so a later script can select from it without repeating effects.
An explicit maxOutputBytes=0 allows unlimited output; a larger budget is also
supported. The actionable rejection envelope is exempt from the requested limit.

Prompt-only guidance cannot prevent accidental dumps. Silent truncation loses
edit evidence and may hide errors. A hard cap without recovery would encourage
unsafe replays. Per-item budgets alone do not bound aggregate output.

## Consequences

Existing large calls now need selection or explicit opt-out. The default admits
small full files and useful source pages while intercepting the two largest
probe responses; it is a conservative presentation choice, not a token or cost
optimum. Rejected output still requires serialization and one retained payload's
memory. Recovery is session-local, may describe an older revision and is replaced
by the next rejection. This is not an execution, disk-capture or memory quota.

Macro scheduling, semantic range meaning, revision checks and expected-text
validation remain independent of output presentation. No blanket expansion wait
is introduced. Fewer returned bytes alone cannot establish lower session cost.
