package ginkgo

import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * A half-open range `[start, end)` of UTF-8 byte offsets into the text a tree was built from.
 */
@DerivePython
@PyDoc["A half-open range `[start, end)` of UTF-8 byte offsets into the text a tree was built from."]
public struct TextRange <: Equatable<TextRange> & Hashable & ToString {
    /**
     * @throws IllegalArgumentException - if `start` is negative or past `end`
     */
    public TextRange(public let start: Int64, public let end: Int64) {
        if (start < 0 || end < start) {
            throw IllegalArgumentException("Invalid text range ${start}..${end}")
        }
    }

    @Frozen
    @PyDoc["Create [offset, offset + len) in UTF-8 bytes."]
    public static func at(offset: Int64, len: Int64): TextRange {
        TextRange(offset, offset + len)
    }

    @Frozen
    @PyDoc["Create an empty range at offset."]
    public static func empty(offset: Int64): TextRange {
        TextRange(offset, offset)
    }

    @Frozen
    @PyDoc["The number of UTF-8 bytes in this half-open range."]
    public prop len: Int64 {
        get() {
            end - start
        }
    }

    @Frozen
    @PyDoc["Whether start equals end."]
    public func isEmpty(): Bool {
        start == end
    }

    /**
     * Whether `offset` is inside, `end` excluded.
     */
    @Frozen
    @PyDoc["Whether `offset` is inside, `end` excluded."]
    public func contains(offset: Int64): Bool {
        start <= offset && offset < end
    }

    /**
     * Whether `offset` is inside, `end` included.
     */
    @Frozen
    @PyDoc["Whether `offset` is inside, `end` included."]
    public func containsInclusive(offset: Int64): Bool {
        start <= offset && offset <= end
    }

    @Frozen
    @PyDoc["Whether this range contains both boundaries of other."]
    public func containsRange(other: TextRange): Bool {
        start <= other.start && other.end <= end
    }

    /**
     * The common part: empty when the two only touch, `None` when they are apart.
     */
    @Frozen
    @PyDoc["The common part: empty when the two only touch, `None` when they are apart."]
    public func intersect(other: TextRange): ?TextRange {
        let s = max(start, other.start)
        let e = min(end, other.end)
        if (s <= e) { TextRange(s, e) } else { None }
    }

    /**
     * The smallest range containing both.
     */
    @Frozen
    @PyDoc["The smallest range containing both."]
    public func cover(other: TextRange): TextRange {
        TextRange(min(start, other.start), max(end, other.end))
    }

    @Frozen
    @PyDoc["Translate both boundaries by the signed byte offset by."]
    public func shift(by: Int64): TextRange {
        TextRange(start + by, end + by)
    }

    @Frozen
    public operator func ==(other: TextRange): Bool {
        start == other.start && end == other.end
    }

    @Frozen
    public operator func !=(other: TextRange): Bool {
        !(this == other)
    }

    @Frozen
    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(start)
        hasher.write(end)
        hasher.finish()
    }

    @Frozen
    public func toString(): String {
        "${start}..${end}"
    }
}
