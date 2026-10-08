package cjformat

import std.collection.ArrayList
import std.deriving.*
import ginkgo.{SyntaxElement, TextRange}
import cjsyntax.*

/**
 * The columns one level of indentation takes.
 */
const INDENT = 4

/**
 * `range` of the text replaced by `text`; `range` is in UTF-8 bytes.
 */
@Derive[Equatable, ToString]
public struct TextEdit {
    public TextEdit(public let range: TextRange, public let text: String) {}
}

/**
 * The edits that format a file, in order and apart; `None` when it has syntax errors, as what the
 * formatter would make of them is a guess.
 *
 * Only whitespace changes, and only where a line starts or ends: the line breaks are the author's.
 * A line is indented by the brackets open at its start, one level for all those opened on one line,
 * and one more when it carries on what an earlier line started; a declaration's or a statement's
 * `{}` is indented from the line it starts on, as is what follows the `=>` of a `case`. What a macro
 * reads as tokens (`quote(...)`, a macro call's `(...)` and `[...]`) and a string's interpolations
 * keep their layout, moved as a whole. Trailing whitespace goes, blank lines are kept to one, and
 * the file ends in one line break.
 */
public func format(parse: CjParse): ?Array<TextEdit> {
    if (!parse.errors.isEmpty()) {
        return None
    }
    Some(Formatter(parse.syntaxNode()).run())
}

/**
 * `text` formatted, or `None` when it has syntax errors.
 */
public func formatText(text: String): ?String {
    let edits = format(parse(text)) ?? return None
    applyEdits(text, edits)
}

/**
 * `text` with `edits`, in order and apart, made to it.
 */
