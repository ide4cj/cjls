package rope

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// 2000 lines of code-like text, a non-ASCII comment every tenth
let benchText: Rope = {
    =>
    let text = StringBuilder()
    for (i in 0..2000) {
        if (i > 0) {
            text.append("\n")
        }
        text.append(if (i % 10 == 0) { "    // значение ${i} ✓" } else { "    let value${i} = compute(${i}, \"text\")" })
    }
    Rope(text.toString())
}()

// 128 offsets spread over the text, each at a character boundary
let benchOffsets: Array<Int64> = {
    =>
    let offsets = ArrayList<Int64>()
    let text = benchText.toString()
    var at = 0
    while (offsets.size < 128) {
        var offset = (at * 7919) % text.size
        while ((text[offset] & 0xC0) == 0x80) {
            offset--
        }
        offsets.add(offset)
        at++
    }
    offsets.toArray()
}()

@Test
class PositionBench {
    @Bench
    func positionOfUtf16(): Int64 {
        var sum = 0
        for (offset in benchOffsets) {
            sum += benchText.positionOf(offset, Utf16).column
        }
        sum
    }

    @Bench
    func positionOfUtf8(): Int64 {
        var sum = 0
        for (offset in benchOffsets) {
            sum += benchText.positionOf(offset, Utf8).column
        }
        sum
    }
}
