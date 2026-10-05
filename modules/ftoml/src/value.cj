package ftoml

import std.collection.*
import std.deriving.*
import index_map.IndexMap

/*
 * A TOML document as read: every value with the bytes it was read from, tables in the order their
 * keys were first met. Not lossless - comments and layout are gone - and not for editing: what
 * `FromToml` reads from, and what a diagnostic points into.
 */

public enum FtData {
    | AsString(String)
    | AsInteger(Int64)
    | AsFloat(Float64)
    | AsBool(Bool)
    | AsOffsetDateTime(OffsetDateTime)
    | AsLocalDateTime(LocalDateTime)
    | AsLocalDate(LocalDate)
    | AsLocalTime(LocalTime)
    | AsArray(FtArray)
    | AsTable(FtTable)

    /** What the value is, as an error message names it: `a string`, `a table`. */
    public prop kindName: String {
        get() {
            match (this) {
                case AsString(_) => "a string"
                case AsInteger(_) => "an integer"
                case AsFloat(_) => "a float"
                case AsBool(_) => "a boolean"
                case AsOffsetDateTime(_) => "an offset date-time"
                case AsLocalDateTime(_) => "a local date-time"
                case AsLocalDate(_) => "a local date"
                case AsLocalTime(_) => "a local time"
                case AsArray(_) => "an array"
                case AsTable(_) => "a table"
            }
        }
    }
}

/**
 * A value and where it was read: `start..end` are byte offsets into the document. A table's are
 * where it was introduced - its header, its first dotted key, its braces; the root table's are
 * empty, at 0.
 */
public class FtValue {
    public let data: FtData
    var startAt: Int64
    var endAt: Int64

    public init(data: FtData, start!: Int64 = 0, end!: Int64 = 0) {
        this.data = data
        startAt = start
        endAt = end
    }

    public prop start: Int64 {
        get() {
            startAt
        }
    }

    public prop end: Int64 {
        get() {
            endAt
        }
    }

    /** An error about this value, placed at it. */
    public func error(reason: String): FtException {
        FtException(reason, startAt)
    }

    /** That this value is not what was expected. */
    public func expected(what: String): FtException {
        error("expected ${what}, found ${data.kindName}")
    }

    public func asString(): String {
        match (data) {
            case AsString(v) => v
            case _ => throw expected("a string")
        }
    }

    public func asInteger(): Int64 {
        match (data) {
            case AsInteger(v) => v
            case _ => throw expected("an integer")
        }
    }

    /** A float, or an integer as the nearest one: `1` where a float is expected is one. */
    public func asFloat(): Float64 {
        match (data) {
            case AsFloat(v) => v
            case AsInteger(v) => Float64(v)
            case _ => throw expected("a float")
        }
    }

    public func asBool(): Bool {
        match (data) {
            case AsBool(v) => v
            case _ => throw expected("a boolean")
        }
    }

    public func asArray(): FtArray {
        match (data) {
            case AsArray(v) => v
            case _ => throw expected("an array")
        }
    }

    public func asTable(): FtTable {
        match (data) {
            case AsTable(v) => v
            case _ => throw expected("a table")
        }
    }
}

/**
 * How a table came to be, which decides what may still add to it (the `Table` section of the spec):
 * a header defines one once, dotted keys define the tables they pass through, and an inline table
 * is complete when its braces close.
 */
@Derive[Equatable]
enum TableOrigin {
    /** Named on the way to another: `a` of `[a.b]`. A header may still define it, once. */
    | Implicit
    /** `[a]` */
    | Header
    /** `a` of `a.b = 1`. Only more dotted keys under the same header add to it. */
    | Dotted
    /** `{ ... }`: nothing adds to it. */
    | Braced
    /** An element of `[[a]]`: a table its header defined. */
    | ArrayElement
}

public class FtTable <: Iterable<(String, FtValue)> {
    let entries = IndexMap<String, FtValue>()
    // where each key was written, by the index of its entry
    let keySpans = ArrayList<(Int64, Int64)>()
    var origin: TableOrigin
    // how many tables and arrays it is in: the root is at 0, and none deeper than `NESTING_MAX`
    var level: Int64

    init(origin: TableOrigin, level!: Int64 = 0) {
        this.origin = origin
        this.level = level
    }

    public prop size: Int64 {
        get() {
            entries.size
        }
    }

    public func get(key: String): ?FtValue {
        entries.get(key)
    }

    public func contains(key: String): Bool {
        entries.contains(key)
    }

    /** The keys and their values, in the order the keys were first met. */
    public func iterator(): Iterator<(String, FtValue)> {
        entries.iterator()
    }

    /** Where `key` was written: its last part, for a dotted key. */
    public func keySpan(key: String): ?(Int64, Int64) {
        entries.indexOf(key).map {index => keySpans[index]}
    }

    func add(key: String, value: FtValue, keyStart!: Int64 = 0, keyEnd!: Int64 = 0): Unit {
        entries.add(key, value)
        keySpans.add((keyStart, keyEnd))
    }
}

public class FtArray <: Iterable<FtValue> {
    let items = ArrayList<FtValue>()
    /** `[[a]]`, which more such headers add to; an array written as a value is complete. */
    let isTableArray: Bool

    init(isTableArray: Bool) {
        this.isTableArray = isTableArray
    }

    public prop size: Int64 {
        get() {
            items.size
        }
    }

    public operator func [](index: Int64): FtValue {
        items[index]
    }

    public func iterator(): Iterator<FtValue> {
        items.iterator()
    }
}

/**
 * A document: its root table, and the bytes it was read from, for placing an error by line.
 */
public class FtDocument {
    public FtDocument(public let root: FtValue, public let bytes: Array<Byte>) {}

    public prop table: FtTable {
        get() {
            root.asTable()
        }
    }
}
