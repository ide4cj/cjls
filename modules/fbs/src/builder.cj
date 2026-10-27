package fbs

import std.collection.*

// Little-endian writes into a struct's bytes (`FbBuilder.addStruct`), a signed value as the bits of the unsigned one.

public func writeBool(buf: Array<Byte>, pos: Int64, value: Bool): Unit {
    buf[pos] = if (value) { 1 } else { 0 }
}

public func writeUInt8(buf: Array<Byte>, pos: Int64, value: UInt8): Unit {
    buf[pos] = value
}

@OverflowWrapping
public func writeInt8(buf: Array<Byte>, pos: Int64, value: Int8): Unit {
    buf[pos] = UInt8(value)
}

public func writeUInt16(buf: Array<Byte>, pos: Int64, value: UInt16): Unit {
    buf[pos] = UInt8(value & 0xFF)
    buf[pos + 1] = UInt8(value >> 8)
}

@OverflowWrapping
public func writeInt16(buf: Array<Byte>, pos: Int64, value: Int16): Unit {
    writeUInt16(buf, pos, UInt16(value))
}

public func writeUInt32(buf: Array<Byte>, pos: Int64, value: UInt32): Unit {
    for (i in 0..4) {
        buf[pos + i] = UInt8((value >> UInt32(8 * i)) & 0xFF)
    }
}

@OverflowWrapping
public func writeInt32(buf: Array<Byte>, pos: Int64, value: Int32): Unit {
    writeUInt32(buf, pos, UInt32(value))
}

public func writeUInt64(buf: Array<Byte>, pos: Int64, value: UInt64): Unit {
    for (i in 0..8) {
        buf[pos + i] = UInt8((value >> UInt64(8 * i)) & 0xFF)
    }
}

@OverflowWrapping
public func writeInt64(buf: Array<Byte>, pos: Int64, value: Int64): Unit {
    writeUInt64(buf, pos, UInt64(value))
}

public func writeFloat32(buf: Array<Byte>, pos: Int64, value: Float32): Unit {
    writeUInt32(buf, pos, value.toBits())
}

public func writeFloat64(buf: Array<Byte>, pos: Int64, value: Float64): Unit {
    writeUInt64(buf, pos, value.toBits())
}

/**
 * Where an object built is: its distance from the end of the buffer, which stays what it is as the buffer
 * grows at the front.
 */
public struct FbOffset {
    public FbOffset(public let value: Int64) {}
}

/**
 * Builds a flatbuffer back to front, as flatbuffers' own builders do: an object's children before the
 * object, a table's fields between `startTable` and `endTable`, a vector's elements last to first between
 * `startVector` and `endVector`, the root last (`finish`). Every value is aligned to its size from the
 * buffer's start, as flatbuffers' verifier checks; a vtable is written for each table, none shared.
 */
public class FbBuilder {
    private var buf: Array<Byte>
    private var used = 0
    private var minAlign = 1
    private var tableStart = -1
    // `(id, where)` of each field of the table being built, where as `used` after it was written
    private let fields = ArrayList<(Int64, Int64)>()

    public init(capacity!: Int64 = 256) {
        buf = Array<Byte>(max(capacity, 16), repeat: 0)
    }

    /**
     * Room for `n` more bytes at the front, what is written so far moved to the end of a bigger buffer.
     */
    private func reserve(n: Int64): Unit {
        if (buf.size - used >= n) {
            return
        }
        var size = buf.size * 2
        while (size - used < n) {
            size *= 2
        }
        let bigger = Array<Byte>(size, repeat: 0)
        buf.copyTo(bigger, buf.size - used, size - used, used)
        buf = bigger
    }

    /**
     * Takes `n` bytes at the front, zeroed: where they start. It may move `buf`, so a write takes first and
     * names `buf` after (`writeUInt32(buf, take(4), v)` would write into the buffer it replaced).
     */
    private func take(n: Int64): Int64 {
        reserve(n)
        used += n
        let at = buf.size - used
        for (i in at..at + n) {
            buf[i] = 0
        }
        at
    }

    /**
     * Pads so that a value of `size` bytes written after `additional` more is aligned to `size`.
     */
    private func prep(size: Int64, additional: Int64): Unit {
        minAlign = max(minAlign, size)
        let pad = (size - (used + additional) % size) % size
        take(pad)
        ()
    }

    public func addBool(value: Bool): Unit {
        prep(1, 0)
        let at = take(1)
        writeBool(buf, at, value)
    }

    public func addUInt8(value: UInt8): Unit {
        prep(1, 0)
        let at = take(1)
        writeUInt8(buf, at, value)
    }

    public func addInt8(value: Int8): Unit {
        prep(1, 0)
        let at = take(1)
        writeInt8(buf, at, value)
    }

    public func addUInt16(value: UInt16): Unit {
        prep(2, 0)
        let at = take(2)
        writeUInt16(buf, at, value)
    }

    public func addInt16(value: Int16): Unit {
        prep(2, 0)
        let at = take(2)
        writeInt16(buf, at, value)
    }

    public func addUInt32(value: UInt32): Unit {
        prep(4, 0)
        let at = take(4)
        writeUInt32(buf, at, value)
    }

