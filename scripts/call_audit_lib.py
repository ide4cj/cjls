"""On-demand breadth-first audit over revision-bound loupe directCalls results.

Can be imported by runPython scripts. No source-text call matching is used.
"""
from collections import deque


def shortest_paths(root, successors, is_target, *, limit=10000):
    """One minimum-edge path per target, with gaps from all visited nodes.

    successors(node) returns ([(target, edge), ...], [gap, ...]). The result
    describes the constructed graph; gaps preclude a negative reachability claim.
    """
    parents = {root: None}
    queue = deque([root])
    findings, gaps = [], []
    while queue:
        node = queue.popleft()
        if node != root and is_target(node):
            path, cursor = [], node
            while parents[cursor] is not None:
                previous, edge = parents[cursor]
                path.append(edge)
                cursor = previous
            findings.append((node, list(reversed(path))))
        edges, missing = successors(node)
        gaps.extend(missing)
        for target, edge in edges:
            if target in parents:
                continue
            if len(parents) >= limit:
                gaps.append({"reason": "node-limit", "limit": limit})
                continue
            parents[target] = (node, edge)
            queue.append(target)
    return findings, gaps, len(parents)


def audit(workspace, *, limit=10000):
    """Audit original @CalcaTracked declarations; preserve one loaded revision."""
    analysis = workspace.analysis()
    metadata, adjacency = {}, {}

    def location(site):
        if site is None:
            return None
        path = analysis.path(site.fileId)
        text = analysis.text(path).encode("utf-8")
        start = site.focusRange.start
        return {"path": path, "start": start, "end": site.focusRange.end,
                "line": text[:start].count(b"\n") + 1,
                "expansion": site.expansion is not None}

    def declaration(definition):
        if definition not in metadata:
            item = analysis.callDeclaration(definition)
            metadata[definition] = {
                "id": len(metadata), "package": item.packageName, "name": item.name,
                "owner": item.ownerName, "location": location(item.location)}
        return metadata[definition]

    def target(definition):
        item = declaration(definition)
        return (item["package"] in {"std.fs", "std.env", "std.random"}
                or (item["package"] == "std.time" and item["owner"] == "DateTime" and item["name"] == "now")
                or (item["package"] == "loupe.vfs" and item["name"] in {"readFile", "readRoots", "readCjoFiles"}))

    def successors(definition):
        if definition not in adjacency:
            calls = analysis.directCalls(definition)
            caller = declaration(definition)
            adjacency[definition] = (
                [(edge.target, {"caller": caller, "callee": declaration(edge.target),
                                "site": location(edge.site), "conservative": edge.conservative,
                                "resolution": edge.resolution}) for edge in calls.edges],
                [{"declaration": caller, "reason": gap.reason, "site": location(gap.site)} for gap in calls.gaps])
        return adjacency[definition]

    roots = [definition for path in workspace.files()
             for definition in analysis.trackedCallRoots(path)]
    reports = []
    for root in roots:
        findings, gaps, visited = shortest_paths(root, successors, target, limit=limit)
        if workspace.problems or not workspace.hasExpandedMacros:
            gaps.append({"reason": "workspace-preparation", "problems": workspace.problems,
                         "has_expanded_macros": workspace.hasExpandedMacros})
        # Deduplicate repeated gap sites without hiding which successor was incomplete.
        import json
        gaps = list({json.dumps(gap, sort_keys=True): gap for gap in gaps}.values())
        reports.append({"root": declaration(root), "visited": visited,
                        "status": "reachable" if findings else "unknown" if gaps else "no-path",
                        "unlisted_targets": "unknown" if gaps else "no-path",
                        "coverage_complete": not gaps,
                        "findings": [{"target": declaration(dest), "edges": path,
                                      "distance": len(path),
                                      "certainty": "conservative" if any(e["conservative"] for e in path) else "resolved"}
                                     for dest, path in findings], "gaps": gaps})
    return {"revision": analysis.revision, "root": workspace.root,
            "problems": workspace.problems, "has_expanded_macros": workspace.hasExpandedMacros,
            "model": "written-direct-calls-stage-1", "declarations_analyzed": len(adjacency), "reports": reports}
