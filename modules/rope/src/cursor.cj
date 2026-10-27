package rope

/**
 * The lines and columns of offsets asked for in the order of the text, each found from the one
 * before: a walk through the whole text costs its length once, where `Rope.positionOf` descends
 * the tree and scans a leaf for every offset. Columns count what `encoding` says, as
 * `Rope.positionOf`'s do.
 */
public class PositionCursor {
    private let chunks: Iterator<String>
    private let size: Int64
    private let encoding: Encoding
    private var chunk = ""
    // the offset `chunk` starts at
    private var chunkStart = 0
    private var offset = 0
    private var line = 0
    private var column = 0
    // the text before `offset`, in units of `encoding`
    private var units = 0

    public init(rope: Rope, encoding: Encoding) {
        chunks = rope.chunks()
        size = rope.size
        this.encoding = encoding
    }

    /**
     * The line and column of `offset`, as `Rope.positionOf` has them.
     *
     * @throws IllegalArgumentException - if `offset` is before the last one asked for, or falls
     * inside a character
     * @throws IndexOutOfBoundsException - if `offset` does not lie within the text
     */
    public func positionOf(offset: Int64): LineColumn {
        moveTo(offset)
        LineColumn(line, column)
    }

    /**
     * The text before `offset`, in units of the encoding: what `Rope.summaryBefore(offset)`
     * measures.
     *
     * @throws IllegalArgumentException - if `offset` is before the last one asked for, or falls
     * inside a character
     * @throws IndexOutOfBoundsException - if `offset` does not lie within the text
     */
    public func unitsBefore(offset: Int64): Int64 {
        moveTo(offset)
        units
    }

    private func moveTo(target: Int64): Unit {
        if (target < offset) {
            throw IllegalArgumentException(
                "offset ${target} is before ${offset}, the last one asked for"
            )
        }
        if (target > size) {
            throw IndexOutOfBoundsException("offset ${target} of a text of ${size} bytes")
        }
        while (offset < target) {
            if (offset - chunkStart == chunk.size) {
                chunkStart = offset
                chunk = chunks.next().getOrThrow()
            }
            let end = min(chunk.size, target - chunkStart)
            for (i in offset - chunkStart..end) {
                let b = chunk[i]
                let width = unitsOf(b)
                units += width
                if (b == b'\n') {
                    line++
                    column = 0
                } else {
                    column += width
                }
            }
            offset = chunkStart + end
        }
        // leaves are cut between characters, so the end of one is a boundary; a character cut
        // short counts at its first byte, and the cursor stays good for the offsets after it
        let i = offset - chunkStart
        if (i < chunk.size && isContinuation(chunk[i])) {
            throw IllegalArgumentException("offset ${offset} is inside a character")
        }
    }

    private func unitsOf(b: Byte): Int64 {
        match (encoding) {
            case Utf8 => 1
            case Utf16 where isContinuation(b) => 0
            case Utf16 => if (b >= 0xF0) { 2 } else { 1 }
            case Utf32 => if (isContinuation(b)) { 0 } else { 1 }
        }
    }
}
