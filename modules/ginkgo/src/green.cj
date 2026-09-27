package ginkgo

/**
 * An immutable leaf: a kind and the exact text it covers, trivia included.
 *
 * Green elements know nothing about where they are, so equal subtrees can be shared, within a tree and between
 * versions of it. Equality is structural.
 */
public class GreenToken<K> <: Equatable<GreenToken<K>> & Hashable & ToString where K <: Kind<K> {
    let structuralHash: Int64

    public GreenToken(public let kind: K, public let text: String) {
        var hasher = DefaultHasher()
        hasher.write(kind.hashCode())
        hasher.write(text)
        structuralHash = hasher.finish()
    }

    /**
     * In UTF-8 bytes.
     */
    @Frozen
    public prop textLen: Int64 {
        get() {
            text.size
        }
    }

    @Frozen
    public operator func ==(other: GreenToken<K>): Bool {
        refEq(this, other) || (structuralHash == other.structuralHash && kind == other.kind && text == other.text)
    }

    @Frozen
    public operator func !=(other: GreenToken<K>): Bool {
        !(this == other)
    }

    @Frozen
    public func hashCode(): Int64 {
        structuralHash
    }

    @Frozen
    public func toString(): String {
        text
    }
}

/**
 * An immutable inner node: a kind and its children. It covers exactly the text of its children, in order.
 *
 * Changing a tree means building new nodes along the path to the root; everything else is shared.
 */
public class GreenNode<K> <: Equatable<GreenNode<K>> & Hashable & ToString where K <: Kind<K> {
    let elements: Array<GreenElement<K>>
    let offsets: Array<Int64>
    let structuralHash: Int64

    /**
     * In UTF-8 bytes.
     */
    public let textLen: Int64

    public let kind: K

    public init(children: Array<GreenElement<K>>, kind: K) {
        this(GreenNode<K>.measure(children.clone(), kind))
    }

    private init(node: GreenNode<K>) {
        elements = node.elements
        offsets = node.offsets
        structuralHash = node.structuralHash
        textLen = node.textLen
        kind = node.kind
    }

    private init(elements: Array<GreenElement<K>>, offsets: Array<Int64>, textLen: Int64, structuralHash: Int64, kind: K) {
        this.elements = elements
        this.offsets = offsets
        this.textLen = textLen
        this.structuralHash = structuralHash
        this.kind = kind
    }

    /**
     * A node of `children`, which it keeps rather than copies. The work is here rather than in a
     * constructor: a generic class's constructor is never inlined, `@Frozen` or not, so its body
     * looks the type of every `GreenElement<K>` up at run time (C11).
     */
    @Frozen
    static func measure(children: Array<GreenElement<K>>, kind: K): GreenNode<K> {
        let offsets = Array<Int64>(children.size, repeat: 0)
        var hasher = DefaultHasher()
        hasher.write(kind.hashCode())
        var len = 0
        for (i in 0..children.size) {
            offsets[i] = len
            len += children[i].textLen
            hasher.write(children[i].hashCode())
        }
        GreenNode<K>(children, offsets, len, hasher.finish(), kind)
    }

    @Frozen
    public prop childCount: Int64 {
        get() {
            elements.size
        }
    }

    /**
     * @throws IndexOutOfBoundsException - if there is no child `index`
     */
    @Frozen
    public func child(index: Int64): GreenElement<K> {
        elements[index]
    }

    /**
     * Where child `index` starts, relative to the start of this node.
     *
     * @throws IndexOutOfBoundsException - if there is no child `index`
     */
    @Frozen
    public func childOffset(index: Int64): Int64 {
        offsets[index]
    }

    @Frozen
    public func children(): Iterator<GreenElement<K>> {
        elements.iterator()
    }

    /**
     * A copy with child `index` replaced.
     */
    @Frozen
    public func replaceChild(index: Int64, element: GreenElement<K>): GreenNode<K> {
        spliceChildren(index, index + 1, [element])
    }

    /**
     * A copy with `element` inserted before child `index`; `index` may be `childCount`.
     */
    @Frozen
    public func insertChild(index: Int64, element: GreenElement<K>): GreenNode<K> {
        spliceChildren(index, index, [element])
    }

    /**
     * A copy without child `index`.
     */
    @Frozen
    public func removeChild(index: Int64): GreenNode<K> {
        spliceChildren(index, index + 1, [])
    }

    /**
     * A copy with children `start` up to, not including, `end` replaced by `replacement`.
     */
    @Frozen
    public func spliceChildren(start: Int64, end: Int64, replacement: Array<GreenElement<K>>): GreenNode<K> {
        if (start < 0 || end < start || end > elements.size) {
            throw IndexOutOfBoundsException("Invalid child range ${start}..${end} of ${elements.size} children")
        }
        GreenNode<K>.measure(elements[..start].concat(replacement).concat(elements[end..]), kind)
    }

    @Frozen
    func writeTo(sb: StringBuilder): Unit {
        for (element in elements) {
            match (element) {
                case GreenElement.Node(node) => node.writeTo(sb)
                case GreenElement.Token(token) => sb.append(token.text)
            }
        }
    }

    @Frozen
    public operator func ==(other: GreenNode<K>): Bool {
        if (refEq(this, other)) {
            return true
        }
        if (structuralHash != other.structuralHash || kind != other.kind || elements.size != other.elements.size) {
            return false
        }
        for (i in 0..elements.size) {
            if (elements[i] != other.elements[i]) {
                return false
            }
        }
        true
    }

    @Frozen
    public operator func !=(other: GreenNode<K>): Bool {
        !(this == other)
    }

    @Frozen
    public func hashCode(): Int64 {
        structuralHash
    }

    /**
     * The text this node covers.
     */
    @Frozen
    public func toString(): String {
        let sb = StringBuilder()
        writeTo(sb)
        sb.toString()
    }
}

public enum GreenElement<K> <: Equatable<GreenElement<K>> & Hashable & ToString where K <: Kind<K> {
    | Node(GreenNode<K>)
    | Token(GreenToken<K>)

    @Frozen
    public prop kind: K {
        get() {
            match (this) {
                case Node(node) => node.kind
                case Token(token) => token.kind
            }
        }
    }

    @Frozen
    public prop textLen: Int64 {
        get() {
            match (this) {
                case Node(node) => node.textLen
                case Token(token) => token.textLen
            }
        }
    }

    @Frozen
    public func asNode(): ?GreenNode<K> {
        match (this) {
            case Node(node) => node
            case Token(_) => None
        }
    }

    @Frozen
    public func asToken(): ?GreenToken<K> {
        match (this) {
            case Node(_) => None
            case Token(token) => token
        }
    }

    @Frozen
    public operator func ==(other: GreenElement<K>): Bool {
        match ((this, other)) {
            case (Node(a), Node(b)) => a == b
            case (Token(a), Token(b)) => a == b
            case _ => false
        }
    }

    @Frozen
    public operator func !=(other: GreenElement<K>): Bool {
        !(this == other)
    }

    @Frozen
    public func hashCode(): Int64 {
        match (this) {
            case Node(node) => node.hashCode()
            case Token(token) => token.hashCode()
        }
    }

    @Frozen
    public func toString(): String {
        match (this) {
            case Node(node) => node.toString()
            case Token(token) => token.text
        }
    }
}
