package source_change

import std.deriving.Derive
import std.sort.sort
import ginkgo.TextRange

/**
 * A replacement in UTF-8 byte offsets into the original text, with an exclusive end.
 */
@Derive[Equatable, ToString]
public struct TextEdit {
    public TextEdit(public let range: TextRange, public let text: String) {}
}

/**
 * Applies edits in original-text coordinates without mutating the input array.
 * Edits may arrive in any order. Insertions at the same position retain input order;
 * insertions at a replacement's start precede it, and those at its end follow it.
 *
 * @throws IllegalArgumentException - for overlapping replacements, insertions inside a
 * replacement, out-of-bounds ranges or endpoints inside a UTF-8 character
 */
public func applyEdits(text: String, edits: Array<TextEdit>): String {
    let ordered = validatedEdits(text, edits)
    let out = StringBuilder()
    var at = 0
    for (edit in ordered) {
        let range = edit.range
        out.append(text[at..range.start])
        out.append(edit.text)
        at = range.end
    }
    out.append(text[at..])
    out.toString()
}

/**
 * Returns a sorted copy for text application or translation to an editor protocol.
 * Uses the same coordinate and insertion ordering contract as applyEdits.
 *
 * @throws IllegalArgumentException - for invalid or overlapping edits
 */
public func validatedEdits(text: String, edits: Array<TextEdit>): Array<TextEdit> {
    let ordered = edits.clone()
    sort(
        ordered,
        by: {
            a, b =>
            let start = a.range.start.compare(b.range.start)
            if (start == Ordering.EQ) { a.range.end.compare(b.range.end) } else { start }
        },
        stable: true
    )
    var at = 0
    for (edit in ordered) {
        let range = edit.range
        if (
            range.end > text.size || range.start < at || !isBoundary(text, range.start) ||
                !isBoundary(text, range.end)
        ) {
            throw IllegalArgumentException("invalid or overlapping text edit: ${range}")
        }
        at = range.end
    }
    ordered
}

private func isBoundary(text: String, offset: Int64): Bool {
    offset == text.size || (text[offset] & 0xC0) != 0x80
}
