# Navigate macro expansions

`call = analysis.macroCall(path, offset)` finds a call at a source UTF-8 byte
offset, or returns `None`. `analysis.expansion(call.call)` returns an expansion
with `.text`, or `None` when unavailable. These two queries suffice to inspect
one macro. `analysis.expandedFile(path, header)` is for whole-file output and
requires an explicit header string; it is not needed before `expansion`.

Expansion queries use byte offsets into `analysis.expansion(call).text`:
`hoverInExpansion`, `definitionInExpansion` and `typeDefinitionInExpansion`.
They reject missing expansion text or invalid byte positions. A hover range
belongs to the requested expansion; each navigation target has its own
`expansion` identity (or `None` for source), which selects the text for its ranges.

## Inspect an expansion and resolve a generated use

For example, inspect a `@Derive` expansion and resolve the `==` used by its
generated `!=` in one script. Replace the path and byte markers for the selected
macro/use. If the path is unknown, select it inside the same script from
`workspace.files()`, filtering to project files. A text match selects a candidate;
`definitionInExpansion` supplies the semantic evidence.

```python
def excerpt(data, span, max_bytes=1200):
    # Trim only the preview; keep complete text and original ranges for analysis.
    text = data[span.start:min(span.end, span.start + max_bytes)].decode("utf-8", errors="ignore")
    end = span.start + len(text.encode("utf-8"))
    return {"range": TextRange(span.start, end), "text": text,
            "total_bytes": span.end - span.start,
            "omitted_bytes": span.end - end}

a = workspace.analysis()
path = str(workspace.root) + "/src/config/cjc_dependency.cj"
source = a.text(path).encode("utf-8")
macro_offset = source.index(b"@Derive[")
call = a.macroCall(path, macro_offset)
expanded = a.expansion(call.call) if call is not None else None
result = {
    "root": str(workspace.root),
    "loadDiagnostics": workspace.loadDiagnostics,
    "macros": workspace.macros,
    "path": path,
    "macro_offset": macro_offset,
    "expansion": None,
    "targets": [],
}
if expanded is None:
    result["gap"] = "Expansion unavailable"
else:
    text = expanded.text.encode("utf-8")
    result["expansion_bytes"] = len(text)
    use = text.find(b"this == other")
    if use < 0:
        result["gap"] = "Selected use absent from expansion"
    else:
        offset = use + len(b"this ")
        line_start = text.rfind(b"\n", 0, use) + 1
        preview = excerpt(text, TextRange(line_start, len(text)))
        result["expansion"] = preview
        preview["total_bytes"] = len(text)
        preview["omitted_bytes"] += line_start
        result["use"] = {
            "offset": offset,
            "line": text[:offset].count(b"\n") + 1,
            "text": "this == other",
        }
        targets = a.definitionInExpansion(call.call, offset)
        result["targets_total"] = len(targets)
        result["targets_omitted"] = max(0, len(targets) - 4)
        for target in targets[:4]:
            if target.expansion is None:
                target_text = a.text(a.path(target.fileId))
            else:
                target_expansion = a.expansion(target.expansion)
                target_text = None if target_expansion is None else target_expansion.text
            r = target.fullRange
            result["targets"].append({
                "path": a.path(target.fileId),
                "expansion": None if target.expansion is None else str(target.expansion),
                "fullRange": r,
                "focusRange": target.focusRange,
                "declaration": None if target_text is None else
                    excerpt(target_text.encode("utf-8"), r),
            })
        if not result["targets"]:
            result["gap"] = "Selected use has no definition target"
```

Previews contain at most 1200 UTF-8 bytes each, with their actual ranges and
omitted byte counts. At most four targets are shown; totals retain omitted
matches. Narrow the selection or retrieve more evidence when omissions matter.
The expansion includes both retained source and generated declarations; distinguish
them before counting additions. This example proves a use inside the expansion.
External uses need their own semantic evidence; a project-wide name search does
not prove or disprove operator calls. Return a selected excerpt for large
expansions instead of dumping unrelated output. Native navigation targets and
structure nodes need explicit field projection; ranges serialize directly.
