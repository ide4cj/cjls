package cjformat

import ginkgo.TextRange
import cjsyntax.*

/**
 * Formats the smallest complete statement/declaration enclosing the selected non-whitespace
 * bytes, or their enclosing body when several siblings are selected. An empty range selects
 * the node at the cursor. Syntax errors anywhere refuse formatting, as for the whole file.
 * The replacement can extend outside the requested range, but never outside the selected node
 * and its adjacent whitespace. Invalid byte ranges return no edits.
 */
public func formatRange(parse: CjParse, range: TextRange): ?Array<TextEdit> {
    if (!parse.errors.isEmpty()) {
        return None
    }
    let root = parse.syntaxNode()
    let text = root.text()
    if (range.start < 0 || range.end > text.size) {
        return Some([])
    }
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
    if (selected == root) {
        return format(parse)
    }
    // A range inherits the same group/continuation context as whole-file formatting, including
    // indentation introduced by assignments/match arms and space reserved for following punctuation.
    let position = LayoutPosition()
    Printer(LINE_WIDTH, lineBreakIn(text))
        .print(LayoutBuilder(text, target: Some(selected), position: Some(position)).node(root))
    let nodeRange = selected.textRange
    var from = nodeRange.start
    while (from > 0 && (text[from - 1] == b' ' || text[from - 1] == b'\t')) {
        from--
    }
    let isLineStart = from == 0 || text[from - 1] == b'\n'
    let result =
        Printer(LINE_WIDTH, lineBreakIn(text))
            .print(
                LayoutBuilder(text).node(selected, includeLeading: true),
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
    Some(
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
    )
}

func isRangeNode(n: CjSyntaxNode): Bool {
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

func isAsciiSpace(b: UInt8): Bool {
    b == b' ' || b == b'\t' || b == b'\r' || b == b'\n'
}

func isRangeBody(kind: SyntaxKind): Bool {
    match (kind) {
        case Block | DeclBody | EnumBody | PropBody | MatchBody | ForeignBlock => true
        case _ => false
    }
}
