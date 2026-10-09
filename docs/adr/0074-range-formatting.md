# ADR-0074: A range is formatted by the whole file's edits on the lines it covers

Status: proposed

## Context

- D60 left `textDocument/rangeFormatting` unserved. Neovim sets `formatexpr` to `vim.lsp.formatexpr()` only for a server that serves it, so `gq` needed a formatter of the client's own: cangjie.nvim ran `cjfmt`, whose style D60 rejects.
- Neovim asks for whole lines (column 0 to the end of the last); VS Code's selection of whole lines ends at column 0 of the line after.
- An edit of `cjformat.format` is a run of whitespace; one across a line break is the end of a line (trailing whitespace, blank lines) and the indent of the next.

## Decision

- **The whole file is formatted and the edits on the covered lines are returned** (`cjformat.formatRange`): a line's indent depends on the brackets open before it, so a range is never formatted alone. A file with syntax errors anywhere gets `null`, as for `formatting`.
- **An edit across a line break is split at its last one**, each part kept if its line is covered: the end of a line covered is formatted, the indent of the line after it is not, and the trailing whitespace of the line before the range stays.
- **A range ending at column 0 does not cover that line**; one inside a line covers the line.

## Consequences

- `gq` in Neovim formats with cjls without a line of the plugin; cangjie.nvim drops `cjfmt`.
- The cost of a range is the file's: the tree is the database's, formatting it is linear.
