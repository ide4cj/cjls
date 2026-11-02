# Runtime details

- Assign JSON-serializable values to `result`, or print a compact answer. Native
  objects are not JSON dictionaries and cannot be returned directly.
- Each call has fresh Python globals. The loaded workspace persists. Obtain
  `analysis = workspace.analysis()` in each script that uses revision queries.
- Disk inputs and required macro expansions are synchronized automatically before
  each script. Between calls, a worker polls for changes every 500 ms. Query caches,
  build artifacts and SDK processes persist for the MCP session.
- The database stays fixed throughout the script and result serialization. Edits
  made during execution become visible to a later call. `workspace.reload()` only
  requests preparation after the script; it never refreshes a running script.
- The tool response's `revision`, `workspace.revision` and a newly captured
  `analysis.revision` agree. After a workspace update, older analysis handles raise
  `RuntimeError` containing `ContentModified`; reacquire a handle and its identities.
  Revision numbers describe loaded analysis, not an atomic snapshot of live disk.
- Keep all identities (`DefId`, `Ty`, `FileId`, macro calls) with their producing
  revision. Do not mix values from separate revisions.
- Paths may be absolute or relative to `workspace.root`. Offsets count UTF-8
  bytes from zero, must fall on character boundaries, and exclude range ends.
  Slice `analysis.text(path).encode("utf-8")`, not the Python string, with them.
- Preparation finishes before Python runs. Inspect `workspace.problems` and
  `workspace.hasExpandedMacros`; a usable answer may still be partial. If preparation
  throws, Python does not run and the tool error has a null `revision`.
- Python/native callback failures are reported through the tool's `error`
  traceback. Python has ordinary imports and local I/O, without a sandbox or
  hard timeout. Calls execute sequentially and scripts are never replayed
  automatically. Join any Python threads using analysis before the script returns.

