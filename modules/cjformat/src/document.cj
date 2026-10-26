package cjformat

import std.collection.{ArrayList, count}
import ginkgo.TextRange

const UNBOUNDED = 2305843009213693951

/**
 * A document caches its flat width when built. Choosing a group never scans its descendants,
 * so a group decision does not repeatedly measure the same suffix. Indirection keeps recursive
 * layout variants finite-sized and lets groups share their child documents.
 */
class Doc {
    Doc(let layout: Layout, let width: Int64, let prefixWidth: Int64, let hasBreak: Bool) {}
}

enum Layout {
    | Text(String)
    | Concat(Array<Doc>)
    | Indented(Doc)
    | Group(Doc)
    | Line(String)
    | HardLine
    | EmptyLine
    | IfBreak(Doc, Doc)
    | LineSuffix(Doc)
    | Verbatim(String)
    | Reindented(String, Int64, Array<TextRange>)
    | Positioned(Doc, LayoutPosition)
}

/** Literal text, measured in Unicode scalar values. Unbreakable text may exceed the width. */
func textDoc(text: String): Doc {
    let first = text.indexOf("\n") ?? text.size
    let prefix = text[..first].runes() |> count
    Doc(
        Text(text),
        if (first < text.size) {
            UNBOUNDED
        } else {
            prefix
        },
        prefix,
        first < text.size
    )
}

/** Combines documents and caches the width before the first possible break. */
func concat(docs: Array<Doc>): Doc {
    var prefix = 0
    var hasBreak = false
    for (doc in docs) {
        if (!hasBreak) {
            prefix = min(UNBOUNDED, prefix + doc.prefixWidth)
        }
        hasBreak = hasBreak || doc.hasBreak
    }
    Doc(
        Concat(docs),
        docs.fold(0) { width, doc => min(UNBOUNDED, width + doc.width) },
        prefix,
        hasBreak
    )
}

/** Adds one indentation level when the document starts a new line. */
func indent(doc: Doc): Doc {
    Doc(Indented(doc), doc.width, doc.prefixWidth, doc.hasBreak)
}
/** Flattens the document when its cached width and following punctuation fit. */
func group(doc: Doc): Doc {
    Doc(Group(doc), doc.width, doc.prefixWidth, doc.hasBreak)
}
/** Prints a space in a flat group, otherwise a line break. */
func softline(): Doc {
    Doc(Line(" "), 1, 0, true)
}
/** Prints nothing in a flat group, otherwise a line break. */
func softbreak(): Doc {
    Doc(Line(""), 0, 0, true)
}
/** Forces a line break even inside a flat group. */
func hardline(): Doc {
    Doc(HardLine, UNBOUNDED, 0, true)
}
/** Separates content by one empty line. */
func blankline(): Doc {
    Doc(EmptyLine, UNBOUNDED, 0, true)
}
/** Chooses a document according to the enclosing group's layout. */
func ifBreak(broken: Doc, flat: Doc): Doc {
    Doc(IfBreak(broken, flat), flat.width, broken.prefixWidth, broken.hasBreak)
}
/** Defers literal text until the current line ends. */
func lineSuffix(doc: Doc): Doc {
    Doc(LineSuffix(doc), UNBOUNDED, doc.prefixWidth, true)
}
/** Preserves literal contents, including embedded line breaks. */
func verbatim(text: String): Doc {
    let measured = textDoc(text)
    Doc(Verbatim(text), measured.width, measured.prefixWidth, measured.hasBreak)
}

/** Moves the supplied leading-whitespace ranges together, without crossing the margin. */
func reindented(text: String, oldIndent: Int64, ranges: Array<TextRange>): Doc {
    let measured = textDoc(text)
    Doc(
        Reindented(text, oldIndent, ranges),
        measured.width,
        measured.prefixWidth,
        measured.hasBreak
    )
}

/** The layout context of a range target, captured while printing its complete file. */
class LayoutPosition {
    var reserved = 0
    var indentation = 0
    var column = 0
    var lineIndent = 0
}

/** Records the enclosing print context for formatting a selected syntax node. */
func positioned(doc: Doc, position: LayoutPosition): Doc {
    Doc(Positioned(doc, position), doc.width, doc.prefixWidth, doc.hasBreak)
}

struct PrintFrame {
    PrintFrame(let doc: Doc, let indentation: Int64, let isFlat: Bool, let reserved!: Int64 = 0) {}
}

/** Iterative printing also bounds the call stack for deeply nested documents. */
class Printer {
    private let out = StringBuilder()
    private let stack = ArrayList<PrintFrame>()
    private let suffixes = ArrayList<PrintFrame>()
    private var column = 0
    private var lineIndent = 0
    private var pendingSpaces = 0
    private var lineBreaks = 0
    private var isStart = true

