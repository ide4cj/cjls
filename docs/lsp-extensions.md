<!-- cjls.lsp_ext hash: 062e3d097216c4f3 -->
# LSP extensions

Methods cjls answers beyond LSP (D15). Each is under `cjls/`, advertised as `true` under its name in the `experimental` server capabilities, and optional: every client works without it.

This file is the editor clients' contract (D32): its first line is the hash of `cjls.lsp_ext`, and `LspExtensionsDocTest` fails until a change there is described here and the hash moved.

## Initialization options

What a client may pass in `initialize`'s `initializationOptions`; all optional.

| Option | |
|---|---|
| `linkedProjects: string[]` | projects to load, as R1's: each an absolute path or a `file:` URI of a `cj-project.json`, or of a directory to find a project in. Under a root without a `cj-project.json`, they replace finding one there; outside every root, they are loaded besides (D33). |
| `cangjieHome: string` | the Cangjie SDK, an absolute path or a `file:` URI: looked for first, before `CANGJIE_HOME`, cjsdk's default toolchain and `cjc` on `PATH`; `std` is taken from it, and `${CANGJIE_HOME}` in a project's paths expands to it (D40). |
| `cangjieSrc: string` | the sources of the SDK's version, a directory holding `std/` as `cangjie_runtime`'s `stdlib/libs` does, an absolute path or a `file:` URI: looked for first, before `CANGJIE_SRC` and the SDK's `src`; go to definition on a declaration of `std` goes there (D65). `cjls fetch-src` puts them in the SDK's `src` (D69). |

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
