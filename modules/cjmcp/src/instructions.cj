package cjmcp

// Keep the playbook in the executable so clients need no checkout or installed skill.
let agentInstructions =
    #"
# cjmcp: semantic analysis for Cangjie

Use runPython before exploring or changing Cangjie code to locate declarations,
resolve types and calls, and inspect usages. Compose native loupe queries in one
Python script; filter and aggregate there, then return only the evidence needed.
If your client defers tool schemas, discover runPython before concluding that
analysis is unavailable. Use the tool name as exposed by your client.

## Start and discover

workspace and native types are already injected; do not import loupe. Each call
has fresh Python globals. Start by returning workspace.root, workspace.problems,
workspace.hasExpandedMacros and a bounded sample of workspace.files(). Check the
root is the checkout you are editing. Capture a = workspace.analysis() in each
script using analysis queries. Discover unfamiliar members with dir(type(value))
or dir(KnownType); inspect one returned value rather than dumping every type.
Native objects have attributes, arrays become lists, options become None.
Enum variants support isinstance(value, Expr.CallExpr), .kind and field0, field1,
etc. Convert native values to JSON primitives before assigning result, or print
compact output. The response includes result, stdout, stderr, revision and error.

## Choose the query

- Find a declaration: a.symbols(query, limit) searches case-insensitive name
  subsequences; inspect candidates' .symbol.name and .symbol.selectionRange.
  Resolve .fileId with a.path(fileId). workspace.structure(path) gives nested
  declarations through .children; a.declarations(path) includes nested DefIds.
- Read source: a.text(path) is this revision's text. Use the relevant declaration
  range, rather than reading whole files again after obtaining its source.
- Navigate: workspace.definition(path, offset), a.references(path, offset),
  a.typeDefinition(path, offset), a.implementations(path, offset). References
  include declarations (.isDeclaration); distinguish them when counting usages.
- Understand behavior or change impact: resolve the symbol first, then batch
  references and relevant source. a.item(def), a.signature(def),
  a.signatureTypes(def), a.body(def), a.scopes(def) and a.infer(def) expose HIR,
  scope and inferred types. Inference .callees contains selected targets with
  .decl, .expr and .isInitializer; this is not a complete dynamic call graph.
- Inspect types: a.typeText(ty), a.typeKind(ty), a.isTypeUnknown(ty),
  a.members(def, name), a.supertypes(def), a.receiverType(def, expr).
  Distinguish TyKind.ErrorTy (user error), TodoTy (unsupported analysis) and
  UnknownTy (missing input or inference limit); a display string can hide this.
- Investigate errors: workspace.diagnostics(path), workspace.hover(path, offset),
  a.completions(path, offset), a.completionDetails(path, offset, item).
- Macros: a.macroCall(path, offset), a.expansion(call), a.loweredBody(def).
  Expansion-relative ranges are not offsets into the original file.

## Correctness and efficient use

Offsets are zero-based UTF-8 bytes with exclusive ends. Slice
source = a.text(path).encode('utf-8'); source[start:end].decode('utf-8').
Python string indices and editor line/column positions are not byte offsets.
Keep DefId, Ty, FileId and macro identities with their producing revision.
Inputs and macros synchronize before each call and remain fixed through result
serialization. After disk edits, make a new call and reacquire analysis and IDs;
workspace.reload() only requests a refresh AFTER the current script. Older
analysis handles raise ContentModified after an update. Save editor buffers first.

Check workspace.problems and hasExpandedMacros before claiming completeness.
An empty or partial answer is not proof of no usages or no errors. Narrow the
query, inspect candidates or report the missing coverage. Use text search for
configs, docs, literals and gaps in analysis; do not reconstruct resolved usages
by grepping names or repeat successful semantic lookups just to verify them.
Bound traversals as well as output; avoid whole-workspace HIR dumps. Native
proxies currently retain values for the session. Calls run sequentially.

Edit files with the client's normal editing tools, then use a fresh runPython
call to check affected diagnostics and usages. Run the project's compiler/tests
for validation; analysis is experimental and does not replace them. cjmcp has
no dedicated rename, refactoring, build or test API. Ordinary Python imports and
local I/O are available with process permissions, without a sandbox or hard
execution timeout. Errors may follow partial external effects: inspect the
traceback and state before retrying a script that writes or starts processes.
"#
