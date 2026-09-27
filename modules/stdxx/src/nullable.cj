package stdxx

import stdx.serialization.serialization.*
import fjson.*

public enum Nullable<T> {
    | Value(T)
    | Null

    public func isValue(): Bool {
        match (this) {
            case Value(_) => true
            case Null => false
        }
    }

    public func isNull(): Bool {
        !isValue()
    }

    /**
     * @throws NullValueException - if it holds `Null`
     */
    public func getOrThrow(): T {
        match (this) {
            case Value(v) => v
            case Null => throw NullValueException()
        }
    }
}

extend<T> Nullable<T> <: Serializable<Nullable<T>> where T <: Serializable<T> {
    public static func deserialize(dm: DataModel): Nullable<T> {
        match (dm) {
            case _: DataModelNull => Null
            case _ => Value(T.deserialize(dm))
        }
    }

    public func serialize(): DataModel {
        match (this) {
            case Value(s) => s.serialize()
            case Null => DataModelNull()
        }
    }
}

extend<T> Nullable<T> <: ToJson where T <: ToJson {
    public func toJson(w: FjWriter): Unit {
        match (this) {
            case Value(value) => value.toJson(w)
            case Null => w.null()
        }
    }
}

extend<T> Nullable<T> <: FromJson<Nullable<T>> where T <: FromJson<T> {
    public static func fromJson(r: FjReader): Nullable<T> {
        if (r.peekNull()) {
            r.readNull()
            return Null
        }
        Value(T.fromJson(r))
    }
}
