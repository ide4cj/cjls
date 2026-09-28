# LSP extensions

Methods cjls answers beyond LSP (D15), as R1's `lsp-extensions.md`. Each is under `cjls/`, advertised as `true` under its name in the `experimental` server capabilities, and optional: every client works without it.

## `cjls/memoryUsage`

What the Cangjie runtime says of the server's heap, as numbers a driver can read (R1's `rust-analyzer/memoryUsage` answers a report in text). A request, client to server; capability `experimental.memoryUsage`.

| Params (all optional) | |
|---|---|
| `collect: boolean` | a full collection first, waited for: `allocatedHeap` is then what is held; `RequestFailed` if none has run in 5 s |
| `heapDump: string` | a heap dump written to that path first (after the collection), for `cjprof heap -i <path>`; `RequestFailed` if it cannot be |

| Result | `std.runtime` | |
|---|---|---|
| `usedHeap` | `getUsedHeapSize` | bytes of the heap's regions in use: what the heap takes of the process |
| `allocatedHeap` | `getAllocatedHeapSize` | bytes of the objects in them, live and not collected yet |
| `maxHeap` | `getMaxHeapSize` | bytes the heap may grow to |
| `gcCount`, `gcTime`, `gcFreed` | `getGCCount`, `getGCTime`, `getGCFreedSize` | collections since the start, their time in µs, the bytes they freed |
| `threads` | `getThreadCount` | Cangjie threads |

The collector runs on a timer (~150 ms), not on allocation, so between collections `allocatedHeap` and the process's RSS grow with the garbage of the interval (#22): what the server holds is `allocatedHeap` after `collect`.
