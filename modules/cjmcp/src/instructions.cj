package cjmcp

// Keep evidence selection and executable common queries ahead of API discovery.
let agentInstructions =
    #"
Use runPython for Cangjie source analysis, reading and editing. Shell is for
Git, builds, tests and non-Cangjie files; report partial analysis without a shell
fallback. workspace and native types are injected; do not import loupe.

Choose evidence in this order:
1. Query the analysis database for syntax and semantics. Select declarations and
   resolved references/types/hierarchies; use syntax nodes for expression shape,
   nesting and edit boundaries. Reuse the matching cangjie-mcp task recipe before
   inventing a traversal (references/semantic.md, navigation.md, refactoring.md,
   editing.md). Simple queries below need no preparation lookup.
2. If a recipe or query leaves a specific API contract unknown, use targeted
   bundled .pyi lookup (references/discovery.md). Check server_info for a version
   mismatch; do not infer missing capability from an unfamiliar API name.
3. Only after identifying a concrete analysis/API gap, use a bounded textual
   fallback inside Python and label its limits. Do not reconstruct declarations,
   usages, inheritance or block boundaries with re, substring tests or splitlines
   when database queries or syntax nodes provide them. Text search is also useful
   for literals/comments, candidate discovery and an additional residual-name
   check; a textual match does not establish a symbol relationship.

For a refactor, read references/refactoring.md and editing.md; establish affected
identities, implementations and usages before writing. Apply text transformations
within selected source ranges with expected-text checks. An empty query result
is not proof of completeness: inspect unresolved/macro/contextual gaps.
Compose related queries in Python and keep intermediate objects there. Return
bounded evidence with paths/ranges, totals and omissions; follow up on uncertainty.
Minimize total tokens without truncating searches or weakening verification.

Pass root=<absolute project/worktree> on every call outside the configured --dir;
omission always selects --dir. Verify root/sessionId; four roots are cached,
eviction closes a session and reopening gives a new ID. Revision and last_output
belong to that session. Calls are sequential; Python globals are fresh each call.
Capture a = workspace.analysis() per call. Include workspace.root,
workspace.loadDiagnostics and workspace.macros with the first useful query.
MacroState.Pending()/Settled() describe completion, not severity. Retry missing
expansion-dependent evidence when needed; no blanket expansion wait is required.

Core queries (ranges are UTF-8 bytes, end-exclusive):
- exact_symbols(a, paths, name) -> all exact (path, symbol) matches in explicit
  files. a.symbols(name, limit) is fuzzy; a full limit may omit exact matches.
  api_docs.find_symbol("ExportedType.member") locates an unknown reference path.
- a.fileSymbols(path), workspace.structure(path) -> declarations; structure nodes
  have .name, .kind, .range, .selectionRange and nested .children.
- a.references(path, offset) -> .fileId, .range, .isDeclaration;
  workspace.definition(path, offset), hover(path, offset), diagnostics(path).
- s = a.semantic(); s.at(a.fileId(path), offset) retains occurrence resolution and
  contextualFile(); s.project() traverses modules, packages and dependencies.
  s.syntaxAt(a.fileId(path)).root() gives syntax; children()/descendants(),
  kindName(), location(), mappings() connect exact syntax to HIR. See semantic.md.
- a.declarations(path) -> DefIds; a.item(defId), a.body(defId), a.infer(defId),
  a.typeKind(ty), a.typeText(ty). See inference.md for aligned arrays, selected
  callees and unavailable ranges; source-maps.md for written signature types.
- a.members(defId, name), a.allMembers(defId), a.supertypes(defId),
  a.implementations(path, offset); see members.md for native member variants.
- a.prepareCallHierarchy(path, offset), a.incomingCalls(entry), a.outgoingCalls(entry)
  -> grouped call sites; see calls.md.
- a.macroCall(path, offset) -> call or None; a.expansion(call.call) -> .text or None.
  a.expandedFile(path, header) requires a header string. See expansions.md for
  navigation: target .expansion ranges belong to expansion text, not source text.
- a.formatting(path), a.rangeFormatting(path, TextRange(start, end)) -> edits or None;
  options=FormatOptions(indentWidth=2) overrides defaults. These never write.
- a.text(path) reads loaded revision text. workspace.files() includes dependencies;
  filter by path components relative to workspace.root, not absolute substrings.
  workspace.sdk is the selected SDK or None; project its fields explicitly.
Other editor queries and builtin docs: references/members.md and python-api.md.

Use result_page(projected_rows, limit=20) for compact rows with totals/omissions.
Forward only MCP structuredContent, or content when absent, never both copies.
At an extend's type name, references means uses of that type; select the member
name for member usages. AmbiguousMeaning references are candidates, not proven
calls. Inspect occurrence.resolution() before asserting dependency relationships.

Select the smallest relevant declarations/nodes before returning source:
result = source_excerpts(a, [(path, symbol.range)], max_bytes=12000)
Follow next_offset with the same requests/revision; if blocked, select a smaller
range or raise max_bytes. Small full files are fine. Keep expectedText in Python.
Diagnostic/status/range/severity values serialize directly; other native objects
need explicit field projection. Sort before limiting rankings and preserve ties.

For whole-declaration edits use declaration_range(a, path, selectionRange,
"FuncDecl"): it includes enclosing MacroExpandDecl annotations such as @TestCase.
Outline ranges and even FuncDecl.fullRange can exclude those wrappers.
Use workspace.applyChange(SourceChange([...]), a.revision) for project edits:
FileChange.EditFile(path, expectedText, [TextEdit(range, text)]),
FileChange.CreateFile(path, text), FileChange.RenameFile(path, target, expectedText),
FileChange.DeleteFile(path, expectedText). Formatting edits pass through directly.
Inspect report.isSuccess, applied, failed and error; str(report) is not a report.
Validation precedes writes; I/O failures may leave partial changes. For direct
pathlib writes to loaded files, compare disk bytes with revision text first.
In a NEW call after writing, reacquire analysis/IDs and verify changed relationships
and diagnostics. The writing call retains its old revision. Run compiler/tests.

maxOutputBytes defaults to 24000 UTF-8 JSON bytes across all response channels.
OutputBudgetExceeded happens AFTER execution: inspect outputBudget.largest_fields
and select from last_output in a new call; never replay effects to recover output.
Saved output may be from an older revision. Larger limits are supported; 0 is unlimited.
"#