public func applyEdits(text: String, edits: Array<TextEdit>): String {
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
 * What an open bracket, or the statements after an `=>`, indents. `line` is the line it opened
 * on, `contentIndent` where its elements start; `elementLine` and `elementIndent` are the line and
 * the indent of the element now going on. `isArrow` for the statements after a `case`'s `=>`.
 */
class Frame {
    Frame(
        let node: CjSyntaxNode,
        let isArrow: Bool,
        let line: Int64,
        let contentIndent: Int64,
        var elementLine: Int64,
        var elementIndent: Int64
    ) {}
}

class Formatter {
    let root: CjSyntaxNode
    let text: String
    let edits = ArrayList<TextEdit>()
    let frames = ArrayList<Frame>()
    var line = 0
    var lineIndent = 0
    /** How far the current line moved: what is kept as written moves as much. */
    var lineDelta = 0
    /** The end of the node kept as written the current token is in, `-1` outside one. */
    var opaqueEnd = -1
    var opaqueDelta = 0

    init(root: CjSyntaxNode) {
        this.root = root
        this.text = root.text()
        frames.add(Frame(root, false, -1, 0, -1, 0))
    }

    func run(): Array<TextEdit> {
        let tokens = ArrayList<CjSyntaxToken>()
        for (element in root.descendantsWithTokens()) {
            if (let Some(token) <- element.asToken()) {
                tokens.add(token)
            }
        }
        var i = 0
        var first = true
        while (true) {
            var j = i
            while (j < tokens.size && isSpace(tokens[j].kind)) {
                j++
            }
            let start = if (i < tokens.size) { tokens[i].textRange.start } else { text.size }
            if (j == tokens.size) {
                // the file ends in one line break, unless it is empty
                let ending = if (first) { "" } else { lineBreakIn(text) }
                replace(start, text.size, ending)
                break
            }
            gap(start, tokens[j], first)
            token(tokens[j])
            first = false
            i = j + 1
        }
        edits.toArray()
    }

    /**
     * The whitespace from `start` to `next`: where it breaks the line, the line breaks, kept to two,
     * and `next`'s indent.
     */
    func gap(start: Int64, next: CjSyntaxToken, first: Bool) {
        let end = next.textRange.start
        let space = text[start..end]
        let breaks = space.count("\n")
        if (breaks == 0 && !first) {
            return
        }
        line++
        let oldIndent = match (space.lastIndexOf("\n")) {
            case Some(at) => space.size - at - 1
            case None => space.size
        }
        let lineBreak = if (space.contains("\r\n")) { "\r\n" } else { "\n" }
        let (newIndent, kept) = if (opaqueEnd >= 0 && end < opaqueEnd) {
            (oldIndent + opaqueDelta, breaks)
        } else {
            (indentOf(next), if (first) { 0 } else { min(breaks, 2) })
        }
        lineIndent = newIndent
        lineDelta = newIndent - oldIndent
        replace(start, end, lineBreak * kept + " " * newIndent)
    }

    func token(t: CjSyntaxToken) {
        let start = t.textRange.start
        popArrows(t)
        match (t.kind) {
            case LineComment => comment(t)
            case BlockComment => comment(t)
            case _ => ()
        }
        if (opaqueEnd >= 0) {
            if (start < opaqueEnd) {
                return
            }
            opaqueEnd = -1
        }
        if (let Some(opaque) <- outermostOpaque(t)) {
            opaqueEnd = opaque.textRange.end
            opaqueDelta = boundedDelta(lineDelta, lineIndentsIn(opaque))
            return
        }
        if (t.kind.isTrivia()) {
            return
        }
        let top = frames[frames.size - 1]
        if (isElementStart(t, top)) {
            top.elementLine = line
            top.elementIndent = lineIndent
        }
        if (isCloser(t) && !top.isArrow && t.parent == top.node) {
            frames.remove(at: frames.size - 1)
        } else if (isOpener(t)) {
            frames.add(open(t.parent, false, fromElement: isBodyBrace(t.kind, t.parent.kind)))
        } else if (t.kind == FatArrow && t.parent.kind == MatchCase) {
            frames.add(open(t.parent, true, fromElement: true))
        }
    }

    func open(node: CjSyntaxNode, isArrow: Bool, fromElement!: Bool): Frame {
        let top = frames[frames.size - 1]
        let contentIndent = if (top.line == line) {
            top.contentIndent
        } else if (fromElement) {
            top.elementIndent + INDENT
        } else {
            lineIndent + INDENT
        }
        Frame(node, isArrow, line, contentIndent, line, lineIndent)
    }

    /**
     * The indent of the line `t` starts: a closer's is its bracket's line's, an element's that of
     * the elements of the bracket it is in, a line carrying an element on one level more, unless
     * the element started on the bracket's line.
     */
    func indentOf(t: CjSyntaxToken): Int64 {
        popArrows(t)
        let top = frames[frames.size - 1]
        if (isCloser(t) && !top.isArrow && t.parent == top.node) {
            return max(0, top.contentIndent - INDENT)
        }
        if (isElementStart(t, top)) {
            top.elementLine = line
            top.elementIndent = top.contentIndent
            return top.contentIndent
        }
        top.contentIndent + if (top.line == top.elementLine) { 0 } else { INDENT }
    }

    /**
     * Closes what follows the `=>`s of the `case`s that end before `t`.
     */
    func popArrows(t: CjSyntaxToken) {
        while (frames.size > 1) {
            let top = frames[frames.size - 1]
            if (!top.isArrow || t.textRange.start < top.node.textRange.end) {
                return
            }
            frames.remove(at: frames.size - 1)
        }
    }

    /**
     * A comment without trailing whitespace on its lines, the lines after its first moved as much
     * as that one, or as far as the least indented of them can go.
     */
    func comment(t: CjSyntaxToken) {
        let lines = t.text().split("\n")
        let crs = lines.map {line => line.endsWith("\r")}
        let trimmed = lines.map {line => line.trimAsciiEnd()}
        let after = trimmed[1..].filter {line => !line.isEmpty()}
        let delta = boundedDelta(lineDelta, after.map {line => indentOfLine(line)})
        let out = StringBuilder()
        for (i in 0..lines.size) {
            var current = trimmed[i]
            if (i > 0 && !current.isEmpty()) {
                let indent = indentOfLine(current)
                current = " " * (indent + delta) + current[indent..]
            }
            if (i > 0) {
                out.append("\n")
            }
            out.append(current)
            if (crs[i]) {
                out.append("\r")
            }
        }
        let range = t.textRange
        replace(range.start, range.end, out.toString())
    }

    func replace(start: Int64, end: Int64, replacement: String) {
        if (text[start..end] != replacement) {
            edits.add(TextEdit(TextRange(start, end), replacement))
        }
    }
}

func isSpace(kind: SyntaxKind): Bool {
    kind == Whitespace || kind == Newline
}

func isOpener(t: CjSyntaxToken): Bool {
    match (t.kind) {
        case LParen | LBracket | LBrace => true
        case Lt => isTypeList(t.parent.kind)
        case _ => false
    }
}

func isCloser(t: CjSyntaxToken): Bool {
    match (t.kind) {
        case RParen | RBracket | RBrace => true
        case Gt => isTypeList(t.parent.kind)
        case _ => false
    }
}

/**
 * A list in `<>`, whose `<` and `>` are brackets; elsewhere they compare.
 */
func isTypeList(kind: SyntaxKind): Bool {
    kind == TypeArgList || kind == TypeParamList
}

/**
 * A `{` whose content is indented from the line its declaration or statement starts on, not the
 * line it is on: `func f(a: A,\n    b: B) {` has its body one level in, not two.
 */
func isBodyBrace(kind: SyntaxKind, parent: SyntaxKind): Bool {
    if (kind != LBrace) {
        return false
    }
    match (parent) {
        case Block | DeclBody | EnumBody | PropBody | MatchBody | ForeignBlock => true
        case _ => false
    }
}

/**
 * What a macro reads as tokens, and a string, whose layout the formatter keeps.
 */
func isOpaque(kind: SyntaxKind): Bool {
    match (kind) {
        case QuoteExpr | MacroArgs | MacroAttr | StringLit => true
        case _ => false
    }
}

func outermostOpaque(t: CjSyntaxToken): ?CjSyntaxNode {
    var found: ?CjSyntaxNode = None
    for (ancestor in t.ancestors()) {
        if (isOpaque(ancestor.kind)) {
            found = ancestor
        }
    }
    found
}

/**
 * Whether `t` starts one of `frame`'s elements — a child of its node, a statement after a `case`'s
 * `=>` — with nothing before it in that element but annotations, modifiers, comments and the name
 * of a macro called on it.
 */
func isElementStart(t: CjSyntaxToken, frame: Frame): Bool {
    var element: CjSyntaxElement = SyntaxElement.Token(t)
    while (true) {
        let parent = element.parent ?? return false
        if (parent == frame.node) {
            return true
        }
        var before = element.prevSiblingOrToken()
        while (let Some(sibling) <- before) {
            if (!isPrefix(sibling, parent.kind)) {
                return false
            }
            before = sibling.prevSiblingOrToken()
        }
        element = SyntaxElement.Node(parent)
    }
    false
}

func isPrefix(element: CjSyntaxElement, parent: SyntaxKind): Bool {
    match (element.kind) {
        case Whitespace | Newline | LineComment | BlockComment | Annotation | Modifiers => true
        case At | AtBang | Dot | NameRef | MacroAttr => parent == MacroExpandDecl || parent == MacroExpandExpr
        case _ => false
    }
}

/**
 * `delta`, or as much of it as the least of `indents` can take: what moves as a whole keeps the
 * alignment of its lines, the least indented at the margin rather than the others shifted less.
 */
func boundedDelta(delta: Int64, indents: Array<Int64>): Int64 {
    indents.fold(delta) {bounded, indent => max(bounded, -indent)}
}

/**
 * The columns of whitespace `line` starts with.
 */
func indentOfLine(line: String): Int64 {
    line.size - line.trimAsciiStart().size
}

/**
 * The indents of the lines that start inside `node`, after its first token.
 */
func lineIndentsIn(node: CjSyntaxNode): Array<Int64> {
    let text = node.text()
    let start = node.textRange.start
    let indents = ArrayList<Int64>()
    var spaceFrom = -1
    for (element in node.descendantsWithTokens()) {
        let token = element.asToken() ?? continue
        if (isSpace(token.kind)) {
            if (spaceFrom < 0) {
                spaceFrom = token.textRange.start - start
            }
            continue
        }
        if (spaceFrom >= 0) {
            let space = text[spaceFrom..token.textRange.start - start]
            if (let Some(at) <- space.lastIndexOf("\n")) {
                indents.add(space.size - at - 1)
            }
            spaceFrom = -1
        }
    }
    indents.toArray()
}

func lineBreakIn(text: String): String {
    if (text.contains("\r\n")) {
        "\r\n"
    } else {
        "\n"
    }
}
