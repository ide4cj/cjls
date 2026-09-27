package ftoml

import std.collection.*
import fnum.parseFloat64

/*
 * TOML 1.1.0 read into a document: every rule is checked on the way, so what `FromToml` reads is
 * valid TOML and nothing else. A table's keys may be spread over the file (`[a]` ... `[a.b]` ...
 * dotted keys), hence a document rather than a pull reader as `fjson` has.
 */

const NESTING_MAX = 512

/**
 * `bytes` read as a TOML document.
 *
 * @throws FtException - at the first thing that is not TOML 1.1.0, placed by line and column
 */
public func parseToml(bytes: Array<Byte>): FtDocument {
    try {
        FtParser(bytes).document()
    } catch (e: FtException) {
        throw e.locatedIn(bytes)
    }
}

/** `text` read as a TOML document. */
public func parseToml(text: String): FtDocument {
    parseToml(text.toArray())
}

struct KeyPart {
    KeyPart(let name!: String, let start!: Int64, let end!: Int64) {}
}

class FtParser {
    private var pos = 0
    private let root = FtTable(Header)
    private var current: FtTable
    // strings with escapes are built here, one buffer for the document
    private var scratch = Array<Byte>(64, repeat: 0)
    private var scratchLength = 0

    FtParser(private let bytes: Array<Byte>) {
        current = root
    }

    func document(): FtDocument {
        // a byte order mark is no part of the text
        if (bytes.size >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
            pos = 3
        }
        while (true) {
            skipWhitespace()
            if (pos >= bytes.size) {
                break
            }
            match (bytes[pos]) {
                case 0x23 => lineEnd()
                case 0x0A | 0x0D => newline()
                case 0x5B =>
                    header()
                    lineEnd()
                case _ =>
                    keyValue(current, 0)
                    lineEnd()
            }
        }
        FtDocument(FtValue(AsTable(root), 0, 0), bytes)
    }

    private func fail(reason: String): FtException {
        FtException(reason, pos)
    }

    private func fail(reason: String, at: Int64): FtException {
        FtException(reason, at)
    }

    private func skipWhitespace(): Unit {
        while (pos < bytes.size && (bytes[pos] == 0x20 || bytes[pos] == 0x09)) {
            pos++
        }
    }

    /** Whitespace, newlines and comments: what may stand between the items of an array or an inline table. */
    private func skipBlank(): Unit {
        while (pos < bytes.size) {
            match (bytes[pos]) {
                case 0x20 | 0x09 => pos++
                case 0x0A | 0x0D => newline()
                case 0x23 => comment()
                case _ => return
            }
        }
    }

    /** `\n` or `\r\n`: a carriage return is nothing on its own. */
    private func newline(): Unit {
        if (bytes[pos] == 0x0A) {
            pos++
            return
        }
        if (pos + 1 < bytes.size && bytes[pos + 1] == 0x0A) {
            pos += 2
            return
        }
        throw fail("a carriage return not followed by a newline")
    }

    /** What may end a line: whitespace, a comment, then a newline or the end. */
    private func lineEnd(): Unit {
        skipWhitespace()
        if (pos < bytes.size && bytes[pos] == 0x23) {
            comment()
        }
        if (pos >= bytes.size) {
            return
        }
        match (bytes[pos]) {
            case 0x0A | 0x0D => newline()
            case _ => throw fail("expected a newline or the end of the document")
        }
    }

    private func comment(): Unit {
        pos++
        while (pos < bytes.size) {
            let b = bytes[pos]
            if (b == 0x0A) {
                return
            }
            if (b == 0x0D) {
                if (pos + 1 < bytes.size && bytes[pos + 1] == 0x0A) {
                    return
                }
                throw fail("a carriage return not followed by a newline")
            }
            if ((b < 0x20 && b != 0x09) || b == 0x7F) {
                throw fail("a control character in a comment")
            }
            pos += if (b >= 0x80) { utf8At(pos) } else { 1 }
        }
    }

