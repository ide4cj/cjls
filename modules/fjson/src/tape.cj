package fjson

/*
 * An experiment (branch `perf/tape-experiment`, not for merging): a structural index over the
 * bytes of one JSON text - a tape, as jsmn and simdjson's second stage build one, but scalar -
 * against `FjReader`, the pull reader, on the same messages.
 *
 * `index` makes one pass over the bytes and writes a token per value and per key: its kind, where
 * its bytes start and end, and for a container the index of the token after it, so that skipping
 * a value and looking a key up in an object cost no second pass over the bytes. Strings are
 * scanned to their end, their escapes and UTF-8 checked, but not unescaped; numbers are checked
 * against JSON's grammar but not parsed. The syntax (commas, colons, brackets) is checked as
 * `FjReader` checks it. The arrays are kept from message to message and grow on demand, so a
 * message of a shape seen before allocates nothing for its index.
 *
 * The cursor reads the tape the way a generated decoder reads `FjReader`: `beginObject` /
 * `nextKey` / `keyIs` / `readString` ... A string with escapes is unescaped by an `FjReader` over
 * the same bytes, rewound to it: the one unescape, not a second.
 */

const TAPE_INITIAL = 64

// a token's kind; a key is a token of its own, its value the token after it
const TK_OBJECT: UInt8 = 0
const TK_ARRAY: UInt8 = 1
const TK_KEY_PLAIN: UInt8 = 2
const TK_KEY_ESCAPED: UInt8 = 3
const TK_STRING_PLAIN: UInt8 = 4
const TK_STRING_ESCAPED: UInt8 = 5
const TK_NUMBER: UInt8 = 6
const TK_TRUE: UInt8 = 7
const TK_FALSE: UInt8 = 8
const TK_NULL: UInt8 = 9

// what the grammar allows next while indexing
const EX_VALUE = 0
const EX_VALUE_OR_CLOSE = 1
const EX_KEY = 2
const EX_KEY_OR_CLOSE = 3
const EX_COLON = 4
const EX_AFTER_VALUE = 5
const EX_END = 6

public class FjTape {
    private var bytes = Array<Byte>()
    private var kinds = Array<UInt8>(TAPE_INITIAL, repeat: 0)
    // a string's or key's: past the opening quote and at the closing one; a number's or literal's: its bytes
    private var starts = Array<Int32>(TAPE_INITIAL, repeat: 0)
    // a scalar's byte end; a container's: the index of the token after it
    private var ends = Array<Int32>(TAPE_INITIAL, repeat: 0)
    private var count = 0
    // the open containers' token indices, their `ends` patched on close
    private let stack = Array<Int32>(MAX_DEPTH, repeat: 0)
    // the cursor: the token the next read takes, and the key `nextKey` last stepped over
    private var at = 0
    private var lastKey = 0
    // strings with escapes are unescaped by the reader's code, over the same bytes
    private let reader = FjReader(Array<Byte>())

    public FjTape() {}

    /** How many tokens the last `index` wrote. */
    public prop size: Int64 {
        get() {
            count
        }
    }

    private func fail(message: String, pos: Int64): FjException {
        FjException("${message} at byte ${pos}")
    }

    private func grow(): Unit {
        let n = kinds.size * 2
        let k = Array<UInt8>(n, repeat: 0)
        kinds.copyTo(k, 0, 0, count)
        kinds = k
        let s = Array<Int32>(n, repeat: 0)
        starts.copyTo(s, 0, 0, count)
        starts = s
        let e = Array<Int32>(n, repeat: 0)
        ends.copyTo(e, 0, 0, count)
        ends = e
    }

    private func push(kind: UInt8, start: Int64, end: Int64): Int64 {
        if (count == kinds.size) {
            grow()
        }
        kinds[count] = kind
        starts[count] = Int32(start)
        ends[count] = Int32(end)
        count++
        count - 1
    }

