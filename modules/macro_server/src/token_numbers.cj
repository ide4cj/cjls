package macro_server

import std.collection.*
import std.convert.*
import std.fs.*

/**
 * cjc's token kinds as the pinned nightly's `include/cangjie/Lex/Tokens.inc` numbers them, which `TokenNumbersTest`
 * holds to the SDK the tests run on, for an SDK that ships no `Tokens.inc` (D104). cjc only adds kinds, so every SDK
 * since 1.1 numbers them the same; 1.0 had the first `KINDS_OF_1_0` and then `ILLEGAL`, which 1.1 moved to make
 * room.
 */
let KINDS: Array<String> =
    [
        "DOT",
        "COMMA",
        "LPAREN",
        "RPAREN",
        "LSQUARE",
        "RSQUARE",
        "LCURL",
        "RCURL",
        "EXP",
        "MUL",
        "MOD",
        "DIV",
        "ADD",
        "SUB",
        "INCR",
        "DECR",
        "AND",
        "OR",
        "COALESCING",
        "PIPELINE",
        "COMPOSITION",
        "NOT",
        "BITAND",
        "BITOR",
        "BITXOR",
        "BITNOT",
        "LSHIFT",
        "RSHIFT",
        "COLON",
        "SEMI",
        "ASSIGN",
        "ADD_ASSIGN",
        "SUB_ASSIGN",
        "MUL_ASSIGN",
        "EXP_ASSIGN",
        "DIV_ASSIGN",
        "MOD_ASSIGN",
        "AND_ASSIGN",
        "OR_ASSIGN",
        "BITAND_ASSIGN",
        "BITOR_ASSIGN",
        "BITXOR_ASSIGN",
        "LSHIFT_ASSIGN",
        "RSHIFT_ASSIGN",
        "ARROW",
        "BACKARROW",
        "DOUBLE_ARROW",
        "RANGEOP",
        "CLOSEDRANGEOP",
        "ELLIPSIS",
        "HASH",
        "AT",
        "QUEST",
        "LT",
        "GT",
        "LE",
        "GE",
        "IS",
        "AS",
        "NOTEQ",
        "EQUAL",
        "WILDCARD",
        "INT8",
        "INT16",
        "INT32",
        "INT64",
        "INTNATIVE",
        "UINT8",
        "UINT16",
        "UINT32",
        "UINT64",
        "UINTNATIVE",
        "FLOAT16",
        "FLOAT32",
        "FLOAT64",
        "RUNE",
        "BOOLEAN",
        "NOTHING",
        "UNIT",
        "STRUCT",
        "ENUM",
        "VARRAY",
        "THISTYPE",
        "PACKAGE",
        "IMPORT",
        "CLASS",
        "INTERFACE",
        "FUNC",
        "MACRO",
        "QUOTE",
        "DOLLAR",
        "LET",
        "VAR",
        "CONST",
        "TYPE",
        "INIT",
        "THIS",
        "SUPER",
        "IF",
        "ELSE",
        "CASE",
        "TRY",
        "CATCH",
        "FINALLY",
        "FOR",
        "DO",
        "WHILE",
        "THROW",
        "RETURN",
        "CONTINUE",
        "BREAK",
        "IN",
        "NOT_IN",
        "MATCH",
        "WHERE",
        "EXTEND",
        "WITH",
        "PROP",
        "STATIC",
        "PUBLIC",
        "PRIVATE",
        "INTERNAL",
        "PROTECTED",
        "OVERRIDE",
        "REDEF",
        "ABSTRACT",
        "SEALED",
        "OPEN",
        "FOREIGN",
        "INOUT",
        "MUT",
        "UNSAFE",
        "OPERATOR",
        "SPAWN",
        "SYNCHRONIZED",
        "UPPERBOUND",
        "MAIN",
        "IDENTIFIER",
        "PACKAGE_IDENTIFIER",
        "INTEGER_LITERAL",
        "RUNE_BYTE_LITERAL",
        "FLOAT_LITERAL",
        "COMMENT",
        "NL",
        "END",
        "SENTINEL",
        "RUNE_LITERAL",
        "STRING_LITERAL",
        "JSTRING_LITERAL",
        "MULTILINE_STRING",
        "MULTILINE_RAW_STRING",
        "BOOL_LITERAL",
        "UNIT_LITERAL",
        "DOLLAR_IDENTIFIER",
        "ANNOTATION",
        "AT_EXCL",
        "COMMON",
        "SPECIFIC",
        "PERFORM",
        "RESUME",
        "THROWING",
        "HANDLE",
        "ILLEGAL",
        "DOUBLE_COLON",
        "FEATURES"
    ]

