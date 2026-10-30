<!-- cjls.lsp_ext hash: bda1bf40521e1341 -->
# LSP extensions

Methods cjls supports beyond LSP (D15). Each is under `cjls/`, advertised as `true` under its name in the `experimental` server capabilities, and optional: every client works without it.

This file is the editor clients' contract (D32): its first line is the hash of `cjls.lsp_ext`, and `LspExtensionsDocTest` fails until a change there is described here and the hash moved.

## Settings

What `cjls --config-schema` prints, a JSON Schema with each setting's type, default and description; all optional (D79). A client passes them as `initializationOptions` and keeps them under the section `cjls` of its configuration: the server asks for that section (`workspace/configuration`) once initialized and on each `workspace/didChangeConfiguration`, or, from a client that cannot be asked, reads it in that notification's `settings.cjls`. `null` or `{}` leaves the settings as they were; any other object replaces them whole. Today: `linkedProjects` (D33), `cangjieHome` (D40), `cangjieSrc` (D65), `newFilePackage` (D92).

Path settings (`linkedProjects`, `cangjieHome`, `cangjieSrc`) accept `~` or a leading
`~/` (`~\` on Windows) for the home directory (`HOME`, falling back to
`USERPROFILE`), and `${VAR}` or `$VAR` for variables in the server process's
environment. For example, `"cangjieHome": "~/.cjpm/toolchains/default"` or
`"cangjieSrc": "${SDK_SOURCES}/stdlib/libs"`. Expansion happens once and must
produce an absolute path. Missing variables are reported and the affected value
is ignored. `file:` URIs are literal and are not expanded; `~user` and other shell
expressions are not supported. Variables supplied by an editor (such as VS Code's
`${workspaceFolder}`) must be resolved by that editor before sending settings.

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

## `cjls/analysisStats`

The work the analysis has done, counted rather than timed: read before and after a request, the difference is what that request cost, the same on every machine and every run (`tests/perf` sets its threshold on it, D81). A request, client to server, without params; capability `experimental.analysisStats`.

| Result | |
|---|---|
| `queriesExecuted` | how many times a query was computed since the server started, rather than taken from what the analysis remembered (calca's `Storage.executions`), on every thread |

A request's count is its own only while nothing else runs: a client pulling diagnostics, after the workspace has loaded, and one request at a time.

## `cjls/expandMacro`

What the macro call at a position expands to, as rust-analyzer's `rust-analyzer/expandMacro` answers it (D103). A request, client to server; capability `experimental.expandMacro`.

| Params | |
|---|---|
| `textDocument: TextDocumentIdentifier`, `position: Position` | a position on a call's head (`@`, its name, its attribute), or anywhere in a declaration with calls on it, as rust-analyzer's: the outermost call of the innermost such declaration that expands |

| Result, or `null` off a call, or on one nothing expands yet | |
|---|---|
| `name: string` | the macro as the call writes it: `@Derive`, `@m.M` |
| `expansion: string` | the expansion, formatted as `cjls fmt` formats (D150) |
| `kind: string` | `server`: the macro server's output, for a macro of the workspace or of std (D123); `cjls`: cjls's own for one of std the server has not expanded, signatures only, after a comment line saying so and the declaration it adds to, as cjc's output starts with it |

A call inside the input of another (D98) answers the expansion of that one, the call read.

## Command `cjls.expandMacro`

The code action "Expand macro" (no `kind`) is offered where `cjls/expandMacro` answers, but in a body of the declaration, where it would be offered at every line, to a client that takes `window/showDocument` and asks for no kind in particular (`context.only`). Its command, which `workspace/executeCommand` runs (`executeCommandProvider.commands`), takes one argument, the `TextDocumentPositionParams` of the call. It writes `<project>/.cache/cjls/expanded/<path under the project>.macrocall`, read-only, in the server's directory of the document's project (D106). The file is the document with each item a call the server ran replaces swapped for its expansion, and each of cjls's own expansions of std after its item, each after a comment naming the call. The command then sends `window/showDocument` (`takeFocus`, the call's expansion selected) and answers `null`. To a client without `window/showDocument` it is `RequestFailed`.

In that file, while it is what the server would write now, `textDocument/hover`, `textDocument/definition`, `textDocument/typeDefinition` and `textDocument/documentHighlight` answer as in the source for what was copied from it, and as in the expansion for an expansion. `textDocument/references` and `textDocument/implementation` answer as in the source for what was copied from it, and `null` in an expansion, their locations in the files. Once the source or an expansion changed, they answer `null` until the command writes the file again. The file has no diagnostics. A client gives `*.cj.macrocall` the Cangjie language, or it never asks.

## `cjls/binarySourceRoots`

A notification from server to client; capability `experimental.binarySourceRoots`.
Params: `{ "roots": ["file:///path/to/sdk/src/std", ...] }`. Each URI names the
root directory of sources attached to a binary in the merged project model.
Compiled source modules, including path dependencies, do not contribute roots.

The server sends the complete replacement list when a current workspace load
commits its project, before loading its source files. An empty workspace sends
`[]`; an obsolete load never sends a replacement. Order is unspecified and roots
are deduplicated. Clients handle notifications from initialization onward, apply
them to existing and subsequently opened documents, and clear their roots when
the server stops or restarts. A file is covered by directory containment, not a
raw URI prefix (`std-other` is not under `std`).

Clients protect covered files in the editor and remove their protection when a
file is no longer covered. Real sources keep their `file:` URIs and filesystem
permissions. Neovim uses buffer-local `readonly` and `nomodifiable`; VS Code uses
its session readonly command when the editor becomes active. Zed's extension API
0.7.0 has no custom notification handler or buffer readonly setter, so its client
cannot currently enforce this ([API source](https://github.com/zed-industries/zed/blob/main/crates/extension_api/src/extension_api.rs)).

Readonly is presentation: open source documents retain their existing diagnostics
behavior. This notification does not change analysis or navigation context (#492).
