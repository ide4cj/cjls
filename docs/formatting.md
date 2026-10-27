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

`simple_if = "compact"` permits this layout when the entire expression fits:

```cangjie
let start = if (range.hasStart) { range.start } else { 0 }
```

Both branches must contain exactly one expression and no comments. Longer
expressions, multiple statements and `else if` retain multiline layout. Use
`"multiline"` to expand all nonempty control bodies.

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
