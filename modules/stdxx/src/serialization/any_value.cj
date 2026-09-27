package stdxx.serialization

import std.collection.ArrayList
import fjson.*

/**
 * Any JSON value at all, `null` included: what a field of any value holds (`LSPAny`), kept as a
 * tree. An object keeps its keys in the order they came, so a value round-trips as it came: an
 * integer stays one, a number with a fraction or an exponent is a `Float64`.
 *
 * The variants are `Any`-prefixed: `fjson.*` brings `FjKind`'s `JsonNull`, `JsonArray`... into
 * scope unqualified.
 */
public enum AnyValue <: Equatable<AnyValue> {
    | AnyNull
    | AnyBool(Bool)
    | AnyInteger(Int64)
    | AnyFloat(Float64)
    | AnyString(String)
    | AnyArray(Array<AnyValue>)
    | AnyObject(Array<(String, AnyValue)>)

    /** The value under `key` of an object; `None` if there is none, or this is no object. */
    public func get(key: String): ?AnyValue {
        match (this) {
            case AnyObject(members) =>
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
    public operator func [](key: String): AnyValue {
        get(key) ?? throw IllegalArgumentException("no key \"${key}\" in ${this}")
    }

    /**
     * The item at `index` of an array.
     *
     * @throws IllegalArgumentException - if this is no array
     */
    public operator func [](index: Int64): AnyValue {
        asArray()[index]
    }

    public func isNull(): Bool {
        match (this) {
            case AnyNull => true
            case _ => false
        }
    }

    public func asBool(): Bool {
        match (this) {
            case AnyBool(b) => b
            case _ => throw notA("a boolean")
        }
    }

    public func asInteger(): Int64 {
        match (this) {
            case AnyInteger(i) => i
            case _ => throw notA("an integer")
        }
    }

    public func asFloat(): Float64 {
        match (this) {
            case AnyFloat(f) => f
            case _ => throw notA("a float")
        }
    }

    public func asString(): String {
        match (this) {
            case AnyString(s) => s
            case _ => throw notA("a string")
        }
    }

    public func asArray(): Array<AnyValue> {
        match (this) {
            case AnyArray(items) => items
            case _ => throw notA("an array")
        }
    }

    public func asObject(): Array<(String, AnyValue)> {
        match (this) {
            case AnyObject(members) => members
            case _ => throw notA("an object")
        }
    }

    private func notA(kind: String): IllegalArgumentException {
        IllegalArgumentException("${this} is not ${kind}")
    }

    /** Equal as JSON is, the order of an object's keys included; `NaN` is never read. */
    public operator func ==(other: AnyValue): Bool {
        match ((this, other)) {
            case (AnyNull, AnyNull) => true
            case (AnyBool(a), AnyBool(b)) => a == b
            case (AnyInteger(a), AnyInteger(b)) => a == b
            case (AnyFloat(a), AnyFloat(b)) => a == b
            case (AnyString(a), AnyString(b)) => a == b
            case (AnyArray(a), AnyArray(b)) => a == b
            case (AnyObject(a), AnyObject(b)) =>
                a.size == b.size && (0..a.size).iterator().all {i => a[i][0] == b[i][0] && a[i][1] == b[i][1]}
            case _ => false
        }
    }
}

extend AnyValue <: ToJson & FromJson<AnyValue> & ToString {
    /** The value as JSON. */
    public func toString(): String {
        let w = FjWriter()
        toJson(w)
        String.fromUtf8(w.bytes())
    }

    public func toJson(w: FjWriter): Unit {
        match (this) {
            case AnyNull => w.null()
            case AnyBool(b) => w.bool(b)
            case AnyInteger(i) => w.int64(i)
            case AnyFloat(f) => w.float64(f)
            case AnyString(s) => w.string(s)
            case AnyArray(items) =>
                w.beginArray()
                for (item in items) {
                    item.toJson(w)
                }
                w.endArray()
            case AnyObject(members) =>
                w.beginObject()
                for ((name, value) in members) {
                    w.name(name)
                    value.toJson(w)
                }
                w.endObject()
        }
    }

    /**
     * @throws FjException - if the value is not JSON, or nested deeper than `ANY_VALUE_DEPTH_MAX`
     */
    public static func fromJson(r: FjReader): AnyValue {
        readAnyValue(r, 0)
    }
}

/**
 * How deep an `AnyValue` may nest: it is read recursively, and a client's `initializationOptions`
 * must not be able to run the stack out.
 */
public const ANY_VALUE_DEPTH_MAX = 512

/** The value inside `depth` containers; a container deeper than `ANY_VALUE_DEPTH_MAX` is refused, as `FjReader.skipValue` refuses it. */
private func readAnyValue(r: FjReader, depth: Int64): AnyValue {
    match (r.peekKind()) {
        case FjKind.JsonObject | FjKind.JsonArray where depth >= ANY_VALUE_DEPTH_MAX =>
            throw FjException("nested deeper than ${ANY_VALUE_DEPTH_MAX} at byte ${r.position}")
        case FjKind.JsonObject =>
            let members = ArrayList<(String, AnyValue)>()
            r.beginObject()
            while (r.nextKey()) {
                let key = r.key()
                members.add((key, readAnyValue(r, depth + 1)))
            }
            AnyObject(members.toArray())
        case FjKind.JsonArray =>
            let items = ArrayList<AnyValue>()
            r.beginArray()
            while (r.nextItem()) {
                items.add(readAnyValue(r, depth + 1))
            }
            AnyArray(items.toArray())
        case FjKind.JsonString => AnyString(r.readString())
        case FjKind.JsonBool => AnyBool(r.readBool())
        case FjKind.JsonNull =>
            r.readNull()
            AnyNull
        case FjKind.JsonNumber =>
            let number = r.rawValue()
            if (number.iterator().any {b => b == 0x2E || b == 0x65 || b == 0x45}) {
                AnyFloat(FjReader(number).readFloat64())
            } else {
                // past Int64, an integer is kept as JavaScript keeps it: the nearest Float64
                try {
                    AnyInteger(FjReader(number).readInt64())
                } catch (_: FjException) {
                    AnyFloat(FjReader(number).readFloat64())
                }
            }
    }
}