    /** The index of `next`, one pass; the cursor at its first token. */
    public func index(next: Array<Byte>): Unit {
        bytes = next
        count = 0
        at = 0
        lastKey = 0
        reader.reset(next)
        let n = bytes.size
        var pos = 0
        var depth = 0
        var expect = EX_VALUE
        while (true) {
            // whitespace
            while (pos < n) {
                let b = bytes[pos]
                if (b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09) {
                    pos++
                } else {
                    break
                }
            }
            if (pos >= n) {
                if (expect == EX_END) {
                    return
                }
                throw fail("unexpected end of input", pos)
            }
            let b = bytes[pos]
            if (expect == EX_END) {
                throw fail("trailing characters", pos)
            } else if (expect == EX_COLON) {
                    if (b != 0x3A) {
                        throw fail("expected `:`", pos)
                    }
                    pos++
                    expect = EX_VALUE
            } else if (expect == EX_KEY || expect == EX_KEY_OR_CLOSE) {
                    if (b == 0x7D && expect == EX_KEY_OR_CLOSE) {
                        depth = close(TK_OBJECT, depth, pos)
                        pos++
                        expect = if (depth == 0) { EX_END } else { EX_AFTER_VALUE }
                    } else if (b == QUOTE) {
                        pos = string(pos, true)
                        expect = EX_COLON
                    } else {
                        throw fail("expected a key", pos)
                    }
            } else if (expect == EX_AFTER_VALUE) {
                    let open = kinds[Int64(stack[depth - 1])]
                    if (b == 0x2C) {
                        pos++
                        expect = if (open == TK_OBJECT) { EX_KEY } else { EX_VALUE }
                    } else if (b == 0x7D && open == TK_OBJECT) {
                        depth = close(TK_OBJECT, depth, pos)
                        pos++
                        expect = if (depth == 0) { EX_END } else { EX_AFTER_VALUE }
                    } else if (b == 0x5D && open == TK_ARRAY) {
                        depth = close(TK_ARRAY, depth, pos)
                        pos++
                        expect = if (depth == 0) { EX_END } else { EX_AFTER_VALUE }
                    } else {
                        throw fail(if (open == TK_OBJECT) { "expected `,` or `}`" } else { "expected `,` or `]`" }, pos)
                    }
            } else {
                    // a value, or the `]` of an array just opened
                    if (b == 0x5D && expect == EX_VALUE_OR_CLOSE) {
                        depth = close(TK_ARRAY, depth, pos)
                        pos++
                        expect = if (depth == 0) { EX_END } else { EX_AFTER_VALUE }
                        continue
                    }
                    match (b) {
                        case 0x7B =>
                            if (depth >= MAX_DEPTH) {
                                throw fail("nested deeper than ${MAX_DEPTH}", pos)
                            }
                            stack[depth] = Int32(push(TK_OBJECT, pos, 0))
                            depth++
                            pos++
                            expect = EX_KEY_OR_CLOSE
                            continue
                        case 0x5B =>
                            if (depth >= MAX_DEPTH) {
                                throw fail("nested deeper than ${MAX_DEPTH}", pos)
                            }
                            stack[depth] = Int32(push(TK_ARRAY, pos, 0))
                            depth++
                            pos++
                            expect = EX_VALUE_OR_CLOSE
                            continue
                        case 0x22 => pos = string(pos, false)
                        case 0x74 => pos = literal(pos, "true", TK_TRUE)
                        case 0x66 => pos = literal(pos, "false", TK_FALSE)
                        case 0x6E => pos = literal(pos, "null", TK_NULL)
                        case _ => pos = number(pos)
                    }
                    expect = if (depth == 0) { EX_END } else { EX_AFTER_VALUE }
            }
        }
    }

    private func close(kind: UInt8, depth: Int64, pos: Int64): Int64 {
        let open = Int64(stack[depth - 1])
        if (kinds[open] != kind) {
            throw fail(if (kind == TK_OBJECT) { "expected `]`" } else { "expected `}`" }, pos)
        }
        ends[open] = Int32(count)
        depth - 1
    }

    /** The string whose opening quote is at `pos`, its token pushed; past its closing quote. */
    private func string(pos: Int64, isKey: Bool): Int64 {
        let start = pos + 1
        var i = start
        var escaped = false
        while (true) {
            i = scanAscii(bytes, i)
            if (i >= bytes.size) {
                throw fail("unterminated string", i)
            }
            let b = bytes[i]
            if (b == QUOTE) {
                break
            }
            if (b == BACKSLASH) {
                i = escape(i)
                escaped = true
            } else if (b >= 0x80) {
                let length = utf8Length(bytes, i)
                if (length == 0) {
                    throw fail("invalid UTF-8", i)
                }
                i += length
            } else {
                throw fail("control character in a string", i)
            }
        }
        let kind = if (isKey) {
            if (escaped) { TK_KEY_ESCAPED } else { TK_KEY_PLAIN }
        } else {
            if (escaped) { TK_STRING_ESCAPED } else { TK_STRING_PLAIN }
        }
        push(kind, start, i)
        i + 1
    }