/**
 * How many kinds 1.0 numbered before its `ILLEGAL`, as `Tokens.inc` of cangjie_compiler's tag v1.0.5 lists them.
 */
const KINDS_OF_1_0 = 156

/**
 * cjc's `TokenKind` numbers by name: as an SDK lists them in its `include/cangjie/Lex/Tokens.inc`, a kind's number
 * its line's place among the `TOKEN` and `EXPERIMENTAL_TOKEN` lines, the order cjc's enum takes them in (D95); or,
 * for an SDK that ships none, as cjls's own table numbers them for its version (D104).
 */
public class TokenNumbers {
    let numbers = HashMap<String, UInt8>()

    /**
     * Each kind's name (`DOT`) by its number, what std.ast's `TokenKind.toString` gives.
     */
    public let names: Array<String>

    /**
     * `sentAs`: kinds the SDK does not have, each sent as one it has.
     */
    init(names: Array<String>, sentAs!: Array<(String, String)> = []) {
        this.names = names
        for (i in 0..names.size) {
            numbers.add(names[i], UInt8(i))
        }
        for ((kind, other) in sentAs) {
            if (let Some(number) <- numbers.get(other)) {
                numbers.add(kind, number)
            }
        }
    }

    /**
     * The numbers the file `tokensInc` lists, as `parse` reads them; `None` if it cannot be read either.
     */
    public static func read(tokensInc: Path): ?TokenNumbers {
        let text =
            try {
                String.fromUtf8(File.readFrom(tokensInc))
            } catch (_: Exception) {
                return None
            }
        parse(text)
    }

    /**
     * The numbers `tokensInc` lists, or `None` if it lists more than a `UInt8` numbers, or lacks a kind `macroTokens`
     * sends: then nothing can be sent to this SDK's server.
     */
    public static func parse(tokensInc: String): ?TokenNumbers {
        let names = ArrayList<String>()
        for (line in tokensInc.lines()) {
            let entry = line.trimAscii()
            let args =
                if (entry.startsWith("TOKEN(")) {
                    entry["TOKEN(".size..]
                } else if (entry.startsWith("EXPERIMENTAL_TOKEN(")) {
                    entry["EXPERIMENTAL_TOKEN(".size..]
                } else {
                    continue
                }
            names.add(args[..(args.indexOf(",") ?? return None)].trimAscii())
        }
        if (names.size > Int64(UInt8.Max) + 1) {
            return None
        }
        let numbers = TokenNumbers(names.toArray())
        if (SENT_KINDS.iterator().any { name => !numbers.numbers.contains(name) }) {
            return None
        }
        numbers
    }

    /**
     * The numbers of the SDK whose `cjc --version` printed `version`, by cjls's own table: since 1.1 the table itself,
     * an SDK newer than the pinned nightly numbering what it added past it; 1.0's first kinds and its `ILLEGAL`, the
     * contextual keywords it does not have sent as the identifiers it reads them as. `None` for an older or unknown
     * version.
     */
    public static func builtin(version: String): ?TokenNumbers {
        let (major, minor) = versionOf(version) ?? return None
        if (major == 1 && minor == 0) {
            let added = KINDS[KINDS_OF_1_0..].filter { kind => kind != "ILLEGAL" }
            return TokenNumbers(
                KINDS[..KINDS_OF_1_0].concat(["ILLEGAL"]),
                sentAs: added.map { kind => (kind, "IDENTIFIER") }
            )
        }
        if (major > 1 || (major == 1 && minor >= 1)) {
            return TokenNumbers(KINDS)
        }
        None
    }

    /**
     * The number of the kind named `name` (`DOT`).
     *
     * @throws NoneValueException - if there is no such kind; `parse` saw every kind `macroTokens` sends
     */
    public func numberOf(name: String): UInt8 {
        numbers.get(name).getOrThrow()
    }
}

/**
 * The major and minor version `cjc --version` printed: `1.0` of `Cangjie Compiler: 1.0.5 (cjnative)`.
 */
func versionOf(version: String): ?(Int64, Int64) {
    let first = version.lines().next() ?? return None
    let text = first[(first.indexOf(": ").map { at => at + 2 } ?? 0)..]
    let parts = text.split(".")
    if (parts.size < 2) {
        return None
    }
    let major = Int64.tryParse(parts[0]) ?? return None
    let minor = Int64.tryParse(parts[1]) ?? return None
    (major, minor)
}
