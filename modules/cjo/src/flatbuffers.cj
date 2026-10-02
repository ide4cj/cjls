package cjo

/**
 * A file that is a `.cjo` by its header, broken inside: an offset out of the file, a vector longer than it,
 * a value a closed enum does not have, a union with no value. Thrown when a view reads it, not when the file
 * is opened: nothing is checked before it is read. A file that is not opened is a `NotCjoException` or a
 * `CjoVersionException`.
 */
public open class CjoException <: Exception {
    public init(message: String) {
        super(message)
    }

    protected open override func getClassName(): String {
        "CjoException"
    }
}

/**
 * What a view throws on a file it finds broken.
 */
func broken(message: String): CjoException {
    CjoException(message)
}

// Flatbuffers are little-endian, a signed value the bits of the unsigned one (`@OverflowWrapping` converts
// without a check); an index out of `buf` throws, which is what a broken file does.

@Frozen
func readBool(buf: Array<Byte>, pos: Int64): Bool {
    buf[pos] != 0
}

@Frozen
func readUInt8(buf: Array<Byte>, pos: Int64): UInt8 {
    buf[pos]
}

@Frozen
@OverflowWrapping
func readInt8(buf: Array<Byte>, pos: Int64): Int8 {
    Int8(UInt8(buf[pos]))
}

@Frozen
func readUInt16(buf: Array<Byte>, pos: Int64): UInt16 {
    UInt16(buf[pos]) | (UInt16(buf[pos + 1]) << 8)
}

@Frozen
@OverflowWrapping
func readInt16(buf: Array<Byte>, pos: Int64): Int16 {
    Int16(readUInt16(buf, pos))
}

@Frozen
func readUInt32(buf: Array<Byte>, pos: Int64): UInt32 {
    UInt32(buf[pos]) | (UInt32(buf[pos + 1]) << 8) | (UInt32(buf[pos + 2]) << 16) | (UInt32(buf[pos + 3]) << 24)
}

@Frozen
@OverflowWrapping
func readInt32(buf: Array<Byte>, pos: Int64): Int32 {
    Int32(readUInt32(buf, pos))
}

@Frozen
func readUInt64(buf: Array<Byte>, pos: Int64): UInt64 {
    UInt64(readUInt32(buf, pos)) | (UInt64(readUInt32(buf, pos + 4)) << 32)
}

@Frozen
@OverflowWrapping
func readInt64(buf: Array<Byte>, pos: Int64): Int64 {
    Int64(readUInt64(buf, pos))
}

@Frozen
func readFloat32(buf: Array<Byte>, pos: Int64): Float32 {
    Float32.fromBits(readUInt32(buf, pos))
}

@Frozen
func readFloat64(buf: Array<Byte>, pos: Int64): Float64 {
    Float64.fromBits(readUInt64(buf, pos))
}

/**
 * Where the offset at `pos` points: an unsigned offset forward from where it is stored.
 */
@Frozen
func follow(buf: Array<Byte>, pos: Int64): Int64 {
    pos + Int64(readUInt32(buf, pos))
}

/**
 * The string whose offset is stored at `pos`: a length, then its UTF-8 bytes.
 */
func readString(buf: Array<Byte>, pos: Int64): String {
    let at = follow(buf, pos)
    let size = Int64(readUInt32(buf, at))
    if (size > buf.size - at - 4) {
        throw CjoException("a string of ${size} bytes at ${at} runs past the end of the file")
    }
    String.fromUtf8(buf[at + 4..at + 4 + size])
}

/**
 * A table: a signed offset back to its vtable, then its fields. The vtable holds its own size, the table's,
 * then the offset of each field from the table, 0 for a field not stored, whose value is the default.
 */
struct FbTable {
    let vtable: Int64
    let vtableSize: Int64

    FbTable(let buf: Array<Byte>, let pos: Int64) {
        vtable = pos - Int64(readInt32(buf, pos))
        vtableSize = Int64(readUInt16(buf, vtable))
    }

