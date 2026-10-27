package loupe

import std.collection.*
import std.sort.sort
import ginkgo.TextRange
import cjformat.formatText
import loupe.db.AnalysisDatabase
import loupe.hir.*
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * The text of an expansion as a reader is shown it: formatted by cjformat, which changes whitespace only (D150), its
 * trailing whitespace left out; as the macro wrote it if it does not format. Its bytes that are not whitespace are
 * those of the text the macro wrote (`expandedMacro`), in order: that is how an offset goes from one to the other.
 */
public class ShownExpansion {
    private ShownExpansion(
        public let text: String,
        // the offsets of the bytes that are no whitespace, in the text written and in the text shown
        private let writtenMarks: Array<Int64>,
        private let shownMarks: Array<Int64>
    ) {}

    public static func of(written: String): ShownExpansion {
        let writtenMarks = marksOf(written)
        let formatted = (formatText(written) ?? written).trimAsciiEnd()
        let formattedMarks = marksOf(formatted)
        if (sameMarks(written, writtenMarks, formatted, formattedMarks)) {
            return ShownExpansion(formatted, writtenMarks, formattedMarks)
        }
        let trimmed = written.trimAsciiEnd()
        ShownExpansion(trimmed, writtenMarks, marksOf(trimmed))
    }

    /**
     * The offset of the written text that `offset` of the shown text is at.
     */
    public func toWritten(offset: Int64): Int64 {
        across(offset, shownMarks, writtenMarks)
    }

    /**
     * The offset of the shown text that `offset` of the written text is at.
     */
    public func fromWritten(offset: Int64): Int64 {
        across(offset, writtenMarks, shownMarks)
    }

    public func fromWritten(range: TextRange): TextRange {
        TextRange(fromWritten(range.start), fromWritten(range.end))
    }
}

func isSpace(byte: Byte): Bool {
    byte == b' ' || byte == b'\t' || byte == b'\n' || byte == b'\r'
}

func marksOf(text: String): Array<Int64> {
    let marks = ArrayList<Int64>()
    for (i in 0..text.size where !isSpace(text[i])) {
        marks.add(i)
    }
    marks.toArray()
}

func sameMarks(a: String, aMarks: Array<Int64>, b: String, bMarks: Array<Int64>): Bool {
    if (aMarks.size != bMarks.size) {
        return false
    }
    for (i in 0..aMarks.size where a[aMarks[i]] != b[bMarks[i]]) {
        return false
    }
    true
}

/**
 * `offset` of a text whose marks are `from`, in the text whose marks are `to`: a mark goes to its mark, an offset in
 * whitespace just past the mark before it, so a range's end stays at the end of what it covers.
 */
func across(offset: Int64, from: Array<Int64>, to: Array<Int64>): Int64 {
    // the first mark at or after `offset`
    var low = 0
    var high = from.size
    while (low < high) {
        let middle = (low + high) / 2
        if (from[middle] < offset) { low = middle + 1 } else { high = middle }
    }
    if (low < from.size && from[low] == offset) {
        to[low]
    } else if (low == 0) {
        0
    } else {
        to[low - 1] + 1
    }
}

/**
 * Where a piece of an expanded file (`expandFile`) comes from.
 */
public enum ExpandedOrigin {
    /**
     * The analysis wrote it: the header, a line naming a call.
     */
    | Written
    /**
     * Copied from the source file, from this offset of it on.
     */
    | Copied(Int64)
    /**
     * The expansion of this call, as shown.
     */
    | Shown(MacroCallId, ShownExpansion)
}

public struct ExpandedSegment {
    public ExpandedSegment(public let range: TextRange, public let origin: ExpandedOrigin) {}
}

/**
 * What an offset of an expanded file is at: an offset of its source file, or one of the text of an expansion
 * (`expandedMacro`).
 */
public enum ExpandedPlace {
    | InSource(Int64)
    | InExpansion(MacroCallId, Int64)
}

/**
 * A source file with its macro calls expanded, as cjc's `--debug-macro` writes a `.cj.macrocall`; and where each of
 * its pieces comes from.
 */
public class ExpandedFile {
    ExpandedFile(public let text: String, public let segments: Array<ExpandedSegment>) {}

    /**
     * What `offset` is at: the piece it is in, or the one it ends; `None` in what the analysis wrote.
     */
    public func placeOf(offset: Int64): ?ExpandedPlace {
        for (
            segment in segments where segment.range.start <= offset && offset <= segment.range.end
        ) {
            // at the end of a piece, the next one's start if it is one
            if (
                offset == segment.range.end &&
                    segments
                        .iterator()
                        .any {
                            one =>
                            one.range.start == offset && !one.range.isEmpty() && !isWritten(one)
                        }
            ) {
                continue
            }
            let within = offset - segment.range.start
            match (segment.origin) {
                case Written => continue
                case Copied(start) => return ExpandedPlace.InSource(start + within)
                case Shown(call, shown) =>
                    return ExpandedPlace.InExpansion(call, shown.toWritten(within))
            }
        }
        None
    }

