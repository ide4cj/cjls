<!-- cjls.lsp_ext hash: 062e3d097216c4f3 -->
# LSP extensions

Methods cjls answers beyond LSP (D15). Each is under `cjls/`, advertised as `true` under its name in the `experimental` server capabilities, and optional: every client works without it.

This file is the editor clients' contract (D32): its first line is the hash of `cjls.lsp_ext`, and `LspExtensionsDocTest` fails until a change there is described here and the hash moved.

## Settings

What `cjls --config-schema` prints, a JSON Schema with each setting's type, default and description; all optional (D79). A client passes them as `initializationOptions` and keeps them under the section `cjls` of its configuration: the server asks for that section (`workspace/configuration`) once initialized and on each `workspace/didChangeConfiguration`, or, from a client that cannot be asked, reads it in that notification's `settings.cjls`. `null` or `{}` leaves the settings as they were; any other object replaces them whole. Today: `linkedProjects` (D33), `cangjieHome` (D40), `cangjieSrc` (D65).

## `cjls/memoryUsage`

What the Cangjie runtime says of the server's heap, as numbers a driver can read, not a report in text. A request, client to server; capability `experimental.memoryUsage`.

| Params (all optional) | |
|---|---|
| `collect: boolean` | a full collection first, waited for: `allocatedHeap` is then what is held; `RequestFailed` if none has run in 5 s |
| `heapDump: string` | a heap dump written to that path first (after the collection), for `cjprof heap -i <path>`; `RequestFailed` if it cannot be |

No `heapDump` on Windows: `RequestFailed`, before any collection. There `dumpHeapData` never returns, with the nightlies of 2026-09-18 and 09-29 alike (#64); `collect` works as elsewhere.

| Result | `std.runtime` | |
|---|---|---|
| `usedHeap` | `getUsedHeapSize` | bytes of the heap's regions in use: what the heap takes of the process |
| `allocatedHeap` | `getAllocatedHeapSize` | bytes of the objects in them, live and not collected yet |
| `maxHeap` | `getMaxHeapSize` | bytes the heap may grow to |
| `gcCount`, `gcTime`, `gcFreed` | `getGCCount`, `getGCTime`, `getGCFreedSize` | collections since the start, their time in µs, the bytes they freed |
| `threads` | `getThreadCount` | Cangjie threads |

The collector runs on a timer (~150 ms), not on allocation, so between collections `allocatedHeap` and the process's RSS grow with the garbage of the interval (#22): what the server holds is `allocatedHeap` after `collect`.