    /** Past the escape at `i`, checked as `FjReader` checks it. */
    private func escape(i: Int64): Int64 {
        if (i + 1 >= bytes.size) {
            throw fail("unterminated string", i)
        }
        match (bytes[i + 1]) {
            case 0x22 | 0x5C | 0x2F | 0x62 | 0x66 | 0x6E | 0x72 | 0x74 => i + 2
            case 0x75 =>
                if (i + 6 > bytes.size) {
                    throw fail("unterminated escape", i)
                }
                for (k in 2..6) {
                    let c = bytes[i + k]
                    let hex = (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66) || (c >= 0x41 && c <= 0x46)
                    if (!hex) {
                        throw fail("invalid hex digit", i + k)
                    }
                }
                i + 6
            case _ => throw fail("invalid escape", i)
        }
    }

    private func literal(pos: Int64, text: String, kind: UInt8): Int64 {
        if (pos + text.size > bytes.size) {
            throw fail("expected `${text}`", pos)
        }
        for (k in 0..text.size) {
            if (bytes[pos + k] != text[k]) {
                throw fail("expected `${text}`", pos)
            }
        }
        push(kind, pos, pos + text.size)
        pos + text.size
    }

    private func digits(from: Int64): Int64 {
        var i = from
        while (i < bytes.size && bytes[i] >= 0x30 && bytes[i] <= 0x39) {
            i++
        }
        i
    }

    /** The number at `pos`, JSON's grammar checked, its token pushed; past it. */
    private func number(pos: Int64): Int64 {
        var i = pos
        if (i < bytes.size && bytes[i] == 0x2D) {
            i++
        }
        let digitsStart = i
        i = digits(i)
        if (i == digitsStart || (i - digitsStart > 1 && bytes[digitsStart] == 0x30)) {
            throw fail("expected a value", pos)
        }
        if (i < bytes.size && bytes[i] == 0x2E) {
            let fraction = digits(i + 1)
            if (fraction == i + 1) {
                throw fail("expected a digit", i + 1)
            }
            i = fraction
        }
        if (i < bytes.size && (bytes[i] == 0x65 || bytes[i] == 0x45)) {
            i++
            if (i < bytes.size && (bytes[i] == 0x2B || bytes[i] == 0x2D)) {
                i++
            }
            let exponent = digits(i)
            if (exponent == i) {
                throw fail("expected a digit", i)
            }
            i = exponent
        }
        push(TK_NUMBER, pos, i)
        i
    }

    // ---- the cursor ----

    /** The token the next read takes: what a decoder keeps to come back to `params` once `method` is known. */
    public prop position: Int64 {
        get() {
            at
        }
    }

    public func seek(token: Int64): Unit {
        at = token
    }

    private func readFail(message: String): FjException {
        let pos = if (at < count) { Int64(starts[at]) } else { bytes.size }
        fail(message, pos)
    }

    /** The index of the token after the value at `token`. */
    private func after(token: Int64): Int64 {
        let kind = kinds[token]
        if (kind == TK_OBJECT || kind == TK_ARRAY) {
            Int64(ends[token])
        } else {
            token + 1
        }
    }

    /** Into the object at the cursor; the index of the token after it, for `nextKey`. */
    public func beginObject(): Int64 {
        if (at >= count || kinds[at] != TK_OBJECT) {
            throw readFail("expected `{`")
        }
        let end = Int64(ends[at])
        at++
        end
    }

    /** Whether a member is left before `end`; the cursor then at its value, the key `keyIs`'s. */
    public func nextKey(end: Int64): Bool {
        if (at >= end) {
            return false
        }
        lastKey = at
        at++
        true
    }

    public func keyIs(name: String): Bool {
        let start = Int64(starts[lastKey])
        let length = Int64(ends[lastKey]) - start
        if (kinds[lastKey] == TK_KEY_ESCAPED) {
            return key() == name
        }
        if (name.size != length) {
            return false
        }
        var i = 0
        while (i < length && bytes[start + i] == name[i]) {
            i++
        }
        i == length
    }

    public func key(): String {
        stringAt(lastKey)
    }

    /**
     * Whether the object at the cursor has a member `name`: what picks an untagged variant without
     * reading the value twice. The cursor does not move.
     */
    public func hasKey(name: String): Bool {
        if (at >= count || kinds[at] != TK_OBJECT) {
            throw readFail("expected `{`")
        }
        let end = Int64(ends[at])
        var key = at + 1
        while (key < end) {
            let start = Int64(starts[key])
            let length = Int64(ends[key]) - start
            if (kinds[key] == TK_KEY_PLAIN && length == name.size) {
                var i = 0
                while (i < length && bytes[start + i] == name[i]) {
                    i++
                }
                if (i == length) {
                    return true
                }
            } else if (kinds[key] == TK_KEY_ESCAPED && stringAt(key) == name) {
                return true
            }
            key = after(key + 1)
        }
        false
    }