    /**
     * The table whose offset is stored at `pos`.
     */
    static func at(buf: Array<Byte>, pos: Int64): FbTable {
        FbTable(buf, follow(buf, pos))
    }

    /**
     * Where field `id` is stored, 0 if it is not. A union takes two ids: its type, then its value.
     */
    @Frozen
    func offset(id: Int64): Int64 {
        let slot = 4 + 2 * id
        if (slot + 2 > vtableSize) {
            0
        } else {
            Int64(readUInt16(buf, vtable + slot))
        }
    }

    /**
     * The scalar of field `id`, read by `read` where it is stored, or `default`.
     */
    @Frozen
    func scalar<T>(id: Int64, default: T, read: (Array<Byte>, Int64) -> T): T {
        let o = offset(id)
        if (o == 0) { default } else { read(buf, pos + o) }
    }

    func string(id: Int64): ?String {
        let o = offset(id)
        if (o == 0) { Option<String>.None } else { readString(buf, pos + o) }
    }

    func table(id: Int64): ?FbTable {
        let o = offset(id)
        if (o == 0) { Option<FbTable>.None } else { FbTable.at(buf, pos + o) }
    }

    /**
     * Where the struct of field `id` starts: a struct is stored in the table itself.
     */
    func structAt(id: Int64): ?Int64 {
        let o = offset(id)
        if (o == 0) { Option<Int64>.None } else { pos + o }
    }

    /**
     * The vector of field `id`, of elements `stride` bytes apart that `read` reads where each starts; an absent
     * vector is an empty one.
     */
    func vector<T>(id: Int64, stride: Int64, read: (Array<Byte>, Int64) -> T): FbVector<T> {
        let o = offset(id)
        if (o == 0) {
            FbVector<T>(buf, 0, 0, stride, read)
        } else {
            FbVector<T>.at(buf, pos + o, stride, read)
        }
    }

    /**
     * The value of a required field `name` of table `table`: one that is absent makes the file broken.
     */
    static func required<T>(value: ?T, table: String, name: String): T {
        match (value) {
            case Some(v) => v
            case _ => throw CjoException("${table} has no ${name}, which it requires")
        }
    }
}

/**
 * A vector of a flatbuffer, read an element at a time when it is asked for: nothing is copied out of the
 * file.
 */
public struct FbVector<T> <: Collection<T> {
    FbVector(
        let buf: Array<Byte>,
        let start: Int64,
        let count: Int64,
        let stride: Int64,
        let read: (Array<Byte>, Int64) -> T
    ) {}

    /**
     * The vector whose offset is stored at `pos`: a length, then the elements.
     *
     * @throws CjoException - if its elements would run past the end of the file
     */
    static func at(buf: Array<Byte>, pos: Int64, stride: Int64, read: (Array<Byte>, Int64) -> T): FbVector<T> {
        let at = follow(buf, pos)
        let count = Int64(readUInt32(buf, at))
        if (count > (buf.size - at - 4) / stride) {
            throw CjoException("a vector of ${count} elements at ${at} runs past the end of the file")
        }
        FbVector<T>(buf, at + 4, count, stride, read)
    }

    public prop size: Int64 {
        get() {
            count
        }
    }

    public func isEmpty(): Bool {
        count == 0
    }

    /**
     * @throws IndexOutOfBoundsException - if `index` is not in `0..size`
     */
    @Frozen
    public operator func [](index: Int64): T {
        if (index < 0 || index >= count) {
            throw IndexOutOfBoundsException("index ${index} of a vector of ${count}")
        }
        read(buf, start + index * stride)
    }

    public func iterator(): Iterator<T> {
        FbVectorIterator<T>(this)
    }

    public func toArray(): Array<T> {
        Array<T>(count) {i => this[i]}
    }
}

class FbVectorIterator<T> <: Iterator<T> {
    var index = 0

    FbVectorIterator(let vector: FbVector<T>) {}

    public func next(): ?T {
        if (index >= vector.size) {
            return Option<T>.None
        }
        index++
        vector[index - 1]
    }
}
