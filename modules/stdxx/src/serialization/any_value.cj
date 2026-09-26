package stdxx.serialization

import std.collection.ArrayList
import stdx.serialization.serialization.*
import fjson.*

/**
 * Any value at all, `null` included, carried as its `DataModel`.
 *
 * `DataModel` cannot be `Serializable` itself: Cangjie forbids extending an imported type with an
 * imported interface, so a serializable field holding any value takes a type of our own.
 */
public struct AnyValue <: Serializable<AnyValue> {
    public AnyValue(public let data: DataModel) {}

    public static func deserialize(dm: DataModel): AnyValue {
        AnyValue(dm)
    }

    public func serialize(): DataModel {
        data
    }
}

/**
 * Read into its `DataModel` and written back from it, so a value round-trips as it came: an integer
 * stays one, a number with a fraction or an exponent is a `Float64`.
 */
extend AnyValue <: ToJson & FromJson<AnyValue> {
    public func toJson(w: FjWriter): Unit {
        writeDataModel(w, data)
    }

    /**
     * @throws FjException - if the value is not JSON, or nested deeper than `ANY_VALUE_DEPTH_MAX`
     */
    public static func fromJson(r: FjReader): AnyValue {
        AnyValue(readDataModel(r, 0))
    }
}

/**
 * How deep an `AnyValue` may nest: it is read recursively, and a client's `initializationOptions`
 * must not be able to run the stack out.
 */
public const ANY_VALUE_DEPTH_MAX = 512

private func readDataModel(r: FjReader, depth: Int64): DataModel {
    if (depth > ANY_VALUE_DEPTH_MAX) {
        throw FjException("nested too deep at byte ${r.position}")
    }
    match (r.peekKind()) {
        case FjKind.JsonObject =>
            let dms = DataModelStruct()
            r.beginObject()
            while (r.nextKey()) {
                let key = r.key()
                dms.add(Field(key, readDataModel(r, depth + 1)))
            }
            dms
        case FjKind.JsonArray =>
            let items = ArrayList<DataModel>()
            r.beginArray()
            while (r.nextItem()) {
                items.add(readDataModel(r, depth + 1))
            }
            DataModelSeq(items)
        case FjKind.JsonString => DataModelString(r.readString())
        case FjKind.JsonBool => DataModelBool(r.readBool())
        case FjKind.JsonNull =>
            r.readNull()
            DataModelNull()
        case FjKind.JsonNumber =>
            let number = r.rawValue()
            if (number.iterator().any {b => b == 0x2E || b == 0x65 || b == 0x45}) {
                DataModelFloat(FjReader(number).readFloat64())
            } else {
                DataModelInt(FjReader(number).readInt64())
            }
    }
}

private func writeDataModel(w: FjWriter, dm: DataModel): Unit {
    match (dm) {
        case dms: DataModelStruct =>
            w.beginObject()
            for (field in dms.getFields()) {
                w.name(field.getName())
                writeDataModel(w, field.getData())
            }
            w.endObject()
        case seq: DataModelSeq =>
            w.beginArray()
            for (item in seq.getItems()) {
                writeDataModel(w, item)
            }
            w.endArray()
        case s: DataModelString => w.string(s.getValue())
        case b: DataModelBool => w.bool(b.getValue())
        case i: DataModelInt => w.int64(i.getValue())
        case f: DataModelFloat => w.float64(f.getValue())
        case _ => w.null()
    }
}
