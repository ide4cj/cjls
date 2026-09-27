package fjson

import std.collection.*

/**
 * A value that writes itself as JSON: serde's `Serialize`, for one format. `@DeriveExt[ToJson]`
 * generates it.
 */
public interface ToJson {
    func toJson(w: FjWriter): Unit
}

/**
 * A value read from the JSON at the reader: serde's `Deserialize`. `@DeriveExt[FromJson]` generates
 * it. A value that does not read throws, `FjException` for what the JSON says and `OverflowException`
 * never: numbers are range-checked by the reader.
 */
public interface FromJson<T> {
    static func fromJson(r: FjReader): T
}

/** `value` as the bytes of one JSON text. */
public func toJsonBytes<T>(value: T): Array<Byte> where T <: ToJson {
    let w = FjWriter()
    value.toJson(w)
    w.bytes()
}

/**
 * The one value `bytes` hold, nothing but whitespace after it.
 *
 * @throws FjException - if the bytes are not the JSON of a `T`
 */
public func fromJsonBytes<T>(bytes: Array<Byte>): T where T <: FromJson<T> {
    let r = FjReader(bytes)
    let value = T.fromJson(r)
    r.end()
    value
}

/**
 * A JSON value kept as its own bytes, unread: serde_json's `RawValue`. Read, it is a slice of the
 * input, no copy; written, it is copied as it is. What a message's `params` are until its method
 * says their type.
 */
public struct RawJson <: ToJson & FromJson<RawJson> {
    public RawJson(public let bytes: Array<Byte>) {}

    /** `null`: the result of a request answered with nothing, and absent params read as. */
    public static let NULL = RawJson("null".toArray())

    public static func fromJson(r: FjReader): RawJson {
        RawJson(r.rawValue())
    }

    public func toJson(w: FjWriter): Unit {
        w.raw(bytes)
    }

    /** What `bytes` hold, read as a `T`. */
    public func read<T>(): T where T <: FromJson<T> {
        fromJsonBytes<T>(bytes)
    }

    /** `value`, written. */
    public static func of<T>(value: T): RawJson where T <: ToJson {
        RawJson(toJsonBytes(value))
    }

    public func toString(): String {
        String.fromUtf8(bytes)
    }
}

/**
 * A required field missing when its object closed: what a generated decoder throws.
 */
public func missingField(typeName: String, field: String): FjException {
    FjException("`${typeName}` misses the field \"${field}\"")
}

extend String <: ToJson & FromJson<String> {
    public func toJson(w: FjWriter): Unit {
        w.string(this)
    }

    public static func fromJson(r: FjReader): String {
        r.readString()
    }
}

extend Bool <: ToJson & FromJson<Bool> {
    public func toJson(w: FjWriter): Unit {
        w.bool(this)
    }

    public static func fromJson(r: FjReader): Bool {
        r.readBool()
    }
}

extend Int64 <: ToJson & FromJson<Int64> {
    public func toJson(w: FjWriter): Unit {
        w.int64(this)
    }

    public static func fromJson(r: FjReader): Int64 {
        r.readInt64()
    }
}

extend Int32 <: ToJson & FromJson<Int32> {
    public func toJson(w: FjWriter): Unit {
        w.int32(this)
    }

    public static func fromJson(r: FjReader): Int32 {
        r.readInt32()
    }
}

extend UInt32 <: ToJson & FromJson<UInt32> {
    public func toJson(w: FjWriter): Unit {
        w.uint32(this)
    }

    public static func fromJson(r: FjReader): UInt32 {
        r.readUInt32()
    }
}

extend Float64 <: ToJson & FromJson<Float64> {
    public func toJson(w: FjWriter): Unit {
        w.float64(this)
    }

    public static func fromJson(r: FjReader): Float64 {
        r.readFloat64()
    }
}

extend<T> Array<T> <: ToJson where T <: ToJson {
    public func toJson(w: FjWriter): Unit {
        w.beginArray()
        for (item in this) {
            item.toJson(w)
        }
        w.endArray()
    }
}

extend<T> Array<T> <: FromJson<Array<T>> where T <: FromJson<T> {
    public static func fromJson(r: FjReader): Array<T> {
        let items = ArrayList<T>()
        r.beginArray()
        while (r.nextItem()) {
            items.add(T.fromJson(r))
        }
        items.toArray()
    }
}

/**
 * `None` is `null`, and `null` reads as `None`: an absent key is the decoder's to tell apart, as
 * only it knows the key was there.
 */
extend<T> Option<T> <: ToJson where T <: ToJson {
    public func toJson(w: FjWriter): Unit {
        match (this) {
            case Some(value) => value.toJson(w)
            case None => w.null()
        }
    }
}

extend<T> Option<T> <: FromJson<Option<T>> where T <: FromJson<T> {
    public static func fromJson(r: FjReader): Option<T> {
        if (r.peekNull()) {
            r.readNull()
            return None
        }
        T.fromJson(r)
    }
}

/**
 * A type whose values are an object's keys: `String`. `HashMap<String, V>` alone cannot be extended
 * in place of this - cjc 1.3.0-alpha crashes (`CHIRType::FillGenericArgType`) compiling any package
 * that uses such a map.
 */
public interface JsonKey<K> {
    func toJsonKey(): String

    static func fromJsonKey(key: String): K
}

extend String <: JsonKey<String> {
    public func toJsonKey(): String {
        this
    }

    public static func fromJsonKey(key: String): String {
        key
    }
}

/**
 * An object of any keys: LSP's `{ [key: K]: V }`, whose keys are always strings.
 */
extend<K, V> HashMap<K, V> <: ToJson where K <: JsonKey<K>, V <: ToJson {
    public func toJson(w: FjWriter): Unit {
        w.beginObject()
        for ((key, value) in this) {
            w.name(key.toJsonKey())
            value.toJson(w)
        }
        w.endObject()
    }
}

extend<K, V> HashMap<K, V> <: FromJson<HashMap<K, V>> where K <: JsonKey<K> & Hashable & Equatable<K>, V <: FromJson<V> {
    public static func fromJson(r: FjReader): HashMap<K, V> {
        let map = HashMap<K, V>()
        r.beginObject()
        while (r.nextKey()) {
            let key = K.fromJsonKey(r.key())
            map[key] = V.fromJson(r)
        }
        map
    }
}
