package macro_server

import std.collection.*
import fbs.FbVector
import cjsyntax.SyntaxKind
import ginkgo.TextRange

/**
 * A token `printMacroTokens` printed: where it is in the text, and where the server said it came from.
 */
public struct PrintedToken {
    public PrintedToken(
        /** The token's bytes in the text, a literal's quotes and `#`s included, an `NL`'s line break. */
        public let range: TextRange,
        /** Where the token begins, as the server gave it. */
        public let begin: ?PositionData,
        /** Where the token ends, as the server gave it. */
        public let end: ?PositionData
    ) {}
}

/**
 * Cangjie source text printed from a macro's tokens, and where each token went in it, in the tokens' order.
 */
public class PrintedTokens {
    public PrintedTokens(public let text: String, public let tokens: Array<PrintedToken>) {}
}

/**
 * The source text of the tokens `LSPMacroServer` answers (`MacroResult.tks`), which `macroTokens` cuts back into
 * the same kinds and values: the reverse of `macroTokens`.
 */
public func printMacroTokens(tokens: FbVector<Token>, numbers: TokenNumbers): PrintedTokens {
    let data = ArrayList<TokenData>(tokens.size)
    for (t in tokens) {
        data.add(
            TokenData(kind: t.kind, value: t.value, begin: t.begin.map(positionData), end: t.end.map(positionData),
                delimiterNum: t.delimiterNum))
    }
    printMacroTokens(data.toArray(), numbers)
}

/**
 * The source text of `tokens`, which `macroTokens` cuts back into the same kinds and values.
 *
 * A token is printed as its value, kinds known by their names in `numbers`, never by a number of ours:
 *
 * - a string as its value between quotes: `"…"`, or `'…'` when that is what lexes back to the value; a
 *   `MULTILINE_STRING` between `"""` (or `'''`) and the line break `macroTokens` drops; a `MULTILINE_RAW_STRING`
 *   between `delimiterNum` `#`s and quotes; a `JSTRING_LITERAL` as `J"…"`; a `RUNE_LITERAL` as `r'…'` (or `r"…"`);
 *   an interpolation is part of its string's value, as written. A value no quotes take back (a single-line string
 *   holding a line break, which a macro may build) is printed escaped: it parses, though to another value;
 * - a `RUNE_BYTE_LITERAL` as its value, which is all of `b'…'`;
 * - an `NL` as a line break;
 * - an `IDENTIFIER` spelled like a keyword between backquotes, as a macro may build one;
 * - two tokens are a space apart, but where none is needed: after `(` and `[`, before `)`, `]`, `,`, `;`, `(`
 *   and `[`, around a `.` between names, after `@`, before a `:` after a name or a bracket, and around a
 *   generic's `<` and `>` next to a type's name. A space is kept where the two would glue into another token
 *   (`> >`, `. .`, `$ x`, `1 .`, `< :`) or come apart (`!in` is one token before a space alone).
 */
public func printMacroTokens(tokens: Array<TokenData>, numbers: TokenNumbers): PrintedTokens {
    MacroTextPrinter(numbers).run(tokens)
}

func positionData(p: Position): PositionData {
    PositionData(fileId: p.fileId, line: p.line, column: p.column)
}

/** Kinds no space needs to follow. */
let NO_SPACE_AFTER: HashSet<String> = HashSet<String>(["LPAREN", "LSQUARE", "NL"])

/** Kinds no space needs to precede. */
let NO_SPACE_BEFORE: HashSet<String> = HashSet<String>(["RPAREN", "RSQUARE", "COMMA", "SEMI", "LPAREN", "LSQUARE", "NL"])

/** Kinds a `.` right after which stays a `.` of its own: neither a number nor a `.` nor a `?`. */
let NAME_LIKE: HashSet<String> = HashSet<String>(
    ["IDENTIFIER", "DOLLAR_IDENTIFIER", "RPAREN", "RSQUARE", "THIS", "SUPER", "THISTYPE"])

/** Kinds a `:` right after which stays a `:` of its own: neither `<` nor `:`. */
let BEFORE_COLON: HashSet<String> = HashSet<String>(["IDENTIFIER", "WILDCARD", "RPAREN", "RSQUARE"])

/** Kinds that name a type, which a generic's `<` and `>` hold without a space. */
let TYPE_NAMES: HashSet<String> = HashSet<String>(
    ["IDENTIFIER", "INT8", "INT16", "INT32", "INT64", "INTNATIVE", "UINT8", "UINT16", "UINT32", "UINT64", "UINTNATIVE",
        "FLOAT16", "FLOAT32", "FLOAT64", "RUNE", "BOOLEAN", "NOTHING", "UNIT", "THISTYPE", "VARRAY"])

