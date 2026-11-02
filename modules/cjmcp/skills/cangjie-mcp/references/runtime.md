# Revision and execution failures

- Calls execute sequentially against a fixed revision through result serialization.
  Edits during execution become visible in a later call. `workspace.reload()` only
  requests preparation after the script; it cannot refresh the running script.
- The response's `revision`, `workspace.revision` and a newly captured
  `analysis.revision` agree. Old handles raise `RuntimeError` containing
  `ContentModified` after an update; reacquire analysis and recompute its identities.
  Revisions describe loaded analysis, not atomic filesystem snapshots.
- Preparation completes before Python runs. Missing SDKs, macro build or expansion
  failures appear in `workspace.problems` and can leave analysis partial. If
  preparation throws, Python does not run and the tool error has a null revision.
- Python/native callback failures appear in the tool's `error` traceback. Scripts
  are never replayed automatically. They may have performed external effects;
  inspect state before retrying. Join threads using analysis before returning.
