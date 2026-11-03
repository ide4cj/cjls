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
Batch queries; project native attributes to bounded JSON primitives in result,
including paths, relevant source/ranges and truncation counts.

Capture a = workspace.analysis() in each call. Core queries:
- a.symbols(name, limit) -> matches with .fileId and .symbol (name, range,
  selectionRange). Resolve paths with a.path(fileId).
- a.references(path, byteOffset) -> entries with .fileId, .range, .isDeclaration.
- a.text(path) -> revision text; workspace.structure(path) -> nested .children.
- workspace.definition(path, byteOffset), hover(path, byteOffset), diagnostics(path).
- a.declarations(path) -> DefIds; a.item(defId), a.infer(defId), a.typeText(ty).

Include workspace.root, workspace.problems and workspace.hasExpandedMacros in the
first task query; report mismatched roots or incomplete analysis.
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