    /** The length of the valid UTF-8 character at `at`. */
    private func utf8At(at: Int64): Int64 {
        let length = utf8Length(bytes, at)
        if (length == 0) {
            throw fail("invalid UTF-8", at)
        }
        length
    }

    // --- keys

    private func key(): Array<KeyPart> {
        let parts = ArrayList<KeyPart>()
        parts.add(simpleKey())
        while (true) {
            skipWhitespace()
            if (pos < bytes.size && bytes[pos] == 0x2E) {
                pos++
                skipWhitespace()
                parts.add(simpleKey())
            } else {
                break
            }
        }
        parts.toArray()
    }

    private func simpleKey(): KeyPart {
        let start = pos
        if (pos >= bytes.size) {
            throw fail("expected a key")
        }
        let name = match (bytes[pos]) {
            case 0x22 =>
                if (startsWith(pos, "\"\"\"")) {
                    throw fail("a key cannot be a multi-line string")
                }
                basicString()
            case 0x27 =>
                if (startsWith(pos, "'''")) {
                    throw fail("a key cannot be a multi-line string")
                }
                literalString()
            case _ =>
                while (pos < bytes.size && isBareKeyByte(bytes[pos])) {
                    pos++
                }
                if (pos == start) {
                    throw fail("expected a key")
                }
                unsafe { String.fromUtf8Unchecked(bytes[start..pos]) }
        }
        KeyPart(name: name, start: start, end: pos)
    }

