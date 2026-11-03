# Formatter configuration

`cjls fmt`, LSP whole-file/range formatting and all three code generators read
`cjformat.toml`. For each source file (or generated output), the nearest config
in its parent directory or an ancestor wins. Relative CLI paths use the working
directory. A config replaces its ancestors; missing keys use these defaults:

```toml
line_width = 100
indent_width = 4
simple_if = "multiline"
```

`line_width` counts Unicode scalars; `indent_width` sets spaces per indentation
level. Both must be positive integers. Indivisible strings, names, comments and
protected macro text may exceed the requested width.

Call arguments wrap independently of a short callee. A single member call keeps
`receiver.method(` together when that prefix fits; call initializers likewise
stay beside `=` when their first line fits. Otherwise the assignment or member
access uses a continuation line. Long method chains still break before dots.
These layout rules apply with every configuration; no extra setting is needed.

`simple_if = "compact"` permits this layout when the entire expression fits:

```cangjie
let start = if (range.hasStart) { range.start } else { 0 }
```

Both branches must contain exactly one expression and no comments. Longer
expressions, multiple statements and `else if` retain multiline layout. Use
`"multiline"` to expand all nonempty control bodies.

Imports are normalized without semantic analysis. Consecutive comment-free imports
sort `std`, `stdx`, dependencies and packages of the current module in that order,
then packages and members alphabetically. The module is identified by the first
package component in the file's `package` header (including its organization
qualifier, if any). Without a package header, all non-standard imports belong to
the dependency group. Import-only ranges retain the file's module context.
Explicit imports from the same package combine into one list;
visibility and annotation tokens must match. This includes `public import` and
identical `@When` conditions. Singleton explicit-name lists lose redundant braces
unless they carry a trailing comma. Explicit-name groups retain trailing commas
when combined.

Wildcard imports use separate standalone declarations, including when extracted
from a grouped import. Every path, alias and
duplicate is retained; unused imports are not removed. Comments inside or attached
to a declaration and inline trailing comments anchor that declaration. Other
comments, semicolons and non-import syntax separate runs; blank lines alone do not.
An import-only range normalizes just the enclosing selected imports, preserving
other imports and code outside the selection.

Unknown keys, wrong types, invalid values and malformed TOML are errors. The CLI
reports the config path and skips that file with a failing exit code. The LSP
returns a failed formatting request. Other CLI files can still be formatted.

Editor indentation options do not override the project policy. Documents without
a disk path use defaults. Save config changes to apply them on the next formatting
request; unsaved config buffers are not read. Generators discover config from the
final output location and format in memory without a formatter subprocess.

Library callers pass `FormatOptions` to `format`, `formatText` or `formatRange`.
These functions do not read files. `cjformat.config.optionsFor` is the explicit
filesystem loader for callers that need project discovery.

## Repository checks

CI and the pre-push hook check `build.cj` and `modules` explicitly. The native
Cangjie inputs under `tests/semantic/cases` are negative oracle fixtures: syntax
errors, source layout and comment annotations are intentional and must remain
verbatim. Format individual product files or use:

```bash
target/release/bin/cjls fmt --check build.cj modules
```