    /**
     * Where `range` of the source file is here, if it was copied whole into one piece.
     */
    public func fromSource(range: TextRange): ?TextRange {
        for (segment in segments) {
            if (
                let Copied(start) <- segment.origin && start <= range.start &&
                    range.end <= start + segment.range.len
            ) {
                return range.shift(segment.range.start - start)
            }
        }
        None
    }

    /**
     * Where `range` of the text of the expansion of `call` (`expandedMacro`) is here, if the file shows it.
     */
    public func fromExpansion(call: MacroCallId, range: TextRange): ?TextRange {
        for (segment in segments) {
            if (let Shown(one, shown) <- segment.origin && one == call) {
                return shown.fromWritten(range).shift(segment.range.start)
            }
        }
        None
    }

    /**
     * Where the expansion of `call` is here, if the file shows it.
     */
    public func expansionOf(call: MacroCallId): ?TextRange {
        for (segment in segments) {
            if (let Shown(one, _) <- segment.origin && one == call) {
                return segment.range
            }
        }
        None
    }

    private func isWritten(segment: ExpandedSegment): Bool {
        match (segment.origin) {
            case Written => true
            case _ => false
        }
    }
}

/**
 * The file `fileId` with what its macro calls expand to (`expandedMacro`), each shown (`ShownExpansion`) after a line
 * naming its call, `header` and a line break first: an item whose call the macro server ran the analysis reads is
 * replaced by its expansion, from that call on, as cjc replaces it; one of std's macros is followed by what the analysis
 * adds for it. `None` for a file the database does not know, or one with no expansion.
 */
public func expandFile(db: AnalysisDatabase, fileId: FileId, header: String): ?ExpandedFile {
    let file = db.sourceFile(fileId) ?? return None
    let source = file.text(db).toString()
    let ids = itemIdMap(db, file)
    let root = parse(db, file).syntaxNode()
    // each top-level item with an expansion, its range, and its calls expanded
    let tops = ArrayList<(TextRange, ArrayList<(MacroCallId, ExpandedMacro)>)>()
    for (call in expandedCalls(db, file)) {
        let expanded = expandedMacro(db, call) ?? continue
        let item = call.item(db)
        let top =
            (
                itemTree(db, file).items |>
                    filter {
                        one: Item =>
                        one.id == item || one.members.iterator().any { member => member.id == item }
                    } |>
                    first
            ) ??
                continue
        let range = ids.node(top.id, root)?.textRange ?? continue
        match (
            tops |>
                filter {
                    one: (TextRange, ArrayList<(MacroCallId, ExpandedMacro)>) =>
                    one[0] == range
                } |>
                first
        ) {
            case Some((_, calls)) => calls.add((call, expanded))
            case None =>
                tops.add((range, ArrayList<(MacroCallId, ExpandedMacro)>([(call, expanded)])))
        }
    }
    if (tops.isEmpty()) {
        return None
    }
    let sorted = tops.toArray()
    sort(sorted, key: { one: (TextRange, ArrayList<(MacroCallId, ExpandedMacro)>) => one[0].start })
    let builder = ExpandedFileBuilder()
    builder.write(header + "\n")
    var at = 0
    for ((range, calls) in sorted) {
        let replacing =
            calls |>
                filter {
                    one: (MacroCallId, ExpandedMacro) =>
                    one[1].kind == ExpansionKind.ServerExpansion &&
                        macroExpansion(db, one[0]).replaces
                } |>
                first
        if (let Some((call, expanded)) <- replacing) {
            builder.copy(source, at, expanded.range.start)
            builder.write("// ${callText(source, expanded)} expanded by cjls\n")
            builder.show(call, ShownExpansion.of(expanded.text))
        } else {
            builder.copy(source, at, range.end)
        }
        at = range.end
        let added = calls.toArray().filter { one => one[1].kind == ExpansionKind.OwnExpansion }
        sort(added, key: { one: (MacroCallId, ExpandedMacro) => one[1].range.start })
        for ((call, expanded) in added) {
            builder
                .write(
                    "\n\n// ${callText(source, expanded)} expanded by cjls: its own, signatures only, no bodies\n"
                )
            builder.show(call, ShownExpansion.of(expanded.text))
        }
    }
    builder.copy(source, at, source.size)
    builder.build()
}

/**
 * The head of the call `expanded` is of, as `source` writes it, on one line.
 */
func callText(source: String, expanded: ExpandedMacro): String {
    source[expanded.range.start..expanded.range.end].replace("\r", "").replace("\n", " ")
}

class ExpandedFileBuilder {
    private let text = StringBuilder()
    private let segments = ArrayList<ExpandedSegment>()
    private var size = 0

    func write(written: String): Unit {
        add(written, ExpandedOrigin.Written)
    }

    func copy(source: String, start: Int64, end: Int64): Unit {
        if (end > start) {
            add(source[start..end], ExpandedOrigin.Copied(start))
        }
    }

    func show(call: MacroCallId, shown: ShownExpansion): Unit {
        add(shown.text, ExpandedOrigin.Shown(call, shown))
    }

    private func add(piece: String, origin: ExpandedOrigin): Unit {
        text.append(piece)
        segments.add(ExpandedSegment(TextRange(size, size + piece.size), origin))
        size += piece.size
    }

    func build(): ExpandedFile {
        ExpandedFile(text.toString(), segments.toArray())
    }
}