    private func isBareKeyByte(b: Byte): Bool {
        (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || isDigit(b) || b == 0x5F || b == 0x2D
    }

    private func startsWith(at: Int64, text: String): Bool {
        if (at + text.size > bytes.size) {
            return false
        }
        for (i in 0..text.size) {
            if (bytes[at + i] != text[i]) {
                return false
            }
        }
        true
    }

    private func joined(parts: Array<KeyPart>, count: Int64): String {
        String.join(parts[0..count].map {part => part.name}, delimiter: ".")
    }

    // --- tables

    /** A key/value pair into `table`, the tables of a dotted key created on the way. */
    private func keyValue(table: FtTable, depth: Int64): Unit {
        let parts = key()
        skipWhitespace()
        if (pos >= bytes.size || bytes[pos] != 0x3D) {
            throw fail("expected `=` after a key")
        }
        pos++
        skipWhitespace()

        var target = table
        for (i in 0..parts.size - 1) {
            let part = parts[i]
            match (target.get(part.name)) {
                case None =>
                    let created = FtTable(Dotted)
                    target.add(part.name, FtValue(AsTable(created), part.start, part.end), part.start, part.end)
                    target = created
                case Some(existing) => match (existing.data) {
                    // dotted keys add only to tables dotted keys under the same header defined
                    case AsTable(sub) where sub.origin == Dotted => target = sub
                    case AsTable(_) => throw fail("`${joined(parts, i + 1)}` is a table defined elsewhere", part.start)
                    case other => throw fail("`${joined(parts, i + 1)}` is already ${other.kindName}", part.start)
                }
            }
        }
        let last = parts[parts.size - 1]
        if (target.contains(last.name)) {
            throw fail("`${joined(parts, parts.size)}` is defined twice", last.start)
        }
        let value = value(depth)
        target.add(last.name, value, last.start, last.end)
    }

    /** `[a.b]` or `[[a.b]]`; the table it opens becomes the current one. */
    private func header(): Unit {
        let start = pos
        let isArray = pos + 1 < bytes.size && bytes[pos + 1] == 0x5B
        pos += if (isArray) { 2 } else { 1 }
        skipWhitespace()
        let parts = key()
        skipWhitespace()
        if (pos >= bytes.size || bytes[pos] != 0x5D) {
            throw fail("expected `]` closing the header")
        }
        pos++
        if (isArray) {
            if (pos >= bytes.size || bytes[pos] != 0x5D) {
                throw fail("expected `]]` closing the header")
            }
            pos++
        }
        let end = pos

        var parent = root
        for (i in 0..parts.size - 1) {
            let part = parts[i]
            match (parent.get(part.name)) {
                case None =>
                    let created = FtTable(Implicit)
                    parent.add(part.name, FtValue(AsTable(created), part.start, part.end), part.start, part.end)
                    parent = created
                case Some(existing) => match (existing.data) {
                    case AsTable(sub) where sub.origin == Braced =>
                        throw fail("`${joined(parts, i + 1)}` is an inline table, complete as written", part.start)
                    case AsTable(sub) => parent = sub
                    // the element last defined
                    case AsArray(array) where array.isTableArray => parent = array[array.size - 1].asTable()
                    case other => throw fail("`${joined(parts, i + 1)}` is already ${other.kindName}", part.start)
                }
            }
        }

        let last = parts[parts.size - 1]
        let name = joined(parts, parts.size)
        current = if (isArray) {
            let array = match (parent.get(last.name)) {
                case None =>
                    let created = FtArray(true)
                    parent.add(last.name, FtValue(AsArray(created), start, end), last.start, last.end)
                    created
                case Some(existing) => match (existing.data) {
                    case AsArray(array) where array.isTableArray => array
                    case AsArray(_) => throw fail("`${name}` is an array written as a value, complete as written", last.start)
                    case other => throw fail("`${name}` is already ${other.kindName}", last.start)
                }
            }
            let element = FtTable(ArrayElement)
            array.items.add(FtValue(AsTable(element), start, end))
            element
        } else {
            match (parent.get(last.name)) {
                case None =>
                    let created = FtTable(Header)
                    parent.add(last.name, FtValue(AsTable(created), start, end), last.start, last.end)
                    created
                case Some(existing) => match (existing.data) {
                    case AsTable(sub) where sub.origin == Implicit =>
                        sub.origin = Header
                        existing.startAt = start
                        existing.endAt = end
                        sub
                    case AsTable(_) => throw fail("table `${name}` is defined twice", last.start)
                    case other => throw fail("`${name}` is already ${other.kindName}", last.start)
                }
            }
        }
    }

    // --- values

    private func value(depth: Int64): FtValue {
        if (pos >= bytes.size) {
            throw fail("expected a value")
        }
        let start = pos
        let data = match (bytes[pos]) {
            case 0x22 =>
                if (startsWith(pos, "\"\"\"")) {
                    AsString(multilineBasicString())
                } else {
                    AsString(basicString())
                }
            case 0x27 =>
                if (startsWith(pos, "'''")) {
                    AsString(multilineLiteralString())
                } else {
                    AsString(literalString())
                }
            case 0x5B => AsArray(array(depth + 1))
            case 0x7B => AsTable(inlineTable(depth + 1))
            case 0x74 =>
                keyword("true")
                AsBool(true)
            case 0x66 =>
                keyword("false")
                AsBool(false)
            case b where isDigit(b) && (isDateAt(bytes, pos, bytes.size) || isTimeAt(bytes, pos, bytes.size)) =>
                let (data, end) = scanDateTime(bytes, pos, bytes.size)
                pos = end
                data
            case b where isDigit(b) || b == 0x2B || b == 0x2D || b == 0x69 || b == 0x6E => number()
            case _ => throw fail("expected a value")
        }
        FtValue(data, start, pos)
    }

    private func keyword(text: String): Unit {
        if (!startsWith(pos, text)) {
            throw fail("expected a value")
        }
        pos += text.size
    }

    private func array(depth: Int64): FtArray {
        if (depth > NESTING_MAX) {
            throw fail("nested too deep")
        }
        pos++
        let array = FtArray(false)
        while (true) {
            skipBlank()
            if (pos < bytes.size && bytes[pos] == 0x5D) {
                pos++
                return array
            }
            array.items.add(value(depth))
            skipBlank()
            if (pos >= bytes.size) {
                throw fail("expected `,` or `]`")
            }
            match (bytes[pos]) {
                case 0x2C => pos++
                case 0x5D =>
                    pos++
                    return array
                case _ => throw fail("expected `,` or `]`")
            }
        }
        array
    }

    /** `{ ... }`, over several lines and with a trailing comma if need be (TOML 1.1). */
    private func inlineTable(depth: Int64): FtTable {
        if (depth > NESTING_MAX) {
            throw fail("nested too deep")
        }
        pos++
        let table = FtTable(Braced)
        while (true) {
            skipBlank()
            if (pos < bytes.size && bytes[pos] == 0x7D) {
                pos++
                return table
            }
            keyValue(table, depth)
            skipBlank()
            if (pos >= bytes.size) {
                throw fail("expected `,` or `}`")
            }
            match (bytes[pos]) {
                case 0x2C => pos++
                case 0x7D =>
                    pos++
                    return table
                case _ => throw fail("expected `,` or `}`")
            }
        }
        table
    }

    // --- numbers

    private func number(): FtData {
        let start = pos
        while (pos < bytes.size && isNumberByte(bytes[pos])) {
            pos++
        }
        let end = pos
        var at = start
        let negative = bytes[at] == 0x2D
        if (bytes[at] == 0x2B || bytes[at] == 0x2D) {
            at++
        }
        if (isWord(at, end, "inf")) {
            return AsFloat(if (negative) { -Float64.Inf } else { Float64.Inf })
        }
        if (isWord(at, end, "nan")) {
            return AsFloat(Float64.NaN)
        }
        if (at >= end || !isDigit(bytes[at])) {
            throw fail("expected a number", start)
        }
        if (bytes[at] == 0x30 && at + 1 < end && (bytes[at + 1] == 0x78 || bytes[at + 1] == 0x6F || bytes[at + 1] == 0x62)) {
            if (at != start) {
                throw fail("a hexadecimal, octal or binary integer takes no sign", start)
            }
            return AsInteger(radixInteger(at + 2, end))
        }

        // the integer part: no leading zeros
        var i = at
        if (bytes[i] == 0x30) {
            i++
            if (i < end && (isDigit(bytes[i]) || bytes[i] == 0x5F)) {
                throw fail("a leading zero", at)
            }
        } else {
            i = digits(i, end, 10)
        }
        var isFloat = false
        if (i < end && bytes[i] == 0x2E) {
            isFloat = true
            i = digits(i + 1, end, 10)
        }
        if (i < end && (bytes[i] == 0x65 || bytes[i] == 0x45)) {
            isFloat = true
            i++
            if (i < end && (bytes[i] == 0x2B || bytes[i] == 0x2D)) {
                i++
            }
            i = digits(i, end, 10)
        }
        if (i != end) {
            throw fail("expected a number", start)
        }
        if (isFloat) {
            return AsFloat(parseFloat64(bytes, start, end))
        }
        AsInteger(decimalInteger(start, end))
    }

    private func isNumberByte(b: Byte): Bool {
        isBareKeyByte(b) || b == 0x2B || b == 0x2E
    }

    private func isWord(at: Int64, end: Int64, word: String): Bool {
        end - at == word.size && startsWith(at, word)
    }

    private func digitValue(b: Byte, radix: Int64): ?Int64 {
        let d = if (isDigit(b)) {
            Int64(b - 0x30)
        } else if (b >= 0x61 && b <= 0x66) {
            Int64(b - 0x61 + 10)
        } else if (b >= 0x41 && b <= 0x46) {
            Int64(b - 0x41 + 10)
        } else {
            return None
        }
        if (d < radix) { d } else { None }
    }

    /** Past the digits of `radix` from `from`, a `_` allowed only between two of them. */
    private func digits(from: Int64, end: Int64, radix: Int64): Int64 {
        if (from >= end || digitValue(bytes[from], radix).isNone()) {
            throw fail("expected a digit", from)
        }
        var i = from + 1
        while (i < end) {
            if (digitValue(bytes[i], radix).isSome()) {
                i++
            } else if (bytes[i] == 0x5F) {
                if (i + 1 >= end || digitValue(bytes[i + 1], radix).isNone()) {
                    throw fail("an underscore must stand between two digits", i)
                }
                i += 2
            } else {
                break
            }
        }
        i
    }

    private func decimalInteger(start: Int64, end: Int64): Int64 {
        var i = start
        let negative = bytes[i] == 0x2D
        if (bytes[i] == 0x2B || bytes[i] == 0x2D) {
            i++
        }
        // accumulated negative, so that Int64.Min fits
        var v: Int64 = 0
        while (i < end) {
            let b = bytes[i]
            i++
            if (b == 0x5F) {
                continue
            }
            let d = Int64(b - 0x30)
            if (v < (Int64.Min + d) / 10) {
                throw fail("an integer out of the range of 64 bits", start)
            }
            v = v * 10 - d
        }
        if (negative) {
            v
        } else if (v == Int64.Min) {
            throw fail("an integer out of the range of 64 bits", start)
        } else {
            -v
        }
    }

    private func radixInteger(from: Int64, end: Int64): Int64 {
        let radix = match (bytes[from - 1]) {
            case 0x78 => 16
            case 0x6F => 8
            case _ => 2
        }
        if (digits(from, end, radix) != end) {
            throw fail("expected a digit", from)
        }
        var v: Int64 = 0
        for (i in from..end) {
            let d = digitValue(bytes[i], radix) ?? continue
            if (v > (Int64.Max - d) / radix) {
                throw fail("an integer out of the range of 64 bits", from - 2)
            }
            v = v * radix + d
        }
        v
    }

    // --- strings

    private func reserve(extra: Int64): Unit {
        if (scratchLength + extra > scratch.size) {
            let grown = Array<Byte>(max(scratch.size * 2, scratchLength + extra), repeat: 0)
            scratch.copyTo(grown, 0, 0, scratchLength)
            scratch = grown
        }
    }

    private func push(b: Byte): Unit {
        reserve(1)
        scratch[scratchLength] = b
        scratchLength++
    }

    private func pushRange(from: Int64, to: Int64): Unit {
        reserve(to - from)
        bytes.copyTo(scratch, from, scratchLength, to - from)
        scratchLength += to - from
    }

    private func takeScratch(): String {
        let text = unsafe { String.fromUtf8Unchecked(scratch[0..scratchLength]) }
        scratchLength = 0
        text
    }

    /** `"..."`: on one line, with escapes. */
    private func basicString(): String {
        pos++
        let start = pos
        // the common case: no escape, one copy
        while (pos < bytes.size) {
            let b = bytes[pos]
            if (b == 0x22) {
                let text = unsafe { String.fromUtf8Unchecked(bytes[start..pos]) }
                pos++
                return text
            }
            if (b == 0x5C || b < 0x20 || b == 0x7F) {
                break
            }
            pos += if (b >= 0x80) { utf8At(pos) } else { 1 }
        }
        scratchLength = 0
        pushRange(start, pos)
        while (true) {
            if (pos >= bytes.size) {
                throw fail("an unterminated string")
            }
            let b = bytes[pos]
            if (b == 0x22) {
                pos++
                return takeScratch()
            }
            if (b == 0x5C) {
                escape()
            } else if (b == 0x0A || b == 0x0D) {
                throw fail("a newline in a single-line string")
            } else if ((b < 0x20 && b != 0x09) || b == 0x7F) {
                throw fail("a control character in a string")
            } else {
                let length = if (b >= 0x80) { utf8At(pos) } else { 1 }
                pushRange(pos, pos + length)
                pos += length
            }
        }
        ""
    }

    /** `"""..."""`: over lines, with escapes, and a backslash ending a line trimming the whitespace after it. */
    private func multilineBasicString(): String {
        pos += 3
        skipFirstNewline()
        scratchLength = 0
        while (true) {
            if (pos >= bytes.size) {
                throw fail("an unterminated string")
            }
            let b = bytes[pos]
            if (b == 0x22 && startsWith(pos, "\"\"\"")) {
                return closeMultiline(0x22)
            }
            if (b == 0x5C) {
                if (lineEndingBackslash()) {
                    continue
                }
                escape()
            } else if (b == 0x0D) {
                newline()
                push(0x0D)
                push(0x0A)
            } else if ((b < 0x20 && b != 0x09 && b != 0x0A) || b == 0x7F) {
                throw fail("a control character in a string")
            } else {
                let length = if (b >= 0x80) { utf8At(pos) } else { 1 }
                pushRange(pos, pos + length)
                pos += length
            }
        }
        ""
    }

    /** `'...'`: on one line, as written. */
    private func literalString(): String {
        pos++
        let start = pos
        while (true) {
            if (pos >= bytes.size) {
                throw fail("an unterminated string")
            }
            let b = bytes[pos]
            if (b == 0x27) {
                let text = unsafe { String.fromUtf8Unchecked(bytes[start..pos]) }
                pos++
                return text
            }
            if (b == 0x0A || b == 0x0D) {
                throw fail("a newline in a single-line string")
            }
            if ((b < 0x20 && b != 0x09) || b == 0x7F) {
                throw fail("a control character in a string")
            }
            pos += if (b >= 0x80) { utf8At(pos) } else { 1 }
        }
        ""
    }

    /** `'''...'''`: over lines, as written. */
    private func multilineLiteralString(): String {
        pos += 3
        skipFirstNewline()
        scratchLength = 0
        while (true) {
            if (pos >= bytes.size) {
                throw fail("an unterminated string")
            }
            let b = bytes[pos]
            if (b == 0x27 && startsWith(pos, "'''")) {
                return closeMultiline(0x27)
            }
            if (b == 0x0D) {
                newline()
                push(0x0D)
                push(0x0A)
            } else if ((b < 0x20 && b != 0x09 && b != 0x0A) || b == 0x7F) {
                throw fail("a control character in a string")
            } else {
                let length = if (b >= 0x80) { utf8At(pos) } else { 1 }
                pushRange(pos, pos + length)
                pos += length
            }
        }
        ""
    }

    /** A newline right after the opening delimiter is not part of the string. */
    private func skipFirstNewline(): Unit {
        if (pos < bytes.size && (bytes[pos] == 0x0A || bytes[pos] == 0x0D)) {
            newline()
        }
    }

    /**
     * At three delimiters: up to two more are still the string's (`""""` ends a string with a
     * quote in it), then it closes. Six in a row is three too many.
     */
    private func closeMultiline(delimiter: Byte): String {
        var count = 0
        while (pos + count < bytes.size && bytes[pos + count] == delimiter) {
            count++
        }
        if (count > 5) {
            throw fail("more than five delimiters in a row", pos + 5)
        }
        for (_ in 0..count - 3) {
            push(delimiter)
        }
        pos += count
        takeScratch()
    }

    /**
     * A `\` with nothing but whitespace after it on its line: it, the newline and all the
     * whitespace up to the next character are trimmed.
     */
    private func lineEndingBackslash(): Bool {
        var i = pos + 1
        while (i < bytes.size && (bytes[i] == 0x20 || bytes[i] == 0x09)) {
            i++
        }
        if (i >= bytes.size || (bytes[i] != 0x0A && bytes[i] != 0x0D)) {
            return false
        }
        pos = i
        while (pos < bytes.size) {
            match (bytes[pos]) {
                case 0x20 | 0x09 => pos++
                case 0x0A | 0x0D => newline()
                case _ => break
            }
        }
        true
    }

    private func escape(): Unit {
        let at = pos
        if (pos + 1 >= bytes.size) {
            throw fail("an unterminated string")
        }
        let e = bytes[pos + 1]
        pos += 2
        match (e) {
            case 0x62 => push(0x08)
            case 0x74 => push(0x09)
            case 0x6E => push(0x0A)
            case 0x66 => push(0x0C)
            case 0x72 => push(0x0D)
            case 0x65 => push(0x1B)
            case 0x22 => push(0x22)
            case 0x5C => push(0x5C)
            case 0x78 => pushCodePoint(hex(2), at)
            case 0x75 => pushCodePoint(hex(4), at)
            case 0x55 => pushCodePoint(hex(8), at)
            case _ => throw fail("an invalid escape", at)
        }
    }

    private func hex(count: Int64): UInt32 {
        var v: UInt64 = 0
        for (_ in 0..count) {
            if (pos >= bytes.size) {
                throw fail("an unterminated escape")
            }
            let d = digitValue(bytes[pos], 16) ?? throw fail("expected a hexadecimal digit")
            v = v * 16 + UInt64(d)
            pos++
        }
        if (v > 0x10FFFF) {
            return 0xFFFF_FFFF
        }
        UInt32(v)
    }

    private func pushCodePoint(cp: UInt32, at: Int64): Unit {
        if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
            throw fail("an escape of something not a Unicode scalar value", at)
        }
        reserve(4)
        if (cp < 0x80) {
            push(UInt8(cp))
        } else if (cp < 0x800) {
            push(UInt8(0xC0 | (cp >> 6)))
            push(UInt8(0x80 | (cp & 0x3F)))
        } else if (cp < 0x10000) {
            push(UInt8(0xE0 | (cp >> 12)))
            push(UInt8(0x80 | ((cp >> 6) & 0x3F)))
            push(UInt8(0x80 | (cp & 0x3F)))
        } else {
            push(UInt8(0xF0 | (cp >> 18)))
            push(UInt8(0x80 | ((cp >> 12) & 0x3F)))
            push(UInt8(0x80 | ((cp >> 6) & 0x3F)))
            push(UInt8(0x80 | (cp & 0x3F)))
        }
    }
}

