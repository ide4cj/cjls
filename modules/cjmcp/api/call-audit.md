# Call audit: stage 1

`analysis.trackedCallRoots(path)` finds active original declarations by resolving
the macro to `calca.macros.CalcaTracked`, including renamed imports.
`analysis.directCalls(definition)` returns `DirectCalls(edges, gaps)` on demand.
An edge retains its target `DefId`, UTF-8 call-site `NavigationTarget`, resolution
string and `conservative` flag. `analysis.callDeclaration(definition)` returns
canonical identity, declaring package, name, containing declaration name and
optional navigation location. Match targets by this metadata, never by source
spelling. Keep all values with their producing `AnalysisRevision`.

This is a partial possible-call model, not an execution proof. Conditions are not
proved; both branches contribute. `resolved-declaration` identifies the declaration
resolved at an explicit call site. `inferred-operator` identifies an overload
selected by inference. `candidate` is conservative: an ambiguous candidate or a
static virtual declaration whose runtime implementation is not enumerated.
A chain containing a candidate must remain labelled conservative.

The query uses the same call-site resolver as Call Hierarchy: selected
initializers, name resolution, member resolution and inference results. It does
not mistake `infer().callees` for a complete list. Existing LSP hierarchy behavior
is preserved; this query has stricter execution boundaries. No new LSP method is
added and inference does not invoke this query or a transitive traversal.

The source declaration's original body is scanned. `@CalcaTracked` is transparent:
Calca's generated runtime wrappers are not additional calls made by the original
body. Other declaration macros add `declaration-macro`; body macros add
`body-macro` and their token arguments are not treated as executed code. Generated
expansion declarations have unavailable bodies in this model. This deliberately
leaves macro semantics unknown instead of mixing generated and original calls.

Nested local functions and lambdas are execution boundaries. Merely declaring
them contributes no edge and does not execute their bodies. Invoking such a value
adds a gap in this stage. The analysis does not yet follow functional values
through assignments, parameters or returned values. Explicit declaration calls,
methods, selected overloads and explicit initializer calls contribute edges;
selected operator overloads contribute edges alongside an incompleteness marker.

Gap reasons are part of the API:

| Reason | Missing behavior |
|---|---|
| `unavailable-body` | Binary/expansion body, declaration without a block, removed declaration |
| `unresolved-call` | No declaration-backed callable target was resolved |
| `functional-value` | Local function, lambda, parameter, variable or expression called as a value |
| `functional-value-or-constructor` | Name resolved to a value/type without a selected callable declaration |
| `callback-flow` | A call has arguments; callback transfer/invocation is not modeled (deliberately overinclusive) |
| `virtual-dispatch` | Static declaration found; possible runtime implementations not enumerated |
| `implicit-initialization` | Field, base and other implicit construction effects not modeled |
| `implicit-operator` | Operator effects not fully modeled, even if a selected overload is retained |
| `property-or-initialization` | Getter/setter or declaration-backed value initialization not modeled |
| `unresolved-value` | Value resolution unavailable |
| `default-arguments` | Default values are not unconditional body calls |
| `implicit-conversion` | Interpolation may invoke user conversion code |
| `malformed-source` | Parse recovery may have omitted executable code |
| `iteration-protocol`, `resource-protocol`, `spawn-boundary` | Implicit protocol/execution effects not modeled |
| `declaration-macro`, `body-macro` | Macro behavior outside transparent CalcaTracked policy |

Gaps have an optional location; unavailable bodies may have no location.
They are coverage information, not source diagnostics. The staged model omits
additional compiler/runtime effects (for example allocation/finalization and
implicit string conversion); it cannot certify general language-level purity.
A `no-path` answer is only relative to the constructed model, never such a proof.

## Reproduce the workspace audit

Build cjmcp as in its README, then run with the SDK and CPython 3.14 configured:

```bash
cjHeapSize=4GB python3 scripts/call_audit.py \
  --binary target/release/bin/cjmcp --workspace /absolute/path/to/cjls \
  --output audit.json --summary audit-summary.json
```

This drives the real `runPython` tool over stdio. `api/call_audit.py` can also be
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
one example per reason. The checked-in [cjls audit](../../../docs/audits/tracked-calls-2026-11-02.md)
records the workspace run and coverage limitations.

## Planned PR boundaries

1. **This PR:** reusable immediate declaration-call evidence and coverage gaps,
   shared hierarchy resolver, native bindings, BFS, regression cases and a real
   partial cjls audit. This stage enables inspection without claiming completeness.
2. **Functional execution graph:** identities for lambdas/local functions, value
   flow through locals, parameters, returns and callback invocation. Implement
   context/argument-sensitive refinement as an explicitly requested query, keeping
   inference intraprocedural. Tests must distinguish unused values from invoked
   callbacks, including unavailable dependency bodies.
3. **Runtime targets and implicit edges:** possible virtual implementations,
   getters/setters, complete constructor/field/base/default initialization and
   language protocols; reviewed dependency models for callback-taking std APIs.
   Add those edges to the same model, retire corresponding gaps only with tests,
   rerun the audit and report remaining external-body gaps.

These boundaries keep value-flow fixed points and workspace implementation searches
out of interactive inference, and make each coverage improvement independently
reviewable. The original full audit remains incomplete until those stages land.