class MacroTextPrinter {
    let out = StringBuilder()
    var size = 0
    let printed = ArrayList<PrintedToken>()

    MacroTextPrinter(let numbers: TokenNumbers) {}

    func run(tokens: Array<TokenData>): PrintedTokens {
        var previous = ""
        for (t in tokens) {
            let name = nameOf(t.kind)
            if (!previous.isEmpty() && spaced(previous, name)) {
                append(" ")
            }
            let start = size
            append(textOf(name, t))
            printed.add(PrintedToken(TextRange(start, size), t.begin, t.end))
            previous = name
        }
        if (previous == "NOT_IN") {
            // `!in` is one token before a space alone, the end of the text not
            append(" ")
        }
        PrintedTokens(out.toString(), printed.toArray())
    }

    func append(piece: String): Unit {
        out.append(piece)
        size += piece.size
    }

    /** The name of kind `kind`, `ILLEGAL` for a number `numbers` has no name for. */
    func nameOf(kind: UInt8): String {
        let n = Int64(kind)
        if (n < numbers.names.size) {
            numbers.names[n]
        } else {
            "ILLEGAL"
        }
    }

    /** Whether a token of kind `next` right after one of kind `previous` needs a space between. */
    func spaced(previous: String, next: String): Bool {
        if (previous == "NOT_IN") {
            return next != "NL"
        }
        if (NO_SPACE_AFTER.contains(previous) || NO_SPACE_BEFORE.contains(next)) {
            return false
        }
        match ((previous, next)) {
            case (_, "DOT") => !NAME_LIKE.contains(previous)
            case ("DOT", _) => next != "IDENTIFIER"
            case ("AT", _) => next != "IDENTIFIER"
            case (_, "COLON") => !BEFORE_COLON.contains(previous)
            case (_, "LT") | (_, "GT") => !TYPE_NAMES.contains(previous)
            case ("LT", _) => !TYPE_NAMES.contains(next)
            case _ => true
        }
    }

    /** The text of token `t` of kind `name`. */
    func textOf(name: String, t: TokenData): String {
        let value = t.value ?? ""
        match (name) {
            case "NL" => if (value == "\r\n") {
                value
            } else {
                "\n"
            }
            case "STRING_LITERAL" => quoted(name, t, ["\"${value}\"", "'${value}'"]) ?? "\"${escaped(value)}\""
            case "MULTILINE_STRING" =>
                let candidates = ["\"\"\"\n${value}\"\"\"", "'''\n${value}'''"]
                quoted(name, t, candidates) ?? candidates[0]
            case "JSTRING_LITERAL" => quoted(name, t, ["J\"${value}\""]) ?? "J\"${escaped(value)}\""
            case "RUNE_LITERAL" => quoted(name, t, ["r'${value}'", "r\"${value}\""]) ?? "r'${value}'"
            case "MULTILINE_RAW_STRING" =>
                let hashes = "#" * Int64(max(t.delimiterNum, 1))
                let candidates = ["${hashes}\"${value}\"${hashes}", "${hashes}'${value}'${hashes}"]
                quoted(name, t, candidates) ?? candidates[0]
            case "IDENTIFIER" where value != "_" && SyntaxKind.keyword(value).isSome() => "`${value}`"
            case _ => value
        }
    }

    /**
     * The first of `candidates` that `macroTokens` cuts into `t` alone, of kind `name`.
     */
    func quoted(name: String, t: TokenData, candidates: Array<String>): ?String {
        for (candidate in candidates) {
            let back = macroTokens(candidate, numbers, PositionData(fileId: 0, line: 1, column: 1))
            if (back.size == 1 && back[0].kind == numbers.numberOf(name) && back[0].value == t.value &&
                (name != "MULTILINE_RAW_STRING" || back[0].delimiterNum == t.delimiterNum)) {
                return candidate
            }
        }
        None
    }
}

/**
 * `value` with its line breaks and its unescaped `"`s escaped, so that it fits between `"`s.
 */
func escaped(value: String): String {
    let out = StringBuilder()
    var escaping = false
    for (r in value.runes()) {
        match (r) {
            case r'\n' => out.append("\\n")
            case r'\r' => out.append("\\r")
            case r'"' where !escaping => out.append("\\\"")
            case _ => out.append(r)
        }
        escaping = r == r'\\' && !escaping
    }
    out.toString()
}
