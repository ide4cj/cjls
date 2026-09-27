package ftoml

import std.collection.*
import fnum.{FLOAT64_CHARS_MAX, writeShortest}

/*
 * TOML written straight into bytes, no document in between. What TOML imposes on the order is the
 * caller's to follow - a table's plain keys before its sub-tables, which `ToToml.tomlShape` lets a
 * generated encoder sort - and the writer's to check: a key after a sub-table of its table would
 * land in the sub-table, so it throws rather than write something that reads back otherwise.
 */

let HEX_DIGITS: Array<String> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]

enum FrameKind {
    /** The document's own table: keys, then headers. */
    | RootFrame
    /** A table under its `[header]`. */
    | BlockFrame
    /** An array of tables: each table in it opens with `[[header]]`. */
    | TableArrayFrame
    | InlineTableFrame
    | InlineArrayFrame
}

class Frame {
    // nothing written in it yet: no comma before its first member
    var first = true
    // a header was written under it: no more plain keys
    var hasSubTables = false

    Frame(let kind: FrameKind, let path: String) {}

    prop isBlock: Bool {
        get() {
            match (kind) {
                case RootFrame | BlockFrame => true
                case _ => false
            }
        }
    }
}

public class FtWriter {
    private var buf: Array<Byte>
    private var length = 0
    private let frames = ArrayList<Frame>()
    private var pendingKey: ?String = None

    public init(capacity!: Int64 = 1024) {
        buf = Array<Byte>(capacity, repeat: 0)
    }

    /** What was written: a slice of the buffer. */
    public func bytes(): Array<Byte> {
        buf[0..length]
    }

    private func fail(reason: String): FtException {
        FtException(reason, length)
    }

    private func reserve(extra: Int64): Unit {
        if (length + extra > buf.size) {
            let grown = Array<Byte>(max(buf.size * 2, length + extra), repeat: 0)
            buf.copyTo(grown, 0, 0, length)
            buf = grown
        }
    }

    private func put(b: Byte): Unit {
        reserve(1)
        buf[length] = b
        length++
    }

    private func put(text: String): Unit {
        let source = unsafe { text.rawData() }
        reserve(source.size)
        source.copyTo(buf, 0, length, source.size)
        length += source.size
    }

    private func top(): Frame {
        if (frames.isEmpty()) {
            throw fail("a TOML document is a table: begin it with `beginTable`")
        }
        frames[frames.size - 1]
    }

    /** The key the next value is written under, in a table. */
    public func key(name: String): Unit {
        if (let Some(pending) <- pendingKey) {
            throw fail("the key `${pending}` has no value")
        }
        pendingKey = name
    }

    private func takeKey(): String {
        let name = pendingKey ?? throw fail("a value in a table needs a key")
        pendingKey = None
        name
    }

    /** What comes before a value: its key and `=` in a table, a comma in an array. */
    private func beforeValue(): Unit {
        let frame = top()
        match (frame.kind) {
            case RootFrame | BlockFrame =>
                let name = takeKey()
                if (frame.hasSubTables) {
                    throw fail("the key `${name}` would follow a sub-table of its table: write plain keys first")
                }
                putKey(name)
                put(" = ")
            case TableArrayFrame => throw fail("an array of tables holds only tables")
            case InlineTableFrame =>
                let name = takeKey()
                if (!frame.first) {
                    put(", ")
                }
                frame.first = false
                putKey(name)
                put(" = ")
            case InlineArrayFrame =>
                if (!frame.first) {
                    put(", ")
                }
                frame.first = false
        }
    }

    private func afterValue(): Unit {
        if (top().isBlock) {
            put(0x0A)
        }
    }

    private func pathOf(parent: String, name: String): String {
        let quoted = keyText(name)
        if (parent.isEmpty()) { quoted } else { "${parent}.${quoted}" }
    }

    private func header(open: String, path: String, close: String): Unit {
        if (length > 0) {
            put(0x0A)
        }
        put(open)
        put(path)
        put(close)
        put(0x0A)
    }

    /**
     * A table: the document itself when nothing was begun yet, a `[header]` for a key of a table
     * written with headers, an element's `[[header]]` in an array of tables, `{ ... }` anywhere else.
     */
    public func beginTable(): Unit {
        if (frames.isEmpty()) {
            frames.add(Frame(RootFrame, ""))
            return
        }
        let frame = top()
        match (frame.kind) {
            case RootFrame | BlockFrame =>
                let path = pathOf(frame.path, takeKey())
                frame.hasSubTables = true
                header("[", path, "]")
                frames.add(Frame(BlockFrame, path))
            case TableArrayFrame =>
                header("[[", frame.path, "]]")
                frames.add(Frame(BlockFrame, frame.path))
            case _ =>
                beforeValue()
                put("{")
                frames.add(Frame(InlineTableFrame, ""))
        }
    }

