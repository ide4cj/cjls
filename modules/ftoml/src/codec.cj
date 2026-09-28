package ftoml

import std.collection.*

/**
 * How a value is written under a key of a table - what decides where in the table it goes, as
 * TOML wants a table's plain keys before its sub-tables.
 */
public enum FtShape {
    /** Nothing is written, not even the key: `None`, as TOML has no `null`. */
    | Omitted
    /** `key = value` on the key's line: scalars, and arrays that are not arrays of tables. */
    | Inline
    /** A `[header]` of its own. */
    | Table
    /** A `[[header]]` per item: a non-empty array of tables. */
    | TableArray

    /** Written under a header, so after every `Inline` key of its table. */
    public prop isBlock: Bool {
        get() {
            match (this) {
                case Table | TableArray => true
                case _ => false
            }
        }
    }

    public prop isOmitted: Bool {
        get() {
            match (this) {
                case Omitted => true
                case _ => false
            }
        }
    }
}

/**
 * A value that writes itself as TOML: serde's `Serialize`, for one format.
 */
public interface ToToml {
    func toToml(w: FtWriter): Unit

    /**
     * How it is written under a key. A value's own, not its type's: an empty array of tables is
     * `[]` among the plain keys, `None` is nothing, and an untagged enum is whichever its variant is.
     */
    prop tomlShape: FtShape {
        get() {
            Inline
        }
    }
}

/**
 * A value read from a document: serde's `Deserialize`. A value that is not a `T` throws
 * `FtException`, placed at it.
 */
public interface FromToml<T> {
    static func fromToml(v: FtValue): T
}

/**
 * A type whose values are a table's keys: `String`, and whatever a key maps to - as `fjson`'s
 * `JsonKey`, since `HashMap<String, V>` extended for itself crashes cjc 1.3.0-alpha.
 */
public interface TomlKey<K> {
    func toTomlKey(): String

    static func fromTomlKey(key: String): K
}

extend String <: TomlKey<String> {
    public func toTomlKey(): String {
        this
    }

    public static func fromTomlKey(key: String): String {
        key
    }
}

/**
 * `value` as a TOML document.
 *
 * @throws FtException - if it is not a table, which is all a document can be
 */
public func toTomlBytes<T>(value: T): Array<Byte> where T <: ToToml {
    match (value.tomlShape) {
        case Table => ()
        case _ => throw FtException("a TOML document is a table", 0)
    }
    let w = FtWriter()
    value.toToml(w)
    w.bytes()
}

/** `value` as the text of a TOML document. */
public func toTomlString<T>(value: T): String where T <: ToToml {
    String.fromUtf8(toTomlBytes(value))
}

/**
 * The document read as a `T`.
 *
 * @throws FtException - if it is not one, placed by line and column in the document
 */
public func fromToml<T>(document: FtDocument): T where T <: FromToml<T> {
    try {
        T.fromToml(document.root)
    } catch (e: FtException) {
        throw e.locatedIn(document.bytes)
    }
}

/**
 * `bytes` read as a TOML document, and that as a `T`.
 *
 * @throws FtException - if they are not TOML, or not a `T`, placed by line and column
 */
public func fromTomlBytes<T>(bytes: Array<Byte>): T where T <: FromToml<T> {
    fromToml<T>(parseToml(bytes))
}

/** `text` read as a TOML document, and that as a `T`. */
public func fromTomlString<T>(text: String): T where T <: FromToml<T> {
    fromTomlBytes<T>(text.toArray())
}

/**
 * A required key missing from the table `table`: what a generated decoder throws, placed at the
 * table.
 */
public func missingKey(table: FtValue, typeName: String, key: String): FtException {
    table.error("`${typeName}` misses the key \"${key}\"")
}

/**
 * The entries of a table written in the order TOML wants: `write` of each whose value is written on
 * its key's line, then of each that is a table or an array of tables; nothing for an omitted one.
 */
public func writeEntries<K, V>(w: FtWriter, entries: Iterable<(K, V)>): Unit where K <: TomlKey<K>, V <: ToToml {
    for ((key, value) in entries) {
        let shape = value.tomlShape
        if (!shape.isBlock && !shape.isOmitted) {
            w.key(key.toTomlKey())
            value.toToml(w)
        }
    }
    for ((key, value) in entries where value.tomlShape.isBlock) {
        w.key(key.toTomlKey())
        value.toToml(w)
    }
}

extend String <: ToToml & FromToml<String> {
    public func toToml(w: FtWriter): Unit {
        w.string(this)
    }

    public static func fromToml(v: FtValue): String {
        v.asString()
    }
}

extend Bool <: ToToml & FromToml<Bool> {
    public func toToml(w: FtWriter): Unit {
        w.bool(this)
    }

    public static func fromToml(v: FtValue): Bool {
        v.asBool()
    }
}

extend Int64 <: ToToml & FromToml<Int64> {
    public func toToml(w: FtWriter): Unit {
        w.int64(this)
    }

    public static func fromToml(v: FtValue): Int64 {
        v.asInteger()
    }
}

extend Int32 <: ToToml & FromToml<Int32> {
    public func toToml(w: FtWriter): Unit {
        w.int64(Int64(this))
    }

    public static func fromToml(v: FtValue): Int32 {
        let i = v.asInteger()
        if (i < Int64(Int32.Min) || i > Int64(Int32.Max)) {
            throw v.error("an integer out of the range of 32 bits")
        }
        Int32(i)
    }
}

extend UInt32 <: ToToml & FromToml<UInt32> {
    public func toToml(w: FtWriter): Unit {
        w.int64(Int64(this))
    }

    public static func fromToml(v: FtValue): UInt32 {
        let i = v.asInteger()
        if (i < 0 || i > Int64(UInt32.Max)) {
            throw v.error("an integer out of the range of unsigned 32 bits")
        }
        UInt32(i)
    }
}

