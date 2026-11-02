# Follow incoming and outgoing calls

`prepareCallHierarchy(path, offset)` returns callable declarations, or `[]` for
an ordinary value or unresolved name. Keep each `CallHierarchyEntry` with its
producing analysis revision. `incomingCalls(entry)` groups callers;
`outgoingCalls(entry)` groups callees. Each `HierarchyCalls.ranges` lists the
explicit call sites in the caller's file: the returned item's target for incoming
calls, the input entry's target for outgoing calls. Anonymous lambdas belong to
their enclosing callable; function values are not followed through assignments.

Binary callables carry their canonical identity in `entry.definition`, including
when attached sources provide `entry.target`. Without attached sources, the target
points to the referring name. Preserve `definition` when reconstructing an entry;
incoming calls use it to distinguish binary overloads. Source-only entries use `None`.

```python
analysis = workspace.analysis()
path = "src/main.cj"
offset = analysis.text(path).encode("utf-8").index(b"main")
result = [
    {"callee": calls.item.name,
     "path": analysis.path(calls.item.target.fileId),
     "sites": [{"start": span.start, "end": span.end} for span in calls.ranges]}
    for entry in analysis.prepareCallHierarchy(path, offset)
    for calls in analysis.outgoingCalls(entry)
]
```
