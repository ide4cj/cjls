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
- a.declarations(path) -> DefIds; a.item(defId), a.infer(defId), a.typeText(ty).

Include workspace.root, workspace.problems and workspace.hasExpandedMacros in the
first useful task query, not a separate setup call; report mismatched roots or
incomplete analysis. Use documented APIs before introspection; make another call
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
