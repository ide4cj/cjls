package stdxx

import std.deriving.*
import fjson.*

@Derive[Equatable, Hashable]
public enum IntegerOrString <: ToString {
    | Integer(Int32)
    | String(String)

    public func toString(): String {
        match (this) {
            case Integer(i) => i.toString()
            case String(s) => s
        }
    }

    public func isInteger(): Bool {
        match (this) {
            case Integer(_) => true
            case String(_) => false
        }
    }

    public func isString(): Bool {
        !isInteger()
    }

    /**
     * @throws UnexpectedVariantException - if it holds a `String`
     */
    public func getIntegerOrThrow(): Int32 {
        match (this) {
            case Integer(int) => int
            case String(_) => throw UnexpectedVariantException("Integer", "String")
        }
    }

    /**
     * @throws UnexpectedVariantException - if it holds an `Integer`
     */
    public func getStringOrThrow(): String {
        match (this) {
            case String(str) => str
            case Integer(_) => throw UnexpectedVariantException("String", "Integer")
        }
    }
}

extend IntegerOrString <: ToJson & FromJson<IntegerOrString> {
    public func toJson(w: FjWriter): Unit {
        match (this) {
            case Integer(i) => w.int32(i)
            case String(s) => w.string(s)
        }
    }

    /**
     * @throws FjException - if not an integer that fits an `Int32`, nor a string
     */
    public static func fromJson(r: FjReader): IntegerOrString {
        match (r.peekKind()) {
            case FjKind.FjNumber => Integer(r.readInt32())
            case FjKind.FjString => String(r.readString())
            case _ => throw FjException("expected integer or string at byte ${r.position}")
        }
    }
}

// in an extension of its own: inside the enum body these would hide the derived `==` they call
extend IntegerOrString <: Equatable<Int32> & Equatable<String> {
    public operator func ==(other: Int32): Bool {
        this == Integer(other)
    }

    public operator func ==(other: String): Bool {
        this == String(other)
    }
}
