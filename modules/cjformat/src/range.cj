package cjformat

import cjsyntax.{CjParse, CjSyntaxNode, SyntaxKind}
import ginkgo.TextRange

/**
 * Formats the smallest complete statement/declaration enclosing the selected non-whitespace
 * bytes, or their enclosing body when several siblings are selected. An empty range selects
 * the node at the cursor. Syntax errors anywhere refuse formatting, as for the whole file.
 * The replacement can extend outside the requested range, but never outside the selected node
 * and its adjacent whitespace. Invalid byte ranges return no edits.
 */
public func formatRange(
    parse: CjParse,
    range: TextRange,
    options!: FormatOptions = FormatOptions()
): ?Array<TextEdit> {
    if (!parse.errors.isEmpty()) {
        return None
    }
    let root = parse.syntaxNode()
    let text = root.text()
    if (range.start < 0 || range.end > text.size) {
        return Some([])
    }
    let selected = rangeNode(root, text, range)
    if (selected == root) {
        return format(parse, options: options)
    }
    formatNode(root, selected, text, options)
}

/**
 * Finds the smallest complete range target after trimming selection whitespace.
 */
private func rangeNode(root: CjSyntaxNode, text: String, range: TextRange): CjSyntaxNode {
    var start = range.start
    var end = range.end
    while (start < end && isAsciiSpace(text[start])) {
        start++
    }
    while (end > start && isAsciiSpace(text[end - 1])) {
        end--
    }
    var selected = root
    for (n in root.descendants()) {
        if (n.textRange.start <= start && end <= n.textRange.end && isRangeNode(n)) {
            // Brace placement belongs to the enclosing declaration/expression. A selection of
            // only body contents can leave that header untouched.
            if (isRangeBody(n.kind) && (start <= n.textRange.start || end >= n.textRange.end)) {
                continue
            }
            if (n.textRange.len <= selected.textRange.len) {
                selected = n
            }
        }
    }
    selected
}

/**
 * Reprints a target in the indentation and continuation context of its whole file.
 */
private func formatNode(
    root: CjSyntaxNode,
    selected: CjSyntaxNode,
    text: String,
    options: FormatOptions
): Array<TextEdit> {
    // A range inherits the same group/continuation context as whole-file formatting, including
    // indentation introduced by assignments/match arms and space reserved for following punctuation.
    let position = LayoutPosition()
    Printer(lineBreakIn(text), width: options.lineWidth, indentWidth: options.indentWidth)
        .print(
            LayoutBuilder(text, options: options, target: Some(selected), position: Some(position))
                .node(root)
        )
    let nodeRange = selected.textRange
    var from = nodeRange.start
    while (from > 0 && (text[from - 1] == b' ' || text[from - 1] == b'\t')) {
        from--
    }
    let isLineStart = from == 0 || text[from - 1] == b'\n'
    let result =
        Printer(lineBreakIn(text), width: options.lineWidth, indentWidth: options.indentWidth)
            .print(
                LayoutBuilder(text, options: options).node(selected, includeLeading: true),
                indentation: position.indentation,
                column: if (isLineStart) {
                    0
                } else {
                    position.column
                },
                lineIndent: position.lineIndent,
                reserved: position.reserved
            )
    var to = nodeRange.end
    while (to < text.size && (text[to] == b' ' || text[to] == b'\t')) {
        to++
    }
    if (to < text.size && text[to] != b'\n' && text[to] != b'\r') {
        to = nodeRange.end
    }
    var output =
        if (isLineStart) {
            result
        } else {
            result.trimAsciiStart()
        }
    if (text[to..].trimAscii().isEmpty()) {
        to = text.size
        output = "${output.trimAsciiEnd()}${lineBreakIn(text)}"
    }
    replacement(
        text,
        TextRange(
            if (isLineStart) {
                from
            } else {
                nodeRange.start
            },
            to
        ),
        output
    )
}

/**
 * Whether a node can be selected independently without entering protected syntax.
 */
private func isRangeNode(n: CjSyntaxNode): Bool {
    for (ancestor in n.ancestors()) {
        if (isOpaque(ancestor.kind)) {
            return false
        }
    }
    match (n.kind) {
        case Block | DeclBody | EnumBody | PropBody | MatchBody | ForeignBlock => return true
        case _ => ()
    }
    let parent = n.parent ?? return true
    match (parent.kind) {
        case SourceFile |
            Block |
            DeclBody |
            EnumBody |
            PropBody |
            MatchBody |
            ForeignBlock |
            LambdaExpr => !isOpaque(n.kind) && n.kind != LambdaParamList && n.kind != Annotation
        case _ => false
    }
}

/**
 * Whether a byte is layout whitespace around a selection.
 */
private func isAsciiSpace(b: UInt8): Bool {
    b == b' ' || b == b'\t' || b == b'\r' || b == b'\n'
}

/**
 * Whether a node owns a sequence of statements or declarations.
 */
private func isRangeBody(kind: SyntaxKind): Bool {
    match (kind) {
        case Block | DeclBody | EnumBody | PropBody | MatchBody | ForeignBlock => true
        case _ => false
    }
}
