package fjson

/*
 * Layout B of the tape experiment: `FjTape` with one `Int64` a token instead of three arrays. The
 * rest is a copy, so that both layouts are measured in one binary and one run.
 */

// a token's kind, as `FjTape`'s
const TKB_OBJECT: Int64 = 0
const TKB_ARRAY: Int64 = 1
const TKB_KEY_PLAIN: Int64 = 2
const TKB_KEY_ESCAPED: Int64 = 3
const TKB_STRING_PLAIN: Int64 = 4
const TKB_STRING_ESCAPED: Int64 = 5
const TKB_NUMBER: Int64 = 6
const TKB_TRUE: Int64 = 7
const TKB_FALSE: Int64 = 8
const TKB_NULL: Int64 = 9

public class FjTapeB {
    private var bytes = Array<Byte>()
    // layout B: one Int64 a token - the kind in its low 8 bits, the start in the next 28 (a string's or
    // key's: past the opening quote; a number's or literal's: its first byte), the end in the top 28 (a
    // scalar's byte end, a string's closing quote; a container's: the index of the token after it)
    private var tape = Array<Int64>(TAPE_INITIAL, repeat: 0)
    private var count = 0
    // the open containers' token indices, their ends patched on close
    private let stack = Array<Int64>(MAX_DEPTH, repeat: 0)
    // the cursor: the token the next read takes, and the key `nextKey` last stepped over
    private var at = 0
    private var lastKey = 0
    // strings with escapes are unescaped by the reader's code, over the same bytes
    private let reader = FjReader(Array<Byte>())

