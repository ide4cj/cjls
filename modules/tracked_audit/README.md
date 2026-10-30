# Tracked function reachability

`tracked_audit` is a standalone Cangjie client of `loupe`, `project_model` and
`macro_host`. It answers this question without Python, MCP or an LSP connection:

> For each @CalcaTracked function in the cjls workspace, find whether it can
> reach std.fs.*, std.env.*, std.time.DateTime.now, std.random.*,
> loupe.vfs.readFile/readRoots/readCjoFiles through any call chain. For each one
> that can, give the shortest call chain.

Build from the workspace root with the pinned SDK from
[Development](../../docs/development.md#select-the-pinned-sdk):

```bash
cjpm build -m modules/tracked_audit
cjHeapSize=2GB target/release/bin/tracked_audit --dir . --output target/tracked-reachability.json
```

The executable links the Cangjie runtime statically. The SDK is still needed to
load compiled package declarations and build/run workspace macros. Progress and
failures go to stderr; stdout contains JSON unless `--output` is supplied.
Exit 0 means an audit was produced, including an inconclusive audit; exit 1 means
the command failed. `--help` lists the options. `--no-macros` is an explicitly
incomplete exploratory mode. `--max-nodes N` bounds the number of callable
contexts visited (default 100000); exhausting it records a frontier.

## Scope and interpretation

Project discovery selects the host configuration, including test files and
active dependency contexts. Roots are active `Func` declarations tagged
`CalcaTracked` in workspace member modules; an annotation on an `extend` is not
a function. Inactive platform alternatives, fixtures stored as string literals
and unrelated files outside the project model are not executable roots. To audit
another target, load the corresponding project model/configuration; this command
does not merge incompatible platform alternatives into one graph.

The source implementation and its served macro wrapper are two entries for the
same logical tracked function. Calls are resolved by declaration identity, not
spelling or source file path. This counts `std.fs.Path` construction even without
disk I/O. `DateTime.nowUTC`, `MonoTime.now`, and similarly named user functions do
not match `std.time.DateTime.now`.

This is syntactic declaration-level reachability: branches and loop bodies are
considered possible without proving runtime path feasibility. A selected overload
is followed; unselected name candidates are not call edges. Macro expansion
bodies are read directly. SDK binary declarations are followed through checked
source counterparts when available, keeping binary identity for API matching.

Creating a lambda or passing a function value does not invoke it. Local closure
and local function calls are followed. Callable arguments are bound separately
for each call context, including named and default arguments, and forwarded
through parameter calls. Closures retain their callable parameter environment.
Mutable local assignments invalidate these simple bindings. This does not model
general object/heap flow: functions stored in fields, unknown receivers, virtual
dispatch and generic receiver substitutions can leave open frontiers.

Properties select the read or write accessor. Explicit initializer calls,
inference-selected operators and index assignments are included. Unclosed
constructor field initialization, implicit iterators, resource cleanup,
interpolation conversions, synchronization and missing implementations remain
frontiers. A missing body is never treated as an empty implementation.

## JSON results

Each `tracked_roots` row identifies the source declaration by qualified name,
path and byte range, so overloads stay distinct. It has:

- `status`: `reachable` when a resolved chain reaches any requested family;
  `not_reachable` only when the explored graph is closed and loading is complete;
  `unknown` otherwise.
- `shortest_chain`: a minimum-call path to any requested family in the resolved
  graph, or null. `shortest_chains` also gives the shortest discovered path to
  each reached family; `family_status` describes the others separately.
- `boundary_ids`: indices into the shared top-level `boundaries` table. Those
  records identify the callable context, reason and expression where analysis
  stops. Loading/macro failures appear separately in `problems` and prevent
  negative conclusions.

Each path records its steps, caller, callee and call-site evidence. Locations
inside expansions explicitly say `in_expansion`; their ranges/lines refer to
that expansion's text, not to the original source. `context` and
`body_expression` identify contexts only within this report/revision.

`call_count` counts calls, including lambda invocation. A transition to evaluate
an omitted default argument has `call_cost: 0`: its expression runs at the call
site, rather than introducing an extra function call. The path solver relaxes
both zero- and one-cost edges. `shortest_proven` is true only when no recorded
frontier can hide a path with fewer calls; otherwise the witness establishes
reachability but only minimality within the resolved graph.

The traversal stops on reaching a target API, which suffices for the prompt's
shortest path to *any* family. It records that terminal boundary explicitly, so
effects beyond that target cannot incorrectly become negative per-family
answers. No complete heap, dynamic dispatch or native SDK effect analysis is
claimed. A report containing only `unknown` is an inconclusive result, not a
proof that tracked queries are free of these APIs.

Macro packages are built under the analyzed project's
`target/tracked-audit/macros`, using the existing versioned cache and locking
pipeline; independent resolution scopes get separate directories. The command
does not modify source files.

## Verification

The analysis is in `loupe` and its fixture regressions cover shortest paths,
cycles, overload selection, all seven target families, closures and callback
contexts, defaults, accessor selection, served wrappers and budget exhaustion:

```bash
cjpm test --no-progress --target-dir target/test '--filter=TrackedReachabilityTest.*'
```

Use the full suite and formatting checks from
[Development](../../docs/development.md#choose-checks-for-a-change) before changing
the traversal's semantics. An actual SDK-backed workspace run supplements these
fixtures; it does not prove completeness of unresolved frontiers.