extend Float64 <: ToToml & FromToml<Float64> {
    public func toToml(w: FtWriter): Unit {
        w.float64(this)
    }

    public static func fromToml(v: FtValue): Float64 {
        v.asFloat()
    }
}

extend OffsetDateTime <: ToToml & FromToml<OffsetDateTime> {
    public func toToml(w: FtWriter): Unit {
        w.offsetDateTime(this)
    }

    public static func fromToml(v: FtValue): OffsetDateTime {
        match (v.data) {
            case AsOffsetDateTime(value) => value
            case _ => throw v.expected("an offset date-time")
        }
    }
}

extend LocalDateTime <: ToToml & FromToml<LocalDateTime> {
    public func toToml(w: FtWriter): Unit {
        w.localDateTime(this)
    }

    public static func fromToml(v: FtValue): LocalDateTime {
        match (v.data) {
            case AsLocalDateTime(value) => value
            case _ => throw v.expected("a local date-time")
        }
    }
}

extend LocalDate <: ToToml & FromToml<LocalDate> {
    public func toToml(w: FtWriter): Unit {
        w.localDate(this)
    }

    public static func fromToml(v: FtValue): LocalDate {
        match (v.data) {
            case AsLocalDate(value) => value
            case _ => throw v.expected("a local date")
        }
    }
}

extend LocalTime <: ToToml & FromToml<LocalTime> {
    public func toToml(w: FtWriter): Unit {
        w.localTime(this)
    }

    public static func fromToml(v: FtValue): LocalTime {
        match (v.data) {
            case AsLocalTime(value) => value
            case _ => throw v.expected("a local time")
        }
    }
}

/** An array of tables is `[[key]]`s when it has any, `[]` when it has none. */
extend<T> Array<T> <: ToToml where T <: ToToml {
    public func toToml(w: FtWriter): Unit {
        let tables = match (tomlShape) {
            case TableArray => true
            case _ => false
        }
        if (tables) {
            w.beginTableArray()
        } else {
            w.beginArray()
        }
        for (item in this) {
            if (item.tomlShape.isOmitted) {
                throw FtException("an array cannot hold nothing: TOML has no null", 0)
            }
            item.toToml(w)
        }
        if (tables) {
            w.endTableArray()
        } else {
            w.endArray()
        }
    }

    public prop tomlShape: FtShape {
        get() {
            if (!isEmpty() && this.iterator().all {item => match (item.tomlShape) {
                case Table => true
                case _ => false
            }}) {
                TableArray
            } else {
                Inline
            }
        }
    }
}

extend<T> Array<T> <: FromToml<Array<T>> where T <: FromToml<T> {
    public static func fromToml(v: FtValue): Array<T> {
        let array = v.asArray()
        Array<T>(array.size) {i => T.fromToml(array[i])}
    }
}

/**
 * `None` is nothing at all - TOML has no `null` - and a value is `Some`: an absent key is the
 * decoder's to read as `None`, as only it knows the key was not there.
 */
extend<T> Option<T> <: ToToml where T <: ToToml {
    public func toToml(w: FtWriter): Unit {
        match (this) {
            case Some(value) => value.toToml(w)
            case None => throw FtException("nothing cannot be written: TOML has no null", 0)
        }
    }

    public prop tomlShape: FtShape {
        get() {
            match (this) {
                case Some(value) => value.tomlShape
                case None => Omitted
            }
        }
    }
}

extend<T> Option<T> <: FromToml<Option<T>> where T <: FromToml<T> {
    public static func fromToml(v: FtValue): Option<T> {
        T.fromToml(v)
    }
}

/** A table of any keys. */
extend<K, V> HashMap<K, V> <: ToToml where K <: TomlKey<K>, V <: ToToml {
    public func toToml(w: FtWriter): Unit {
        w.beginTable()
        writeEntries(w, this)
        w.endTable()
    }

    public prop tomlShape: FtShape {
        get() {
            Table
        }
    }
}

extend<K, V> HashMap<K, V> <: FromToml<HashMap<K, V>> where K <: TomlKey<K> & Hashable & Equatable<K>, V <: FromToml<V> {
    public static func fromToml(v: FtValue): HashMap<K, V> {
        let map = HashMap<K, V>()
        for ((key, value) in v.asTable()) {
            map[K.fromTomlKey(key)] = V.fromToml(value)
        }
        map
    }
}

/** A value as it was read, written back as it is: what a field of any TOML at all holds. */
extend FtValue <: ToToml & FromToml<FtValue> {
    public func toToml(w: FtWriter): Unit {
        match (data) {
            case AsString(v) => w.string(v)
            case AsInteger(v) => w.int64(v)
            case AsFloat(v) => w.float64(v)
            case AsBool(v) => w.bool(v)
            case AsOffsetDateTime(v) => w.offsetDateTime(v)
            case AsLocalDateTime(v) => w.localDateTime(v)
            case AsLocalDate(v) => w.localDate(v)
            case AsLocalTime(v) => w.localTime(v)
            case AsArray(array) =>
                let items = array.items.toArray()
                items.toToml(w)
            case AsTable(table) =>
                w.beginTable()
                writeEntries(w, table)
                w.endTable()
        }
    }

    public prop tomlShape: FtShape {
        get() {
            match (data) {
                case AsTable(_) => Table
                case AsArray(array) => array.items.toArray().tomlShape
                case _ => Inline
            }
        }
    }

    public static func fromToml(v: FtValue): FtValue {
        v
    }
}
