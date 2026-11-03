# Revision and execution failures

- Calls execute sequentially against a fixed revision through result serialization.
  Edits during execution become visible in a later call. `workspace.reload()` only
  requests preparation after the script; it cannot refresh the running script.
- The response's `revision`, `workspace.revision` and a newly captured
  `analysis.revision` agree. Old handles raise `RuntimeError` containing
  `ContentModified` after an update; reacquire analysis and recompute its identities.
  Revisions describe loaded analysis, not atomic filesystem snapshots.
- Inspect workspace.loadDiagnostics and workspace.macros. The latter has state
  pending/settled and structured diagnostics: pending alone is not an error,
  and settled does not imply success. Check severity independently; warnings
  are preserved too. These objects serialize directly in result, including
  source, code, message and known path/range/line/column. Do not parse messages
  to recover locations; unknown fields remain None.
- Status describes the current script revision. Writes/reload do not turn it
  pending mid-script; reacquire in a later call. This implementation still
  serializes preparation with Python, so normal calls observe settled after
  preparation; the API distinguishes actual pending preparation from failures.
  No additional wait-for-expansion operation is required.
- Loading, SDK/build failures and expansion diagnostics can leave analysis partial.
  A preparation exception prevents Python execution and returns a null revision.
- Python/native callback failures appear in the tool's `error` traceback. Scripts
  are never replayed automatically. They may have performed external effects;
  inspect state before retrying. Join threads using analysis before returning.

- OutputBudgetExceeded means execution finished but the complete response exceeded
  maxOutputBytes (default 24000 UTF-8 JSON bytes). Filter last_output in a new call;
  do not replay effects. It includes the original revision and all output channels.
  Explicit maxOutputBytes=0 permits a full response. The error itself is exempt
  from the budget; see [API](../../../python-api.md) for retention and size semantics.
