# Revision and execution failures

- Calls execute sequentially against a fixed revision through result serialization.
  Edits during execution become visible in a later call. `workspace.reload()` only
  requests preparation after the script; it cannot refresh the running script.
- The response's `revision`, `workspace.revision` and a newly captured
  `analysis.revision` agree. Old handles raise `RuntimeError` containing
  `ContentModified` after an update; reacquire analysis and recompute its identities.
  Revisions describe loaded analysis, not atomic filesystem snapshots.
- Inspect preparation problems before depending on expansion output. A transient
  hasExpandedMacros=false alone is not an error; queries independent of expansion
  can proceed without waiting. Missing SDKs, macro build or expansion
  failures appear in `workspace.problems` and can leave analysis partial. If
  preparation throws, Python does not run and the tool error has a null revision.
- Python/native callback failures appear in the tool's `error` traceback. Scripts
  are never replayed automatically. They may have performed external effects;
  inspect state before retrying. Join threads using analysis before returning.

- OutputBudgetExceeded means execution finished but the complete response exceeded
  maxOutputBytes (default 24000 UTF-8 JSON bytes). Filter last_output in a new call;
  do not replay effects. It includes the original revision and all output channels.
  Explicit maxOutputBytes=0 permits a full response. The error itself is exempt
  from the budget; see [API](../../../python-api.md) for retention and size semantics.
