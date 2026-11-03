package cjmcp

// Keep the common path usable without loading a skill or exploring the bindings first.
let agentInstructions =
    #"
Use runPython for all Cangjie source analysis, reading and editing.
Do not use shell commands (rg, sed, cat, shell-launched Python or subprocesses)
for these operations, including subprocesses inside runPython.
Trust cjmcp analysis; report unavailable or partial results without a shell fallback.
Shell remains available for builds, tests, Git and non-Cangjie files.
workspace and native types are injected; do not import loupe.
Batch each self-contained read-only task into one script: traverse, filter,
aggregate and sort in Python, then return bounded JSON evidence. Sort rankings by
the requested metric, with name/path/position as stable tie-breakers, before
limiting output. Compute global maxima before limiting and return every tied
winner. Keep intermediate objects in Python; include totals and omitted counts.
Return paths, relevant source/ranges and needed signatures with the conclusions.

Source workflow (small full files are fine; keep large file text inside Python):
1. Locate names with a.symbols(name, 20), or filter a.fileSymbols(path) / nested
   workspace.structure(path) when paths are known. Return a compact candidate list
   before choosing an ambiguous declaration; symbols' limit is not a total count.
2. Pass selected (path, symbol.range) pairs to
   source_excerpts(a, requests, max_bytes=12000, offset=0, limit=20, context_lines=0).
   found = a.symbols("targetName", 20)
   result = {"search_may_have_more": len(found) == 20,
             "source": source_excerpts(a, [(a.path(s.fileId), s.symbol.range)
                                          for s in found])}
   It returns paths, one-based lines, UTF-8 requested/shown ranges, revision,
   total requests, omitted count and next_offset. It never cuts an excerpt.
   Recreate the same ordered requests at the same revision to page next_offset.
   If an entry cannot fit, narrow its range (e.g. select a member rather than
   its class) or raise max_bytes; required_bytes reports the blocked page size.
3. Edit using applyChange below; keep full expectedText in Python, not in result.
   Return the application report and a small unified diff (difflib, n=2).
4. In a fresh call check changed ranges, references/inference as relevant and
   diagnostics (message/range); report totals and omissions. Run compiler/tests.
Do semantic selection before implementing, rather than only checking afterwards.
runPython defaults to maxOutputBytes=24000 for the complete UTF-8 JSON payload.
Excess returns an explicit OutputBudgetExceeded error after the script executed.
The complete rejected payload is available as last_output in later calls until
replaced by another rejection: select only needed fields, without replaying edits.
For an intentionally large response set maxOutputBytes higher, or 0 (unlimited).
Output budgets concern returned data, not reading full files inside Python.

Capture a = workspace.analysis() in each call. Core queries:
- a.symbols(name, limit) -> matches with .fileId and .symbol (name, range,
  selectionRange). Resolve paths with a.path(fileId).
- a.references(path, byteOffset) -> entries with .fileId, .range, .isDeclaration.
- workspace.files() -> list[str] of loaded source paths, including dependencies;
  filter to workspace.root for repository-only tasks.
- a.text(path) -> revision text; workspace.structure(path) -> StructureNode list.
  Nodes have .name, .kind, .range, .selectionRange and nested .children;
  use .kind.toString() for kind names such as Function or Method.
- workspace.definition(path, byteOffset), hover(path, byteOffset), diagnostics(path).
  diagnostics returns WorkspaceDiagnostic objects directly serializable in result;
  each has source, code, severity, message, path, range, line, column, unnecessary.
  Location fields are None when unavailable; UTF-8 byte columns and lines are 1-based.
- a.declarations(path) -> DefIds; a.item(defId), a.infer(defId), a.typeText(ty).

Include workspace.root, workspace.loadDiagnostics and workspace.macros in the
first useful task query, not a separate setup call. loadDiagnostics is a list of
structured loading diagnostics. macros has state ("pending" or "settled") and
structured diagnostics; return these objects directly in result, without parsing
message strings or writing serializers. pending alone is not an error; settled
can include failures. Inspect diagnostic severity independently of completion.
Status/diagnostics describe this script's revision, including after writes/reload.
Query missing expansion-dependent evidence again when needed; do not add an
expansion wait to every query. Report mismatched roots/partial analysis. Use documented APIs before introspection; make another call
for errors, missing evidence or a fresh revision after edits.
Ranges are UTF-8 bytes, end exclusive: slice a.text(path).encode('utf-8').
Use workspace.applyChange(SourceChange([...]), a.revision) for project edits.
FileChange.EditFile(path, expectedText, edits), CreateFile(path, text),
RenameFile(path, target, expectedText), DeleteFile(path, expectedText) are native variants.
TextEdit(range, text) uses UTF-8 byte ranges; formatting results can be passed directly.
Inspect report.isSuccess, applied operation indices, failed index and error.
All operations are validated before writing; I/O failures may leave partial changes.
The current analysis stays unchanged after writing; new inputs synchronize next call.
Use pathlib inside runPython for direct I/O outside this model; verify disk bytes
against revision text before directly writing a loaded file.
Reacquire analysis/IDs per call; globals are fresh. Validate changes with compiler/tests.
Load a cangjie-mcp recipe only for an unfamiliar operation.
"#
