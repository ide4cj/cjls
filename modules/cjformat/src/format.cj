package cjformat

import std.deriving.Derive
import cjsyntax.{CjParse, SyntaxKind, parse}
import ginkgo.TextRange

const INDENT = 4
const LINE_WIDTH = 100

/**
 * A replacement in UTF-8 byte offsets.
 */
@Derive[Equatable, ToString]
public struct TextEdit {
    public TextEdit(public let range: TextRange, public let text: String) {}
}

/**
 * Formats a file using `options`. Returns no edits for canonical
 * input, or `None` for a file with syntax errors. Sorts and combines comment-free imports with
 * matching visibility and conditions, preserving every path, alias and duplicate. Wildcards
 * remain separate. All significant tokens outside imports are preserved.
 * Macro token trees and string contents retain their layout. Long indivisible text may overflow.
 */
public func format(parsed: CjParse, options!: FormatOptions = FormatOptions()): ?Array<TextEdit> {
    if (!parsed.errors.isEmpty()) {
        return None
    }
    let original = parsed.syntaxNode()
    let source = original.text()
    let imports = importEdits(original, source)
    let normalized = if (imports.isEmpty()) { source } else { applyEdits(source, imports) }
    let input = if (imports.isEmpty()) { parsed } else { parse(normalized) }
    if (!input.errors.isEmpty()) {
        throw IllegalStateException("import normalization introduced invalid syntax")
    }
    let root = input.syntaxNode()
    let result = Printer(
        lineBreakIn(source),
        width: options.lineWidth,
        indentWidth: options.indentWidth
    )
        .print(LayoutBuilder(normalized, options: options).node(root))
    Some(replacement(source, original.textRange, result))
}

/**
 * Formats source text, or returns `None` when parsing reports syntax errors.
 */
public func formatText(text: String, options!: FormatOptions = FormatOptions()): ?String {
    applyEdits(text, format(parse(text), options: options) ?? return None)
}

/**
 * Applies ordered, non-overlapping edits to `text`. Offsets must be valid UTF-8 boundaries.
 */
func applyEdits(text: String, edits: Array<TextEdit>): String {
    let out = StringBuilder()
    var at = 0
    for (edit in edits) {
        out.append(text[at..edit.range.start])
        out.append(edit.text)
        at = edit.range.end
    }
    out.append(text[at..])
    out.toString()
}

/**
 * Returns one minimal replacement with endpoints on UTF-8 boundaries, or no edits.
 */
func replacement(source: String, range: TextRange, result: String): Array<TextEdit> {
    let previous = source[range.start..range.end]
    if (previous == result) {
        return []
    }
    var first = 0
    while (first < previous.size && first < result.size && previous[first] == result[first]) {
        first++
    }
    while (first > 0 && first < result.size && (result[first] & 0xC0) == 0x80) {
        first--
    }
    var oldEnd = previous.size
    var newEnd = result.size
    while (oldEnd > first && newEnd > first && previous[oldEnd - 1] == result[newEnd - 1]) {
        oldEnd--
        newEnd--
    }
    while (newEnd < result.size && (result[newEnd] & 0xC0) == 0x80) {
        oldEnd++
        newEnd++
    }
    [TextEdit(TextRange(range.start + first, range.start + oldEnd), result[first..newEnd])]
}

/**
 * Uses CRLF when present in the source, otherwise LF.
 */
func lineBreakIn(text: String): String {
    if (text.contains("\r\n")) { "\r\n" } else { "\n" }
}

/**
 * Whether a token is whitespace that layout may replace.
 */
func isSpace(kind: SyntaxKind): Bool {
    kind == SyntaxKind.Whitespace || kind == SyntaxKind.Newline
}

/**
 * Whether a token carries a line or block comment.
 */
func isComment(kind: SyntaxKind): Bool {
    kind == SyntaxKind.LineComment || kind == SyntaxKind.BlockComment
}
