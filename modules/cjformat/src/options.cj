package cjformat

/** Layout of an if expression with one expression in each branch and no comments. */
public enum SimpleIf {
    | Compact
    | Multiline
}

/** Formatting policy. Width counts Unicode scalars; indentation always uses spaces. */
public struct FormatOptions {
    public let lineWidth: Int64
    public let indentWidth: Int64
    public let simpleIf: SimpleIf

    /** @throws IllegalArgumentException - if either width is not positive. */
    public init(
        lineWidth!: Int64 = 100,
        indentWidth!: Int64 = 4,
        simpleIf!: SimpleIf = SimpleIf.Multiline
    ) {
        if (lineWidth <= 0 || indentWidth <= 0) {
            throw IllegalArgumentException("line_width and indent_width must be positive integers")
        }
        this.lineWidth = lineWidth
        this.indentWidth = indentWidth
        this.simpleIf = simpleIf
    }
}