    public FjTapeB() {}

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
        let grown = Array<Int64>(tape.size * 2, repeat: 0)
        tape.copyTo(grown, 0, 0, count)
        tape = grown
    }

    private func push(kind: Int64, start: Int64, end: Int64): Int64 {
        if (count == tape.size) {
            grow()
        }
        tape[count] = (end << 36) | (start << 8) | kind
        count++
        count - 1
    }

    private func kindAt(token: Int64): Int64 {
        tape[token] & 0xFF
    }

    private func startAt(token: Int64): Int64 {
        (tape[token] >> 8) & 0xFFFFFFF
    }

    private func endAt(token: Int64): Int64 {
        tape[token] >> 36
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
                        depth = close(TKB_OBJECT, depth, pos)
                        pos++
                        expect = if (depth == 0) { EX_END } else { EX_AFTER_VALUE }
                    } else if (b == QUOTE) {
                        pos = string(pos, true)
                        expect = EX_COLON
                    } else {
                        throw fail("expected a key", pos)
                    }
            } else if (expect == EX_AFTER_VALUE) {
                    let open = kindAt(stack[depth - 1])
                    if (b == 0x2C) {
                        pos++
                        expect = if (open == TKB_OBJECT) { EX_KEY } else { EX_VALUE }
                    } else if (b == 0x7D && open == TKB_OBJECT) {
                        depth = close(TKB_OBJECT, depth, pos)
                        pos++
                        expect = if (depth == 0) { EX_END } else { EX_AFTER_VALUE }
                    } else if (b == 0x5D && open == TKB_ARRAY) {
                        depth = close(TKB_ARRAY, depth, pos)
                        pos++
                        expect = if (depth == 0) { EX_END } else { EX_AFTER_VALUE }
                    } else {
                        throw fail(if (open == TKB_OBJECT) { "expected `,` or `}`" } else { "expected `,` or `]`" }, pos)
                    }
            } else {
                    // a value, or the `]` of an array just opened
                    if (b == 0x5D && expect == EX_VALUE_OR_CLOSE) {
                        depth = close(TKB_ARRAY, depth, pos)
                        pos++
                        expect = if (depth == 0) { EX_END } else { EX_AFTER_VALUE }
                        continue
                    }
                    match (b) {
                        case 0x7B =>
                            if (depth >= MAX_DEPTH) {
                                throw fail("nested deeper than ${MAX_DEPTH}", pos)
                            }
                            stack[depth] = push(TKB_OBJECT, pos, 0)
                            depth++
                            pos++
                            expect = EX_KEY_OR_CLOSE
                            continue
                        case 0x5B =>
                            if (depth >= MAX_DEPTH) {
                                throw fail("nested deeper than ${MAX_DEPTH}", pos)
                            }
                            stack[depth] = push(TKB_ARRAY, pos, 0)
                            depth++
                            pos++
                            expect = EX_VALUE_OR_CLOSE
                            continue
                        case 0x22 => pos = string(pos, false)
                        case 0x74 => pos = literal(pos, "true", TKB_TRUE)
                        case 0x66 => pos = literal(pos, "false", TKB_FALSE)
                        case 0x6E => pos = literal(pos, "null", TKB_NULL)
                        case _ => pos = number(pos)
                    }
                    expect = if (depth == 0) { EX_END } else { EX_AFTER_VALUE }
            }
        }
    }

    private func close(kind: Int64, depth: Int64, pos: Int64): Int64 {
        let open = stack[depth - 1]
        if (kindAt(open) != kind) {
            throw fail(if (kind == TKB_OBJECT) { "expected `]`" } else { "expected `}`" }, pos)
        }
        // the end patched in: the index of the token after the container
        tape[open] = (tape[open] & 0xFFFFFFFFF) | (count << 36)
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
            if (escaped) { TKB_KEY_ESCAPED } else { TKB_KEY_PLAIN }
        } else {
            if (escaped) { TKB_STRING_ESCAPED } else { TKB_STRING_PLAIN }
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

    private func literal(pos: Int64, text: String, kind: Int64): Int64 {
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
        push(TKB_NUMBER, pos, i)
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
        let pos = if (at < count) { startAt(at) } else { bytes.size }
        fail(message, pos)
    }

    /** The index of the token after the value at `token`. */
    private func after(token: Int64): Int64 {
        let kind = kindAt(token)
        if (kind == TKB_OBJECT || kind == TKB_ARRAY) {
            endAt(token)
        } else {
            token + 1
        }
    }

    /** Into the object at the cursor; the index of the token after it, for `nextKey`. */
    public func beginObject(): Int64 {
        if (at >= count || kindAt(at) != TKB_OBJECT) {
            throw readFail("expected `{`")
        }
        let end = endAt(at)
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
        let start = startAt(lastKey)
        let length = endAt(lastKey) - start
        if (kindAt(lastKey) == TKB_KEY_ESCAPED) {
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
        if (at >= count || kindAt(at) != TKB_OBJECT) {
            throw readFail("expected `{`")
        }
        let end = endAt(at)
        var key = at + 1
        while (key < end) {
            let start = startAt(key)
            let length = endAt(key) - start
            if (kindAt(key) == TKB_KEY_PLAIN && length == name.size) {
                var i = 0
                while (i < length && bytes[start + i] == name[i]) {
                    i++
                }
                if (i == length) {
                    return true
                }
            } else if (kindAt(key) == TKB_KEY_ESCAPED && stringAt(key) == name) {
                return true
            }
            key = after(key + 1)
        }
        false
    }

    /** Into the array at the cursor; the index of the token after it, for `nextItem`. */
    public func beginArray(): Int64 {
        if (at >= count || kindAt(at) != TKB_ARRAY) {
            throw readFail("expected `[`")
        }
        let end = endAt(at)
        at++
        end
    }

    public func nextItem(end: Int64): Bool {
        at < end
    }

    private func stringAt(token: Int64): String {
        let start = startAt(token)
        let end = endAt(token)
        if (kindAt(token) == TKB_STRING_PLAIN || kindAt(token) == TKB_KEY_PLAIN) {
            return unsafe { String.fromUtf8Unchecked(bytes[start..end]) }
        }
        // the reader's unescape, over the same bytes, from the opening quote
        reader.rewind(start - 1)
        reader.readString()
    }

    public func readString(): String {
        if (at >= count || (kindAt(at) != TKB_STRING_PLAIN && kindAt(at) != TKB_STRING_ESCAPED)) {
            throw readFail("expected a string")
        }
        let s = stringAt(at)
        at++
        s
    }

    /** An integer, `-` and digits: the grammar was checked by `index`, the range is checked here. */
    public func readInt64(): Int64 {
        if (at >= count || kindAt(at) != TKB_NUMBER) {
            throw readFail("expected an integer")
        }
        let start = startAt(at)
        let end = endAt(at)
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
        if (at < count && kindAt(at) == TKB_TRUE) {
            at++
            return true
        }
        if (at < count && kindAt(at) == TKB_FALSE) {
            at++
            return false
        }
        throw readFail("expected a boolean")
    }

    public func isNull(): Bool {
        at < count && kindAt(at) == TKB_NULL
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
        let kind = kindAt(at)
        let start = startAt(at)
        let next = after(at)
        let end = if (kind == TKB_OBJECT || kind == TKB_ARRAY) {
            // a container's closing bracket is the byte before whatever its last scalar's end leads to:
            // found by scanning back over whitespace from the next token's start, or the input's end
            closingBracket(start)
        } else if (kind == TKB_STRING_PLAIN || kind == TKB_STRING_ESCAPED) {
            endAt(at) + 1
        } else {
            endAt(at)
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
