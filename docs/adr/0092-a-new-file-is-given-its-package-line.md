# ADR-0092: A document opened blank is given its package line

Status: proposed

## Context

- A file of a package other than `default` starts with `package <name>`, and the name follows from its directory under the module's sources (`packagesUnder`, D33). #294 asks for the line to be written for the user.
- What other servers do, read in their sources (#294):
  - gopls registers `workspace.fileOperations.didCreate` and sends `workspace/applyEdit` on `workspace/didCreateFiles` of an empty file. The setting `newGoFileHeader` turns it off.
  - Metals sends the edit on `textDocument/didOpen` of a file empty on disk and in the buffer, of the document's version.
  - vscode-java and kotlin-lsp write the line in their VS Code extensions, from the source paths or a template the server fills.
- What Neovim 0.12.5 sends, probed with a stub server:
  - It declares `fileOperations.didCreate: false` and sends no `didCreateFiles`, neither on `:e new.cj` nor on `:w`.
  - It opens a file not on disk yet, and an empty one, with the text `"\n"`.
  - It applies `workspace/applyEdit` and does not declare `workspaceEdit.documentChanges`.

## Decision

- **On `didOpen`, as Metals does, not on `didCreateFiles`.** Every editor sends `didOpen`, and Neovim sends nothing else for a file new. Answering both would give one file two edits.
- **A document is new when its text is whitespace alone**, whatever the disk holds: Neovim's `"\n"` for a file not written yet.
- **The name comes from the project last loaded** (`ProjectModel.packageOfNewFile`):
  - that of a package in the file's directory, unless it is `default`;
  - else, under the nearest module whose packages are each named after their directory (cjpm's, never loose files'), the module's name and the directories down to the file's.
  - None when a directory's name is not an identifier, or no module holds the file.
- **A document opened while a load runs is given its line when the load ends**, if it is still open and blank.
- **The whole blank text is replaced by `package <name>\n\n`.** The edit carries the version opened when the client declares `documentChanges`, so an editor typed in since refuses it. Otherwise it goes as `changes`, after the text was checked blank on the loop.
- **The setting `newFilePackage`** (D79), on by default, turns it off. Changing it finds no project again: only `linkedProjects`, `cangjieHome` and `cangjieSrc` do.

## Consequences

- An empty `.cj` opened on purpose is given the line too; the setting is the way out.
- A file created and never opened gets nothing, unlike gopls.
- A client without `documentChanges`, such as Neovim, takes an edit of no version: a keystroke between the check and the edit is overwritten.