/**
 * The length of the UTF-8 sequence starting at `i`, or 0 when it is not a valid one: overlong
 * forms, surrogates and code points past U+10FFFF included, as RFC 3629 has it.
 */
func utf8Length(bytes: Array<Byte>, i: Int64): Int64 {
    let n = bytes.size
    let b0 = bytes[i]
    func cont(at: Int64): Bool {
        at < n && (bytes[at] & 0xC0) == 0x80
    }
    if (b0 >= 0xC2 && b0 <= 0xDF) {
        return if (cont(i + 1)) { 2 } else { 0 }
    }
    if (b0 >= 0xE0 && b0 <= 0xEF) {
        if (i + 1 >= n) {
            return 0
        }
        let b1 = bytes[i + 1]
        let ok = match (b0) {
            case 0xE0 => b1 >= 0xA0 && b1 <= 0xBF
            case 0xED => b1 >= 0x80 && b1 <= 0x9F
            case _ => (b1 & 0xC0) == 0x80
        }
        return if (ok && cont(i + 2)) { 3 } else { 0 }
    }
    if (b0 >= 0xF0 && b0 <= 0xF4) {
        if (i + 1 >= n) {
            return 0
        }
        let b1 = bytes[i + 1]
        let ok = match (b0) {
            case 0xF0 => b1 >= 0x90 && b1 <= 0xBF
            case 0xF4 => b1 >= 0x80 && b1 <= 0x8F
            case _ => (b1 & 0xC0) == 0x80
        }
        return if (ok && cont(i + 2) && cont(i + 3)) { 4 } else { 0 }
    }
    0
}
