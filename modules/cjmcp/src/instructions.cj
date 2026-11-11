package cjmcp

// Keep the common path usable without loading a skill or exploring the bindings first.
let agentInstructions =
    #"
Use runPython for all Cangjie source analysis, reading and editing; do not
substitute shell commands or subprocesses. Report partial analysis without a
shell fallback. Shell remains available for Git, builds, tests and non-Cangjie files.
Pass root=<absolute edited project/worktree> on every runPython call when working
outside the configured --dir. Omitting root always selects --dir, not the previous
call. Canonical roots have independent analysis, macro and last_output state.
Responses carry root and sessionId; revision numbers are meaningful only within
that session. Four roots are cached by recency; eviction closes their workers and
macro hosts. Reopening creates a new sessionId. Calls remain sequential.
workspace and native types are injected; do not import loupe.
Use the core queries below directly for common tasks; no API documentation lookup
is needed before using them. Start with a query that advances the task, including
the workspace health fields below in the same call. For an unfamiliar operation,
load only the relevant task recipe from the cangjie-mcp skill.
Compose read-only tasks in Python: select candidates, inspect them and verify
the requested evidence in one script when the queries below are sufficient.
Keep intermediate objects in Python; return conclusions with supporting
paths/ranges, relevant source and explicit totals/omissions. Use follow-ups for
a concrete missing contract, partial result or a decision needing user input.
Minimize total task token use, including code and output, without truncating
searches or weakening verification. Post-edit verification needs a fresh call.

Capture a = workspace.analysis() in each call. Core queries:
- a.symbols(name, limit) -> matches with .fileId and .symbol (name, range,
  selectionRange); resolve paths with a.path(fileId). A full limit may omit matches.
- a.fileSymbols(path), workspace.structure(path) -> declarations; structure nodes
  have .name, .kind, .range, .selectionRange and nested .children.
- a.references(path, byteOffset) -> entries with .fileId, .range, .isDeclaration.
- workspace.files() includes dependencies; filter to workspace.root when needed.
- a.text(path) -> revision text; ranges are UTF-8 bytes, end-exclusive.
- workspace.definition(path, offset), hover(path, offset), diagnostics(path).
- a.declarations(path) -> DefIds; a.item(defId), a.infer(defId), a.typeText(ty).
- s = a.semantic() -> snapshot views; s.at(fileId, offset), s.project(), s.syntaxAt(fileId).
  Compose occurrence.resolution(), contextualFile() and object relationships; retain gaps.
- a.macroCall(path, byteOffset) -> call or None; a.expansion(call.call) -> expansion
  or None, with .text. a.expandedFile(path, header) needs an explicit header string.
  a.definitionInExpansion(call.call, offset), hoverInExpansion(call.call, offset),
  typeDefinitionInExpansion(call.call, offset) use UTF-8 bytes in expansion.text.
  Navigation targets have .fileId, .fullRange, .focusRange and .expansion; use that
  target's expansion text when .expansion is present, otherwise a.text(a.path(fileId)).
- a.body(defId), a.infer(defId) -> matching .locals/.exprs arrays;
  a.typeKind(ty) preserves native variants; a.typeText(ty) gives display text.
  a.signatureWithSourceMap(defId) -> .signature and .sourceMap.ranges.
- a.allMembers(defId) -> native MemberTarget variants, including inherited/extend members.
  a.members(defId, name), a.supertypes(defId) narrow member/type queries.
- a.prepareCallHierarchy(path, offset) -> entries; a.incomingCalls(entry),
  a.outgoingCalls(entry) -> caller/callee groups with call-site ranges.
- a.completions(path, offset), a.completionDetails(path, offset, item);
  a.typeDefinition(path, offset), a.implementations(path, offset).
- a.formatting(path), a.rangeFormatting(path, TextRange(start, end)) -> edits or None.
  options=FormatOptions(indentWidth=2) overrides defaults; these queries never write.
- a.builtinTypeDoc(name), a.builtinAnnotationDoc(name), a.builtinMacroDoc(name) -> doc
  or None; annotation/macro names exclude @. a.newFilePackageLine(path) -> header or None.
- workspace.sdk -> selected SDK or None; project path/source/version/channel fields
  explicitly for JSON. s.project().modules(): module.nativeLibraries() gives linker inputs.

Select declarations/members before returning source:
result = source_excerpts(a, [(path, symbol.range)], max_bytes=12000)
The helper returns whole excerpts with path/line/range metadata and pagination.
Continue next_offset using the same ordered requests and revision; if blocked,
select a smaller range or increase max_bytes. Small full files are fine.
Keep full expected text inside Python for edits; return a compact diff and report.
For rankings, sort before limiting; compute global maxima first and preserve ties.

Include workspace.root, workspace.loadDiagnostics and workspace.macros with the
first useful query. These and workspace.diagnostics(path) serialize directly.
Other native objects (structure nodes, navigation targets, SDK values) need
explicit JSON field projection; returning them directly fails serialization.
MacroState.Pending()/Settled() describe completion; inspect severity independently.
Report mismatched roots or partial analysis. Retry missing expansion-dependent
queries when needed; no blanket expansion wait is required.

Use workspace.applyChange(SourceChange([...]), a.revision) for project edits.
FileChange variants: EditFile(path, expectedText, edits), CreateFile(path, text),
RenameFile(path, target, expectedText), DeleteFile(path, expectedText).
TextEdit(range, text) uses UTF-8 byte ranges; formatting edits pass through directly.
Inspect report.isSuccess, applied operation indices, failed index and error.
Validation precedes writes; I/O failures may leave partial changes. For direct
pathlib writes to loaded files, compare disk bytes with revision text first.
After edits, reacquire analysis/IDs in a new call and check affected semantics and
diagnostics; globals are fresh and the writing call retains its old revision.
Validate changes with compiler/tests.

runPython defaults to maxOutputBytes=24000 UTF-8 JSON bytes across all channels.
OutputBudgetExceeded occurs after execution: select from last_output in a new
call without replaying effects. Saved output may describe an older revision.
Explicit maxOutputBytes=0 allows unlimited output; larger limits are supported.

If a specific missing API detail blocks the next query, use the skill's
references/discovery.md recipe for a targeted lookup in the bundled .pyi reference.
Otherwise continue with the task; reference browsing is not a preparation step.
For API/version mismatches return server_info and use this binary's reference.
"#
