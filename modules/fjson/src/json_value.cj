package fjson

import std.collection.ArrayList

/**
 * Any JSON value at all, `null` included: what a field of any value holds (`LSPAny`), kept as a
 * tree. An object keeps its keys in the order they came, so a value round-trips as it came: an
 * integer stays one, a number with a fraction or an exponent is a `Float64`.
 *
 * The variants are `Json`-prefixed, as `Null`, `Bool`, `String`, `Array` would shadow `std`'s types
 * wherever `fjson.*` is.
 */
public enum JsonValue <: Equatable<JsonValue> {
    | JsonNull
    | JsonBool(Bool)
    | JsonInteger(Int64)
    | JsonFloat(Float64)
    | JsonString(String)
    | JsonArray(Array<JsonValue>)
    | JsonObject(Array<(String, JsonValue)>)

    /** The value under `key` of an object; `None` if there is none, or this is no object. */
    public func get(key: String): ?JsonValue {
        match (this) {
            case JsonObject(members) =>
                for ((name, value) in members where name == key) {
                    return value
                }
                None
            case _ => None
        }
    }

    /**
     * The value under `key` of an object.
     *
     * @throws IllegalArgumentException - if there is none, or this is no object
     */
    public operator func [](key: String): JsonValue {
        get(key) ?? throw IllegalArgumentException("no key \"${key}\" in ${this}")
    }

    /**
     * The item at `index` of an array.
     *
     * @throws IllegalArgumentException - if this is no array
     */
    public operator func [](index: Int64): JsonValue {
        asArray()[index]
    }

    public func isNull(): Bool {
        match (this) {
            case JsonNull => true
            case _ => false
        }
    }

    public func asBool(): Bool {
        match (this) {
            case JsonBool(b) => b
            case _ => throw notA("a boolean")
        }
    }

    public func asInteger(): Int64 {
        match (this) {
            case JsonInteger(i) => i
            case _ => throw notA("an integer")
        }
    }

    public func asFloat(): Float64 {
        match (this) {
            case JsonFloat(f) => f
            case _ => throw notA("a float")
        }
    }

    public func asString(): String {
        match (this) {
            case JsonString(s) => s
            case _ => throw notA("a string")
        }
    }

    public func asArray(): Array<JsonValue> {
        match (this) {
            case JsonArray(items) => items
            case _ => throw notA("an array")
        }
    }

    public func asObject(): Array<(String, JsonValue)> {
        match (this) {
            case JsonObject(members) => members
            case _ => throw notA("an object")
        }
    }

    private func notA(kind: String): IllegalArgumentException {
        IllegalArgumentException("${this} is not ${kind}")
    }

    /** Equal as JSON is, the order of an object's keys included; `NaN` is never read. */
    public operator func ==(other: JsonValue): Bool {
        match ((this, other)) {
            case (JsonNull, JsonNull) => true
            case (JsonBool(a), JsonBool(b)) => a == b
            case (JsonInteger(a), JsonInteger(b)) => a == b
            case (JsonFloat(a), JsonFloat(b)) => a == b
            case (JsonString(a), JsonString(b)) => a == b
            case (JsonArray(a), JsonArray(b)) => a == b
            case (JsonObject(a), JsonObject(b)) =>
                a.size == b.size && (0..a.size).iterator().all {i => a[i][0] == b[i][0] && a[i][1] == b[i][1]}
            case _ => false
        }
    }
}

extend JsonValue <: ToJson & FromJson<JsonValue> & ToString {
    /** The value as JSON. */
    public func toString(): String {
        let w = FjWriter()
        toJson(w)
        String.fromUtf8(w.bytes())
    }

    public func toJson(w: FjWriter): Unit {
        match (this) {
            case JsonNull => w.null()
            case JsonBool(b) => w.bool(b)
            case JsonInteger(i) => w.int64(i)
            case JsonFloat(f) => w.float64(f)
            case JsonString(s) => w.string(s)
            case JsonArray(items) =>
                w.beginArray()
                for (item in items) {
                    item.toJson(w)
                }
                w.endArray()
            case JsonObject(members) =>
                w.beginObject()
                for ((name, value) in members) {
                    w.name(name)
                    value.toJson(w)
                }
                w.endObject()
        }
    }

    /**
     * @throws FjException - if the value is not JSON, or nested deeper than `JSON_VALUE_DEPTH_MAX`
     */
    public static func fromJson(r: FjReader): JsonValue {
        readJsonValue(r, 0)
    }
}

/**
 * How deep an `JsonValue` may nest: it is read recursively, and a client's `initializationOptions`
 * must not be able to run the stack out.
 */
public const JSON_VALUE_DEPTH_MAX = 512

/** The value inside `depth` containers; a container deeper than `JSON_VALUE_DEPTH_MAX` is refused, as `FjReader.skipValue` refuses it. */
private func readJsonValue(r: FjReader, depth: Int64): JsonValue {
    match (r.peekKind()) {
        case FjKind.FjObject | FjKind.FjArray where depth >= JSON_VALUE_DEPTH_MAX =>
            throw FjException("nested deeper than ${JSON_VALUE_DEPTH_MAX} at byte ${r.position}")
        case FjKind.FjObject =>
            let members = ArrayList<(String, JsonValue)>()
            r.beginObject()
            while (r.nextKey()) {
                let key = r.key()
                members.add((key, readJsonValue(r, depth + 1)))
            }
            JsonObject(members.toArray())
        case FjKind.FjArray =>
            let items = ArrayList<JsonValue>()
            r.beginArray()
            while (r.nextItem()) {
                items.add(readJsonValue(r, depth + 1))
            }
            JsonArray(items.toArray())
        case FjKind.FjString => JsonString(r.readString())
        case FjKind.FjBool => JsonBool(r.readBool())
        case FjKind.FjNull =>
            r.readNull()
            JsonNull
        case FjKind.FjNumber =>
            let number = r.rawValue()
            if (number.iterator().any {b => b == 0x2E || b == 0x65 || b == 0x45}) {
                JsonFloat(FjReader(number).readFloat64())
            } else {
                // past Int64, an integer is kept as JavaScript keeps it: the nearest Float64
                try {
                    JsonInteger(FjReader(number).readInt64())
                } catch (_: FjException) {
                    JsonFloat(FjReader(number).readFloat64())
                }
            }
    }
}