    /** Into the array at the cursor; the index of the token after it, for `nextItem`. */
    public func beginArray(): Int64 {
        if (at >= count || kinds[at] != TK_ARRAY) {
            throw readFail("expected `[`")
        }
        let end = Int64(ends[at])
        at++
        end
    }

    public func nextItem(end: Int64): Bool {
        at < end
    }

    private func stringAt(token: Int64): String {
        let start = Int64(starts[token])
        let end = Int64(ends[token])
        if (kinds[token] == TK_STRING_PLAIN || kinds[token] == TK_KEY_PLAIN) {
            return unsafe { String.fromUtf8Unchecked(bytes[start..end]) }
        }
        // the reader's unescape, over the same bytes, from the opening quote
        reader.rewind(start - 1)
        reader.readString()
    }

    public func readString(): String {
        if (at >= count || (kinds[at] != TK_STRING_PLAIN && kinds[at] != TK_STRING_ESCAPED)) {
            throw readFail("expected a string")
        }
        let s = stringAt(at)
        at++
        s
    }

    /** An integer, `-` and digits: the grammar was checked by `index`, the range is checked here. */
    public func readInt64(): Int64 {
        if (at >= count || kinds[at] != TK_NUMBER) {
            throw readFail("expected an integer")
        }
        let start = Int64(starts[at])
        let end = Int64(ends[at])
        var i = start
        var negative = false
        if (bytes[i] == 0x2D) {
            negative = true
            i++
        }
        // accumulated negative, so that Int64.Min fits
        var v: Int64 = 0
        while (i < end) {
            let b = bytes[i]
            if (b < 0x30 || b > 0x39) {
                throw readFail("expected an integer, not a decimal")
            }
            let d = Int64(b - 0x30)
            if (v < (Int64.Min + d) / 10) {
                throw readFail("integer out of range")
            }
            v = v * 10 - d
            i++
        }
        at++
        if (negative) {
            v
        } else if (v == Int64.Min) {
            throw readFail("integer out of range")
        } else {
            -v
        }
    }

    public func readInt32(): Int32 {
        let v = readInt64()
        if (v < Int64(Int32.Min) || v > Int64(Int32.Max)) {
            throw readFail("integer out of range")
        }
        Int32(v)
    }

    public func readUInt32(): UInt32 {
        let v = readInt64()
        if (v < 0 || v > Int64(UInt32.Max)) {
            throw readFail("integer out of range")
        }
        UInt32(v)
    }

    public func readBool(): Bool {
        if (at < count && kinds[at] == TK_TRUE) {
            at++
            return true
        }
        if (at < count && kinds[at] == TK_FALSE) {
            at++
            return false
        }
        throw readFail("expected a boolean")
    }

    public func isNull(): Bool {
        at < count && kinds[at] == TK_NULL
    }

    public func readNull(): Unit {
        if (!isNull()) {
            throw readFail("expected `null`")
        }
        at++
    }

    /** Past the value at the cursor, whatever its size: one step on the tape. */
    public func skip(): Unit {
        if (at >= count) {
            throw readFail("expected a value")
        }
        at = after(at)
    }

    /** The bytes of the value at the cursor, a slice of the input; the cursor past it. */
    public func rawValue(): Array<Byte> {
        if (at >= count) {
            throw readFail("expected a value")
        }
        let kind = kinds[at]
        let start = Int64(starts[at])
        let next = after(at)
        let end = if (kind == TK_OBJECT || kind == TK_ARRAY) {
            // a container's closing bracket is the byte before whatever its last scalar's end leads to:
            // found by scanning back over whitespace from the next token's start, or the input's end
            closingBracket(start)
        } else if (kind == TK_STRING_PLAIN || kind == TK_STRING_ESCAPED) {
            Int64(ends[at]) + 1
        } else {
            Int64(ends[at])
        }
        at = next
        bytes[start..end]
    }

    /** Past the bracket closing the container opened at `open`: a second scan, which `rawValue` of a container pays. */
    private func closingBracket(open: Int64): Int64 {
        reader.rewind(open)
        reader.skipValue()
        reader.position
    }
}
