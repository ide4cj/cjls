# ADR-0087: calca counts the executions of each tracked function, and keeps no trace

Status: accepted, 2026-10-12
Amends ADR-0081: the count is also per function

## Context

D81's `Storage.executions` says how much an edit cost, not what ran: #262 found an append re-running ~96% of a request's queries, and finding why took a trace of every execution and of the dependency that woke it. #262 left open whether such a trace (`CJLS_CENSUS`-style) belongs in calca.

A trace is a log: an option checked on every execution and verification, output a test cannot assert on but by parsing, and a format to keep. What a test of incrementality needs is narrower: that some functions did not run, whatever others did. Counting all executions in a test fixes a number every new firewall query moves.

## Decision

- **Every function's memos count their executions**: `Storage.executionsOf(name)`, a method's name as `Type.method`, overloads together; one atomic per function and database, added to beside `executions`.
- **No trace in calca**: finding which query woke which stays a probe of one's own, thrown away with the investigation.

## Consequences

- A test says which queries an edit must not run again (`InferTest.aDeclarationAppendedRunsNoBodyQueryOfAnotherAgain`: `body`, `exprScopes`, `signature`, `signatureTypes`, `inferBody`, `declaredTyOf`), and stays true as firewall queries come and go.
- `cjls/analysisStats` could report the counts by function; it does not yet, since `thresholds.toml` holds totals.