    private func pop(): Frame {
        let frame = top()
        frames.remove(at: frames.size - 1)
        frame
    }

    public func endTable(): Unit {
        let frame = pop()
        if (let Some(pending) <- pendingKey) {
            throw fail("the key `${pending}` has no value")
        }
        match (frame.kind) {
            case InlineTableFrame =>
                put("}")
                afterValue()
            case RootFrame | BlockFrame => ()
            case _ => throw fail("`endTable` closes no table")
        }
    }

    /** An array written as a value, `[ ... ]`. */
    public func beginArray(): Unit {
        beforeValue()
        put("[")
        frames.add(Frame(InlineArrayFrame, ""))
    }

    public func endArray(): Unit {
        let frame = pop()
        match (frame.kind) {
            case InlineArrayFrame =>
                put("]")
                afterValue()
            case _ => throw fail("`endArray` closes no array")
        }
    }

    /**
     * An array of tables, each item begun with `beginTable`: `[[header]]`s for a key of a table
     * written with headers, `[{ ... }, ...]` anywhere else. An empty one is `[]`, a value: write it
     * with `beginArray`, among the plain keys.
     */
    public func beginTableArray(): Unit {
        let frame = top()
        match (frame.kind) {
            case RootFrame | BlockFrame =>
                let path = pathOf(frame.path, takeKey())
                frame.hasSubTables = true
                frames.add(Frame(TableArrayFrame, path))
            case _ => beginArray()
        }
    }

    public func endTableArray(): Unit {
        match (top().kind) {
            case TableArrayFrame =>
                pop()
                ()
            case _ => endArray()
        }
    }

    public func string(value: String): Unit {
        beforeValue()
        quoted(value)
        afterValue()
    }

    public func int64(value: Int64): Unit {
        beforeValue()
        put(value.toString())
        afterValue()
    }

    /** The shortest decimal that reads back as `value`, `inf` and `nan` as TOML spells them. */
    public func float64(value: Float64): Unit {
        beforeValue()
        if (value.isNaN()) {
            put("nan")
        } else if (value.isInf()) {
            put(if (value > 0.0) { "inf" } else { "-inf" })
        } else {
            reserve(FLOAT64_CHARS_MAX)
            length = writeShortest(buf, length, value)
        }
        afterValue()
    }

    public func bool(value: Bool): Unit {
        beforeValue()
        put(if (value) { "true" } else { "false" })
        afterValue()
    }

    public func offsetDateTime(value: OffsetDateTime): Unit {
        literal(value.toString())
    }

    public func localDateTime(value: LocalDateTime): Unit {
        literal(value.toString())
    }

    public func localDate(value: LocalDate): Unit {
        literal(value.toString())
    }

    public func localTime(value: LocalTime): Unit {
        literal(value.toString())
    }

    private func literal(text: String): Unit {
        beforeValue()
        put(text)
        afterValue()
    }

    /** A key bare when it can be, quoted when it has to be. */
    private func putKey(name: String): Unit {
        put(keyText(name))
    }

    private func keyText(name: String): String {
        let bare = !name.isEmpty() && name.toArray().iterator().all {
            b => (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39) || b == 0x5F ||
                b == 0x2D
        }
        if (bare) {
            return name
        }
        let mark = length
        quoted(name)
        let text = unsafe { String.fromUtf8Unchecked(buf[mark..length]) }
        length = mark
        text
    }

    /**
     * A basic string: `"` and `\` escaped, and every control character - as TOML 1.0 has them, so
     * that a reader of 1.0 (cjpm's) reads it too.
     */
    private func quoted(value: String): Unit {
        let source = unsafe { value.rawData() }
        reserve(source.size + 2)
        put(0x22)
        var runStart = 0
        for (i in 0..source.size) {
            let b = source[i]
            if (b != 0x22 && b != 0x5C && b >= 0x20 && b != 0x7F) {
                continue
            }
            if (i > runStart) {
                reserve(i - runStart)
                source.copyTo(buf, runStart, length, i - runStart)
                length += i - runStart
            }
            runStart = i + 1
            match (b) {
                case 0x22 => put("\\\"")
                case 0x5C => put("\\\\")
                case 0x08 => put("\\b")
                case 0x09 => put("\\t")
                case 0x0A => put("\\n")
                case 0x0C => put("\\f")
                case 0x0D => put("\\r")
                case _ => put("\\u00${HEX_DIGITS[Int64(b >> 4)]}${HEX_DIGITS[Int64(b & 0x0F)]}")
            }
        }
        if (source.size > runStart) {
            reserve(source.size - runStart)
            source.copyTo(buf, runStart, length, source.size - runStart)
            length += source.size - runStart
        }
        put(0x22)
    }
}

