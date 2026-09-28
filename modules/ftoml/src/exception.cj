package ftoml

/**
 * What is wrong with a TOML document, or with what was read from it, and where: `offset` is the
 * byte it was found at, `line` and `column` count from 1, the column in characters. An editor
 * shows it on the file.
 */
public class FtException <: Exception {
    /** What is wrong, without where. */
    public let reason: String
    public let offset: Int64
    /** 0 until the document's text has placed it. */
    public let line: Int64
    public let column: Int64

    public init(reason: String, offset: Int64) {
        super("${reason} at byte ${offset}")
        this.reason = reason
        this.offset = offset
        this.line = 0
        this.column = 0
    }

    public init(reason: String, offset: Int64, line: Int64, column: Int64) {
        super("${reason} at line ${line}, column ${column}")
        this.reason = reason
        this.offset = offset
        this.line = line
        this.column = column
    }

    /** The same error, placed by its line and column in `bytes`, the text it was found in. */
    public func locatedIn(bytes: Array<Byte>): FtException {
        if (line > 0) {
            return this
        }
        let at = min(max(offset, 0), bytes.size)
        var line = 1
        var column = 1
        for (i in 0..at) {
            let b = bytes[i]
            if (b == 0x0A) {
                line++
                column = 1
            } else if ((b & 0xC0) != 0x80) {
                // a character starts at every byte that does not continue one
                column++
            }
        }
        FtException(reason, offset, line, column)
    }
}