    public func addInt32(value: Int32): Unit {
        prep(4, 0)
        let at = take(4)
        writeInt32(buf, at, value)
    }

    public func addUInt64(value: UInt64): Unit {
        prep(8, 0)
        let at = take(8)
        writeUInt64(buf, at, value)
    }

    public func addInt64(value: Int64): Unit {
        prep(8, 0)
        let at = take(8)
        writeInt64(buf, at, value)
    }

    public func addFloat32(value: Float32): Unit {
        prep(4, 0)
        let at = take(4)
        writeFloat32(buf, at, value)
    }

    public func addFloat64(value: Float64): Unit {
        prep(8, 0)
        let at = take(8)
        writeFloat64(buf, at, value)
    }

    /**
     * An offset to `target`, built before: an unsigned offset forward from where it is stored.
     */
    public func addOffset(target: FbOffset): Unit {
        prep(4, 0)
        let at = take(4)
        writeUInt32(buf, at, UInt32(used - target.value))
    }

    /**
     * A struct, its `bytes` laid out as the schema says, aligned to `alignment`: in a table between `slot`s,
     * in a vector, or alone as a union's value (`createStruct`).
     */
    public func addStruct(bytes: Array<Byte>, alignment: Int64): Unit {
        prep(alignment, bytes.size)
        let at = take(bytes.size)
        bytes.copyTo(buf, 0, at, bytes.size)
    }

    /**
     * A struct alone, a union's value: where it is.
     */
    public func createStruct(bytes: Array<Byte>, alignment: Int64): FbOffset {
        addStruct(bytes, alignment)
        FbOffset(used)
    }

    /**
     * A string: its length, its UTF-8 bytes and a 0.
     */
    public func createString(value: String): FbOffset {
        let bytes = value.toArray()
        prep(4, bytes.size + 1)
        take(1)
        let text = take(bytes.size)
        bytes.copyTo(buf, 0, text, bytes.size)
        let length = take(4)
        writeUInt32(buf, length, UInt32(bytes.size))
        FbOffset(used)
    }

    /**
     * Starts a vector of `count` elements of `size` bytes, aligned to `alignment`: they are added last to first.
     */
    public func startVector(size: Int64, count: Int64, alignment: Int64): Unit {
        prep(4, size * count)
        prep(alignment, size * count)
    }

    /**
     * Ends the vector of `count` elements started last: where it is.
     */
    public func endVector(count: Int64): FbOffset {
        prep(4, 0)
        let at = take(4)
        writeUInt32(buf, at, UInt32(count))
        FbOffset(used)
    }

    /**
     * A vector of offsets to the objects `targets`, built before.
     */
    public func createVector(targets: Array<FbOffset>): FbOffset {
        startVector(4, targets.size, 4)
        for (i in targets.size - 1..=0: -1) {
            addOffset(targets[i])
        }
        endVector(targets.size)
    }

    /**
     * A vector of strings.
     */
    public func createStringVector(values: Array<String>): FbOffset {
        createVector(values.map { s => createString(s) })
    }

    /**
     * Starts a table: its fields are added next, each followed by its `slot`.
     *
     * @throws IllegalStateException - if a table is being built: a child is built before its parent
     */
    public func startTable(): Unit {
        if (tableStart >= 0) {
            throw IllegalStateException("a table is started inside another: build the child first")
        }
        fields.clear()
        tableStart = used
    }

    /**
     * Marks the value added last as field `id` of the table being built.
     */
    public func slot(id: Int64): Unit {
        fields.add((id, used))
    }

    /**
     * Ends the table being built, its vtable written before it: where it is.
     */
    public func endTable(): FbOffset {
        if (tableStart < 0) {
            throw IllegalStateException("a table is ended that was not started")
        }
        addInt32(0)
        let object = used
        var count = 0
        for ((id, _) in fields) {
            count = max(count, id + 1)
        }
        let offsets = Array<UInt16>(count, repeat: 0)
        for ((id, at) in fields) {
            offsets[id] = UInt16(object - at)
        }
        for (i in count - 1..=0: -1) {
            addUInt16(offsets[i])
        }
        addUInt16(UInt16(object - tableStart))
        addUInt16(UInt16(4 + 2 * count))
        writeInt32(buf, buf.size - object, Int32(used - object))
        tableStart = -1
        FbOffset(object)
    }

    /**
     * The buffer of root `root`, with `fileIdentifier` (4 bytes) after its offset if there is one.
     */
    public func finish(root: FbOffset, fileIdentifier!: ?String = None): Array<Byte> {
        let identifier = fileIdentifier?.toArray() ?? Array<Byte>()
        if (!identifier.isEmpty() && identifier.size != 4) {
            throw IllegalArgumentException("a file identifier is 4 bytes, not ${identifier.size}")
        }
        prep(max(minAlign, 4), 4 + identifier.size)
        if (!identifier.isEmpty()) {
            let at = take(4)
            identifier.copyTo(buf, 0, at, 4)
        }
        addOffset(root)
        buf[buf.size - used..].clone()
    }
}
