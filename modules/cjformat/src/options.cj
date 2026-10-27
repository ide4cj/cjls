package cjformat

import ftoml.*
import stdxx.deriving.*

/**
 * Layout of an if expression with one expression in each branch and no comments.
 */
@DeriveExt[FromToml]
public enum SimpleIf {
    | @Serde[rename: "compact"]
    Compact
    | @Serde[rename: "multiline"]
    Multiline
}

/**
 * Formatting policy. Width counts Unicode scalars; indentation always uses spaces.
 */
@DeriveExt[FromToml]
@Serde[denyUnknownFields]
public struct FormatOptions {
    /**
     * Creates validated formatter policy.
     *
     * @throws IllegalArgumentException - if either width is not positive
     */
    public FormatOptions(
        @Serde[rename: "line_width", default]
        public let lineWidth!: Int64 = 100,
        @Serde[rename: "indent_width", default]
        public let indentWidth!: Int64 = 4,
        @Serde[rename: "simple_if", default]
        public let simpleIf!: SimpleIf = SimpleIf.Multiline
    ) {
        if (lineWidth <= 0 || indentWidth <= 0) {
            throw IllegalArgumentException("line_width and indent_width must be positive integers")
        }
    }
}
