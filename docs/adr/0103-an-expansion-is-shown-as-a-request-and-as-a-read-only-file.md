# ADR-0103: An expansion is shown as cjls/expandMacro and as a read-only .cache/cjls/expanded/<file>.macrocall the server navigates

Status: accepted, 2026-10-20

## Context

- `loupe` knows what a macro call expands to (`macroCallAt`, `expandedMacro`), and can hover and go to definition in it (A35). The user needs a way to see it from each editor.
- rust-analyzer answers `rust-analyzer/expandMacro` (`{textDocument, position}` → `{name, expansion}`), and its VS Code client shows the result in a virtual document. Zed's expand macro calls that request by name, and only for rust-analyzer. Zed's extension API cannot send a custom request, nor add a command. So for Zed, a code action, an `executeCommand` and `window/showDocument` are the only path. Every client can take that path.
- cjc's `--debug-macro` writes `<file>.cj.macrocall`: the source file with its calls expanded. Users of cjc know that file.
- A document the server only reports cannot be navigated. For the server to answer requests in it, the document has to be a file the editor opens.

## Decision

- **`cjls/expandMacro`** answers rust-analyzer's params with `{name, expansion, kind}`. The text is formatted by cjformat (D60). An expansion that does not format is shown as the macro wrote it. One of std's, which cjls writes itself, starts with a comment saying it has signatures only.
- **The code action "Expand macro"** is offered on a call head with an expansion, to a client that takes `window/showDocument`. Its command `cjls.expandMacro` writes `expanded/<path under the project>.macrocall`, read-only, in the server's directory of the file's project, `<project>/.cache/cjls` (D106). The file is the source with each item a workspace call replaces swapped for its expansion, and each std expansion after its item, each after a comment naming the call. The command then asks the client to show the file, with the expansion selected.
- **The server navigates that file without remembering it.** For a document under `expanded/` of that directory, hover, definition and highlight make the file again from the snapshot (`loupe.expandFile`). The pieces of that file say where each one comes from: copied from the source, or an expansion as shown, an offset taken between formatted and written text by the bytes that are not whitespace. The request is answered only if the result is the editor's text, at the path the server would write it now. Otherwise the file is stale and the answer is `null`. The source changed, or the macro server answered again.

## Consequences

- No state outlives a request: a restart, or a file written by an earlier server, navigates as well while the editor holds it. The first server process to open the directory empties `expanded/` (D106), so such a file is gone from the disk.
- An expanded file the editor opened is in the `Vfs` as any document is. It is no file of the workspace: a snapshot lists none (workspace symbols), and it has no diagnostics.
- The editor must give `*.cj.macrocall` the Cangjie language, or the client never asks the server about the file.
- The file and its map are made again for each request in it: one `expandFile`, cjformat over each expansion.
