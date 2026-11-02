# Tracked-call audit: stage 1

The [shared loupe contract](../direct-calls.md) defines immediate call evidence,
coverage gaps and declaration identity. The cjmcp bindings expose that model to
Python. This client selects audit targets and searches the graph.

## Reproduce the workspace audit

Build cjmcp as in its README, then run with the SDK and CPython 3.14 configured:

```bash
cjHeapSize=4GB python3 scripts/call_audit.py \
  --binary target/release/bin/cjmcp --workspace /absolute/path/to/cjls \
  --output audit.json --summary audit-summary.json
```

This drives the real `runPython` tool over stdio. `scripts/call_audit_lib.py` can also be
loaded inside a tool script and used as `result = audit(workspace)`.
It enumerates original tracked declarations and lazily memoizes immediate calls
within one revision. Breadth-first search returns one minimum-edge path **per
reachable target declaration**, not merely the nearest target or a target name.
Cycles terminate through identity-based visitation. Ties use edge order. No
preference for resolved paths overrides the minimum-edge requirement.

Each root has findings with edge locations and chain certainty, gaps from every
visited successor, a visited count and an independent coverage flag. `reachable`
means at least one modeled chain exists, `unknown` means none was found and gaps
remain, `no-path` means no modeled path and no reported gaps for that traversal.
`unlisted_targets` separately qualifies targets without findings. Finding a chain
does not make other targets unreachable. `node-limit` explicitly marks truncated
traversals. Loading problems and macro preparation status are retained in the
report; inspect them before trusting coverage. Identities are native during search;
serialized declaration IDs distinguish graph nodes/overloads within that report only.
They must not be fed into another revision. The full report retains every gap
site and can be large; `--summary` saves all per-root outcomes and gap counts plus
one example per reason. The checked-in [cjls audit](tracked-calls-2026-11-02.md)
records the workspace run and coverage limitations.

## Planned PR boundaries

1. **Shared prerequisites:** loupe immediate-call evidence and coverage gaps in
   master, followed by native cjmcp bindings in experiment/cjmcp.
2. **This draft:** BFS, target selection, a CLI runner, regression cases and a
   real partial cjls audit. This stage does not claim completeness.
3. **Functional execution graph:** identities for lambdas/local functions, value
   flow through locals, parameters, returns and callback invocation. Implement
   context/argument-sensitive refinement as an explicitly requested query, keeping
   inference intraprocedural. Tests must distinguish unused values from invoked
   callbacks, including unavailable dependency bodies.
4. **Runtime targets and implicit edges:** possible virtual implementations,
   getters/setters, complete constructor/field/base/default initialization and
   language protocols; reviewed dependency models for callback-taking std APIs.
   Add those edges to the same model, retire corresponding gaps only with tests,
   rerun the audit and report remaining external-body gaps.

These boundaries keep value-flow fixed points and workspace implementation searches
out of interactive inference, and make each coverage improvement independently
reviewable. The original full audit remains incomplete until those stages land.
