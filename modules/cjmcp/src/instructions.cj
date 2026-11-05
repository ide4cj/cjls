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

Minimize total task token use without sacrificing correctness, evidence or
verification. Account for query code, returned data and repeated context.
Batch queries when useful; focused follow-up calls can avoid irrelevant output
or resolve uncertainty. Keep intermediate data in Python and return conclusions
with supporting paths/ranges, relevant source and explicit totals/omissions.
Use documented APIs before introspection; load a recipe for unfamiliar operations.

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

Select declarations/members before returning source:
result = source_excerpts(a, [(path, symbol.range)], max_bytes=12000)
The helper returns whole excerpts with path/line/range metadata and pagination.
Continue next_offset using the same ordered requests and revision; if blocked,
select a smaller range or increase max_bytes. Small full files are fine.
Keep full expected text inside Python for edits; return a compact diff and report.
For rankings, sort before limiting; compute global maxima first and preserve ties.

Include workspace.root, workspace.loadDiagnostics and workspace.macros with the
first useful query. These and workspace.diagnostics(path) serialize directly.
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
"#
