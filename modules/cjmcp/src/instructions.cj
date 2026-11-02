package cjmcp

// Keep the common path usable without loading a skill or exploring the bindings first.
let agentInstructions =
    #"
Use runPython when a Cangjie task needs declarations, usages, types or diagnostics.
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
Save edits with ordinary tools; inputs synchronize before the next call.
Reacquire analysis/IDs per call; globals are fresh. Validate changes with compiler/tests.
Load a cangjie-mcp recipe only for an unfamiliar operation.
"#
