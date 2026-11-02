# cjls tracked-call audit, 2026-11-02

This is the **stage 1 partial audit**, executed through the real cjmcp `runPython`
binding against cjls commit `d86fff40c4d6de739c7196f90df6237b6ebecb6d` on Linux
x86_64. The tracked source tree had no tracked local modifications. Analysis used
SDK `1.3.0-alpha.20261102001050`, CPython 3.14 and a 4 GB Cangjie heap. The
[per-function report](tracked-calls-2026-11-02.json) records binary SHA-256,
revision, source locations, traversal sizes, gap counts and example gap sites.
Its declaration IDs are scoped to that report, distinguishing overloads even
when navigation locations are unavailable.

| Result | Count |
|---|---:|
| Resolved active original tracked functions | 157 |
| In production source | 66 |
| In test source | 91 |
| Distinct graph declarations analyzed | 1693 |
| Functions with modeled target chains | 0 |
| Functions with complete negative traversals | 0 |
| Functions whose target reachability remains unknown | 157 |

No target chain was found in this model. **This does not establish absence of a
path for any of the 157 functions.** All traversals have substantial coverage
gaps. The target set is declarations owned by `std.fs`, `std.env`, `std.random`,
`std.time.DateTime.now`, or the three named `loupe.vfs` functions. Matching uses
declaration ownership, including through import aliases. Ordinary conditions
contribute both branches; configured conditional compilation remains in force.
The largest traversal visited 1503 declarations; the 10000-node limit was not hit.
Workspace preparation reported no problems and completed macro expansion.

The most frequent gap categories are callback/value flow, implicit operators,
properties/value initialization, construction and unavailable bodies. Virtual
implementation enumeration, default argument execution, protocol calls and
implicit conversion also remain incomplete. Counts are per root's reachable
graph and must not be summed as distinct workspace sites. Nested bodies are not
executed merely because they are declared. Calca-generated query wrappers do not
become calls of the original tracked body; other macros remain explicit gaps.

As a positive control, a real-process fixture with marker macro overloads in
`calca.macros`, an aliased macro import, a cycle and an unused lambda yields:

| Target | Minimum-edge chain, with call-site lines | Certainty |
|---|---|---|
| `std.env.getProcessId` | `query` → `via` (audit.cj:10) → `getProcessId` (audit.cj:15) | resolved |
| `std.env.getCommand` | `query` → `via` (audit.cj:10) → `getCommand` (audit.cj:16) | resolved |

These chains belong to the [control fixture](../../tests/mcp/call_audit_fixture/src/audit.cj),
not cjls production queries. The unused lambda does not introduce a shorter
chain. Each target gets its own shortest path, and unavailable std bodies still
make coverage incomplete. The fixture marker macros are identity macros, not
Calca's runtime implementation; the separate loupe expansion regression checks
that generated infrastructure calls are excluded.

Reproduce with the implementation from this PR and the SDK/CPython environment
from [cjmcp](../../modules/cjmcp/README.md):

```bash
cjHeapSize=4GB python3 scripts/call_audit.py \
  --binary target/release/bin/cjmcp --workspace /absolute/path/to/cjls \
  --output audit.json --summary audit-summary.json
```

The full report retains every reachable gap site (about 173 MB on this run); the
checked-in summary retains every root outcome, gap counts and one example of each
reason. Its hash identifies the full local report. The summary is not a replacement
for call-site evidence when findings exist: findings retain all shortest-chain
edges, sites and conservative labels in either form.

One run crashed with a native SIGSEGV during project discovery, before the audit,
with a GC/runtime stack through `CjpmLowering.dependencies`. A retry with the same
binary completed. This is a reproducibility limitation; the crash's cause is not
established by this audit and the failed run supplies no reachability evidence.

Validation on this implementation: build, six focused loupe regressions, ten
MCP tests (including the native positive control), five Call Hierarchy LSP e2e
cases, formatting and documentation checks passed. The full Cangjie run executed
2547 cases: 2546 passed and one errored with native GC SIGSEGV in
`CjpmRegistryTest.missingMalformedAndStaleSelectionsAreRecoverable`; no cases
were skipped. The full suite was therefore not clean. This is in unchanged
`project_model` code; that alone does not establish the crash's cause.

The [analysis contract and PR boundaries](../../modules/cjmcp/api/call-audit.md)
describe what remains: interprocedural functional values/callback execution, then
complete virtual/implicit targets and justified dependency models. This report
must be rerun after those improvements; stage 1 does not complete the original
purity/reachability audit.
