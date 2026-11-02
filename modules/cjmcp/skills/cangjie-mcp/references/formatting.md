# Preview formatting edits

Formatting returns edits without writing files or reading formatter config.
`None` means syntax errors; `[]` means the text is already canonical. Pass
`FormatOptions` explicitly for a policy other than the library defaults. Apply
non-overlapping edits from the end when constructing a preview from UTF-8 bytes:

```python
analysis = workspace.analysis()
path = "src/main.cj"
options = FormatOptions(lineWidth=100, indentWidth=2, simpleIf=SimpleIf.Compact())
edits = analysis.formatting(path, options=options)
data = analysis.text(path).encode("utf-8")
if edits is not None:
    for edit in reversed(edits):
        data = data[:edit.range.start] + edit.text.encode("utf-8") + data[edit.range.end:]
result = {"preview": None if edits is None else data.decode("utf-8")}
```

`rangeFormatting(path, TextRange(start, end), options=options)` formats the
complete enclosing syntax node. Both endpoints must be valid UTF-8 boundaries
inside the revision text. `newFilePackageLine(path)` suggests a header for a new
file without creating it; it also recognizes macro packages.
`formatting(path)` and `rangeFormatting(path, range)` use the library defaults.
`FormatOptions()` uses those same defaults; `FormatOptions(indentWidth=2)` changes
only indentation. Unknown keywords and incompatible argument types raise `TypeError`.
