package cjmcp

// Keep the common path usable without loading a skill or exploring the bindings first.
let agentInstructions =
    #"
Use runPython for Cangjie declarations, usages, types and diagnostics before
broad source searches. Batch queries and return bounded JSON via result.
workspace and native types are injected; do not import loupe.

Capture a = workspace.analysis() in each call. Core queries:
- a.symbols(name, limit) -> matches with .fileId and .symbol (name, range,
  selectionRange). Resolve paths with a.path(fileId).
- a.references(path, byteOffset) -> entries with .fileId, .range, .isDeclaration.
- a.text(path) -> revision text; workspace.structure(path) -> nested .children.
- workspace.definition(path, byteOffset), hover(path, byteOffset), diagnostics(path).
- a.declarations(path) -> DefIds; a.item(defId), a.infer(defId), a.typeText(ty).

In the first task query also check workspace.root, workspace.problems and
workspace.hasExpandedMacros; report mismatched roots or incomplete analysis.
No separate setup/discovery call is needed. Use task recipes from cangjie-mcp
only for unfamiliar operations; dir(type(value)) is a fallback, not onboarding.
Native values use attributes; convert them to JSON primitives before returning.

Ranges are UTF-8 bytes, end exclusive: slice a.text(path).encode('utf-8').
Save edits with normal tools, then make a new call and reacquire analysis/IDs.
Inputs synchronize before each script; reload() cannot refresh a running one.
Keep identities within their revision; expanded ranges may belong to macro output.
Use compiler/tests for validation and source tools for analysis gaps/docs/configs.
Python has process permissions and no hard timeout; inspect effects before retrying
failed scripts. Calls have fresh globals and run sequentially.
"#