    Printer(private let width: Int64, private let newline: String) {}

    func print(
        doc: Doc,
        indentation!: Int64 = 0,
        column!: Int64 = 0,
        lineIndent!: Int64 = 0,
        reserved!: Int64 = 0
    ): String {
        this.column = column
        this.lineIndent = lineIndent
        isStart = column == 0
        stack.add(PrintFrame(doc, indentation, false, reserved: reserved))
        while (!stack.isEmpty()) {
            let frame = stack[stack.size - 1]
            stack.remove(at: stack.size - 1)
            render(frame)
        }
        flushSuffixes()
        out.toString()
    }

    private func render(frame: PrintFrame): Unit {
        let level = frame.indentation
        let flat = frame.isFlat
        match (frame.doc.layout) {
            case Positioned(doc, position) =>
                position.reserved = frame.reserved
                position.indentation = level
                position.column =
                    if (isStart) {
                        0
                    } else {
                        column + pendingSpaces
                    }
                position.lineIndent = lineIndent
                stack.add(PrintFrame(doc, level, flat, reserved: frame.reserved))
            case Text(value) => writeRaw(value, level)
            case Verbatim(value) => writeRaw(value, level)
            case Reindented(value, oldIndent, ranges) =>
                let actualIndent =
                    if (isStart) {
                        level
                    } else {
                        lineIndent
                    }
                let delta = ranges.fold(actualIndent - oldIndent) { d, range => max(d, -range.len) }
                let edits = ranges.map { range => TextEdit(range, " " * (range.len + delta)) }
                writeRaw(applyEdits(value, edits), level)
            case Concat(docs) =>
                var reserved = frame.reserved
                for (i in 0..docs.size) {
                    let doc = docs[docs.size - i - 1]
                    stack.add(PrintFrame(doc, level, flat, reserved: reserved))
                    reserved =
                        if (doc.hasBreak) {
                            doc.prefixWidth
                        } else {
                            min(UNBOUNDED, reserved + doc.prefixWidth)
                        }
                }
            case Indented(doc) =>
                stack.add(PrintFrame(doc, level + INDENT, flat, reserved: frame.reserved))
            case Group(doc) =>
                let used =
                    if (isStart) {
                        level
                    } else {
                        column + pendingSpaces
                    }
                stack
                    .add(
                        PrintFrame(
                            doc,
                            level,
                            flat || doc.width <= width - used - frame.reserved,
                            reserved: frame.reserved
                        )
                    )
            case Line(value) =>
                if (flat) {
                    write(value, level)
                } else {
                    endLine(1)
                }
            case HardLine => endLine(1)
            case EmptyLine => endLine(2)
            case IfBreak(broken, oneLine) =>
                stack
                    .add(
                        PrintFrame(
                            if (flat) {
                                oneLine
                            } else {
                                broken
                            },
                            level,
                            flat,
                            reserved: frame.reserved
                        )
                    )
            case LineSuffix(doc) => suffixes.add(PrintFrame(doc, level, true))
        }
    }

    private func flushSuffixes(): Unit {
        let pending = suffixes.toArray()
        suffixes.clear()
        for (frame in pending) {
            // Suffix documents are text/comments, never groups with deferred work.
            match (frame.doc.layout) {
                case Text(value) => write(value, frame.indentation)
                case Verbatim(value) => writeRaw(value, frame.indentation)
                case _ => throw IllegalStateException("a line suffix must be literal text")
            }
        }
    }

    private func endLine(count: Int64): Unit {
        flushSuffixes()
        pendingSpaces = 0
        while (lineBreaks < count) {
            out.append(newline)
            lineBreaks++
        }
        column = 0
        isStart = true
    }

    private func write(value: String, level: Int64): Unit {
        if (value.isEmpty()) {
            return
        }
        if (value == " ") {
            if (!isStart) {
                pendingSpaces++
            }
            return
        }
        if (isStart) {
            out.append(" " * level)
            column = level
            lineIndent = level
        } else if (pendingSpaces > 0) {
            out.append(" " * pendingSpaces)
            column += pendingSpaces
        }
        pendingSpaces = 0
        out.append(value)
        column += (value.runes() |> count)
        isStart = false
        lineBreaks = 0
    }

    private func writeRaw(value: String, level: Int64): Unit {
        write(value, level)
        if (let Some(at) <- value.lastIndexOf("\n")) {
            let last = value[at + 1..]
            lineIndent = last.size - last.trimAsciiStart().size
            column = last.runes() |> count
            isStart = value.endsWith("\n")
            lineBreaks =
                if (isStart) {
                    1
                } else {
                    0
                }
        }
    }
}
