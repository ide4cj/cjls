package macro_server

import std.collection.*
import cjsyntax.{tokenize, SyntaxKind}
import ginkgo.parsing.Lexed

/**
 * cjc's name of each kind cjsyntax lexes one token of, one for one. The others are `macroTokens`'s to put together
 * or take apart: a string's pieces, the trivia, `>`, `?` and `!`, which cjc's lexer glues to what follows.
 */
let SIMPLE_KINDS: Array<(SyntaxKind, String)> =
    [
        (Dot, "DOT"),
        (Comma, "COMMA"),
        (LParen, "LPAREN"),
        (RParen, "RPAREN"),
        (LBracket, "LSQUARE"),
        (RBracket, "RSQUARE"),
        (LBrace, "LCURL"),
        (RBrace, "RCURL"),
        (StarStar, "EXP"),
        (Star, "MUL"),
        (Percent, "MOD"),
        (Slash, "DIV"),
        (Plus, "ADD"),
        (Minus, "SUB"),
        (PlusPlus, "INCR"),
        (MinusMinus, "DECR"),
        (AmpAmp, "AND"),
        (PipePipe, "OR"),
        (PipeGt, "PIPELINE"),
        (TildeGt, "COMPOSITION"),
        (Amp, "BITAND"),
        (Pipe, "BITOR"),
        (Caret, "BITXOR"),
        (Tilde, "BITNOT"),
        (LtLt, "LSHIFT"),
        (Colon, "COLON"),
        (ColonColon, "DOUBLE_COLON"),
        (Semicolon, "SEMI"),
        (Eq, "ASSIGN"),
        (PlusEq, "ADD_ASSIGN"),
        (MinusEq, "SUB_ASSIGN"),
        (StarEq, "MUL_ASSIGN"),
        (StarStarEq, "EXP_ASSIGN"),
        (SlashEq, "DIV_ASSIGN"),
        (PercentEq, "MOD_ASSIGN"),
        (AmpAmpEq, "AND_ASSIGN"),
        (PipePipeEq, "OR_ASSIGN"),
        (AmpEq, "BITAND_ASSIGN"),
        (PipeEq, "BITOR_ASSIGN"),
        (CaretEq, "BITXOR_ASSIGN"),
        (LtLtEq, "LSHIFT_ASSIGN"),
        (Arrow, "ARROW"),
        (LArrow, "BACKARROW"),
        (FatArrow, "DOUBLE_ARROW"),
        (DotDot, "RANGEOP"),
        (DotDotEq, "CLOSEDRANGEOP"),
        (DotDotDot, "ELLIPSIS"),
        (Hash, "HASH"),
        (At, "AT"),
        (AtBang, "AT_EXCL"),
        (Lt, "LT"),
        (LtEq, "LE"),
        (LtColon, "UPPERBOUND"),
        (EqEq, "EQUAL"),
        (BangEq, "NOTEQ"),
        (Dollar, "DOLLAR"),
        (Backslash, "ILLEGAL"),
        (ErrorToken, "ILLEGAL"),
        (IntLit, "INTEGER_LITERAL"),
        (FloatLit, "FLOAT_LITERAL"),
        (Ident, "IDENTIFIER"),
        (DollarIdent, "DOLLAR_IDENTIFIER"),
        (Underscore, "WILDCARD"),
        (TrueKw, "BOOL_LITERAL"),
        (FalseKw, "BOOL_LITERAL"),
        (Int8Kw, "INT8"),
        (Int16Kw, "INT16"),
        (Int32Kw, "INT32"),
        (Int64Kw, "INT64"),
        (IntNativeKw, "INTNATIVE"),
        (UInt8Kw, "UINT8"),
        (UInt16Kw, "UINT16"),
        (UInt32Kw, "UINT32"),
        (UInt64Kw, "UINT64"),
        (UIntNativeKw, "UINTNATIVE"),
        (Float16Kw, "FLOAT16"),
        (Float32Kw, "FLOAT32"),
        (Float64Kw, "FLOAT64"),
        (RuneKw, "RUNE"),
        (BoolKw, "BOOLEAN"),
        (NothingKw, "NOTHING"),
        (UnitKw, "UNIT"),
        (StructKw, "STRUCT"),
        (EnumKw, "ENUM"),
        (VArrayKw, "VARRAY"),
        (ThisTypeKw, "THISTYPE"),
        (PackageKw, "PACKAGE"),
        (ImportKw, "IMPORT"),
        (ClassKw, "CLASS"),
        (InterfaceKw, "INTERFACE"),
        (FuncKw, "FUNC"),
        (MacroKw, "MACRO"),
        (QuoteKw, "QUOTE"),
        (LetKw, "LET"),
        (VarKw, "VAR"),
        (ConstKw, "CONST"),
        (TypeKw, "TYPE"),
        (InitKw, "INIT"),
        (ThisKw, "THIS"),
        (SuperKw, "SUPER"),
        (IfKw, "IF"),
        (ElseKw, "ELSE"),
        (CaseKw, "CASE"),
        (TryKw, "TRY"),
        (CatchKw, "CATCH"),
        (FinallyKw, "FINALLY"),
        (ForKw, "FOR"),
        (DoKw, "DO"),
        (WhileKw, "WHILE"),
        (ThrowKw, "THROW"),
        (ReturnKw, "RETURN"),
        (ContinueKw, "CONTINUE"),
        (BreakKw, "BREAK"),
        (InKw, "IN"),
        (MatchKw, "MATCH"),
        (WhereKw, "WHERE"),
        (ExtendKw, "EXTEND"),
        (WithKw, "WITH"),
        (PropKw, "PROP"),
        (StaticKw, "STATIC"),
        (PublicKw, "PUBLIC"),
        (PrivateKw, "PRIVATE"),
        (InternalKw, "INTERNAL"),
        (ProtectedKw, "PROTECTED"),
        (OverrideKw, "OVERRIDE"),
        (RedefKw, "REDEF"),
        (AbstractKw, "ABSTRACT"),
        (SealedKw, "SEALED"),
        (OpenKw, "OPEN"),
        (ForeignKw, "FOREIGN"),
        (InoutKw, "INOUT"),
        (MutKw, "MUT"),
        (UnsafeKw, "UNSAFE"),
        (OperatorKw, "OPERATOR"),
        (SpawnKw, "SPAWN"),
        (SynchronizedKw, "SYNCHRONIZED"),
        (MainKw, "MAIN"),
        (IsKw, "IS"),
        (AsKw, "AS"),
        (CommonKw, "COMMON"),
        (SpecificKw, "SPECIFIC"),
        (FeaturesKw, "FEATURES")
    ]

let SIMPLE_KIND_NAMES: HashMap<SyntaxKind, String> = HashMap<SyntaxKind, String>(SIMPLE_KINDS)

/**
 * Every kind `macroTokens` sends: an SDK whose `Tokens.inc` lacks one is sent nothing.
 */
let SENT_KINDS: Array<String> =
    SIMPLE_KINDS
        .map { k => k[1] }
        .concat(
            [
                "GT",
                "GE",
                "RSHIFT",
                "RSHIFT_ASSIGN",
                "QUEST",
                "COALESCING",
                "NOT",
                "NOT_IN",
                "NL",
                "STRING_LITERAL",
                "MULTILINE_STRING",
                "JSTRING_LITERAL",
                "MULTILINE_RAW_STRING",
                "RUNE_LITERAL",
                "RUNE_BYTE_LITERAL"
            ]
        )

/**
 * The tokens cjc's lexer makes of `text`, as a macro is given them: no comment and no whitespace, an `NL` for each
 * line break, a string one token of what is between its quotes, `>>`, `>=`, `>>=`, `??` and `!in` glued. `begin`
 * is where `text` starts; a position is a line and a column in bytes, both from 1, as cjc counts them.
 */
public func macroTokens(
    text: String,
    numbers: TokenNumbers,
    begin: PositionData
): Array<TokenData> {
    MacroTokenWriter(text, numbers, begin).run()
}

/**
 * What cjc's lexer cuts otherwise than cjsyntax, as `cangjieLex` showed it on the pinned nightly (D95):
 *
 * - a string is one token of what its quotes enclose, interpolations as written; a multi-line one drops its first
 *   line break; `#"…"#` is a `MULTILINE_RAW_STRING` whose `delimiterNum` counts its `#`s; `r'a'` is the `a` alone,
 *   `b'a'` all of it;
 * - `>>`, `>=`, `>>=`, `??` and `!in` are glued (`greaterAt` and `notIn` say when);
 * - `true` and `false` are `BOOL_LITERAL`s, `_` a `WILDCARD`, a contextual keyword its own kind;
 * - an `NL` ends a column past where it starts, on its own line.
 */
class MacroTokenWriter {
    let lexed: Lexed<SyntaxKind>
    let bytes: Array<Byte>
    /** Where each line of `text` starts but the first. */
    let lineStarts = ArrayList<Int64>()
    let out = ArrayList<TokenData>()
    var i = 0

    MacroTokenWriter(let text: String, let numbers: TokenNumbers, let begin: PositionData) {
        lexed = tokenize(text)
        bytes = text.toArray()
        for (j in 0..bytes.size where bytes[j] == b'\n') {
            lineStarts.add(j + 1)
        }
    }

    func run(): Array<TokenData> {
        while (i < lexed.size) {
            let kind = lexed.kind(i)
            let range = lexed.range(i)
            match (kind) {
                case Whitespace | LineComment | BlockComment => i++
                case Newline =>
                    newlines(range.start, range.end)
                    i++
                case StringStart => string()
                case RawStringLit =>
                    let hashes = countHashes(range.start)
                    let inner = min(range.start + hashes + 1, range.end)
                    emit(
                        "MULTILINE_RAW_STRING",
                        range.start,
                        range.end,
                        valueStart: inner,
                        valueEnd: max(inner, range.end - hashes - 1),
                        delimiterNum: UInt32(hashes)
                    )
                    i++
                case RuneLit =>
                    emit(
                        "RUNE_LITERAL",
                        range.start,
                        range.end,
                        valueStart: min(range.start + 2, range.end),
                        valueEnd: max(range.start + 2, range.end - 1)
                    )
                    i++
                case ByteLit =>
                    emit("RUNE_BYTE_LITERAL", range.start, range.end)
                    i++
                case Gt => greater(range.start)
                case Question =>
                    if (adjacent(Question)) {
                        emit("COALESCING", range.start, range.start + 2)
                        i += 2
                    } else {
                        emit("QUEST", range.start, range.end)
                        i++
                    }
                case Bang =>
                    if (notIn()) {
                        emit("NOT_IN", range.start, lexed.range(i + 1).end)
                        i += 2
                    } else {
                        emit("NOT", range.start, range.end)
                        i++
                    }
                case _ =>
                    emit(SIMPLE_KIND_NAMES.get(kind) ?? "ILLEGAL", range.start, range.end)
                    i++
            }
        }
        out.toArray()
    }

    /** Whether the token after the `i`th is a `kind` right after it. */
    func adjacent(kind: SyntaxKind): Bool {
        i + 1 < lexed.size && lexed.kind(i + 1) == kind
    }

    /**
     * Whether the `!` at `i` and the `in` after it are one `!in`: cjc glues them before a space or a line break
     * alone, not before a tab or the end.
     */
    func notIn(): Bool {
        if (!adjacent(InKw)) {
            return false
        }
        let next = byteAt(lexed.range(i + 1).end)
        next == b' ' || next == b'\r' || next == b'\n'
    }

    /**
     * An `NL` for each line break in `start..end`, `\r\n` one.
     */
    func newlines(start: Int64, end: Int64): Unit {
        var j = start
        while (j < end) {
            let len =
                if (bytes[j] == b'\r' && j + 1 < end && bytes[j + 1] == b'\n') { 2 } else { 1 }
            if (bytes[j + len - 1] == b'\n') {
                emit("NL", j, j + len)
            }
            j += len
        }
    }

    /**
     * A string from its `StringStart` to its `StringEnd`, interpolations and the strings in them included, as one
     * token of what its quotes enclose; a multi-line string's first line break is not part of it.
     */
    func string(): Unit {
        let open = lexed.range(i)
        let opener = lexed.tokenText(i)
        var depth = 0
        var close = open
        while (i < lexed.size) {
            match (lexed.kind(i)) {
                case StringStart => depth++
                case StringEnd => depth--
                case _ => ()
            }
            close = lexed.range(i)
            i++
            if (depth == 0) {
                break
            }
        }
        let closed = depth == 0
        let innerEnd = if (closed) { close.start } else { close.end }
        let (name, innerStart) =
            match (opener) {
                case "\"\"\"" | "'''" => ("MULTILINE_STRING", skipLineBreak(open.end, innerEnd))
                case _ where opener.startsWith("J") => ("JSTRING_LITERAL", open.end)
                case _ => ("STRING_LITERAL", open.end)
            }
        emit(name, open.start, close.end, valueStart: innerStart, valueEnd: innerEnd)
    }

    func skipLineBreak(start: Int64, end: Int64): Int64 {
        if (start < end && bytes[start] == b'\n') {
            start + 1
        } else if (start + 1 < end && bytes[start] == b'\r' && bytes[start + 1] == b'\n') {
            start + 2
        } else {
            start
        }
    }

    func countHashes(start: Int64): Int64 {
        var n = 0
        while (start + n < bytes.size && bytes[start + n] == b'#') {
            n++
        }
        n
    }

    /**
     * `>` and what cjc's lexer glues to it, cut from the bytes as cjc cuts them: cjsyntax cuts `>` alone, and may
     * have lexed what follows into a `==` or a `=>` cjc cuts elsewhere, so the bytes are cut on until a token of
     * cjsyntax's ends where one of cjc's does.
     */
    func greater(start: Int64): Unit {
        var at = start
        do {
            let (name, len) = if (byteAt(at) == b'>') { greaterAt(at) } else { equalAt(at) }
            emit(name, at, at + len)
            at += len
            while (i < lexed.size && lexed.range(i).start < at) {
                i++
            }
        } while (lexed.range(i - 1).end > at)
    }

    /**
     * The token cjc cuts at the `>` at `at`: `>>=`, `>>`, `>=` or `>`. Its `=` is left to a `=>` after it, unless a
     * `=` or a `>` follows that, which is how cjc reads `{x: Array<T>=> x}` (verified on cjc's lexer through
     * std.ast's `cangjieLex`: `>=>` is `>` `=>`, `>=>=` is `>=` `>=`).
     */
    func greaterAt(at: Int64): (String, Int64) {
        if (byteAt(at + 1) == b'>') {
            if (byteAt(at + 2) == b'=' && !arrowAt(at + 2)) {
                ("RSHIFT_ASSIGN", 3)
            } else {
                ("RSHIFT", 2)
            }
        } else if (byteAt(at + 1) == b'=' && !arrowAt(at + 1)) {
            ("GE", 2)
        } else {
            ("GT", 1)
        }
    }

    /** The token cjc cuts at the `=` at `at`: `==`, `=>` or `=`. */
    func equalAt(at: Int64): (String, Int64) {
        match (byteAt(at + 1)) {
            case b'=' => ("EQUAL", 2)
            case b'>' => ("DOUBLE_ARROW", 2)
            case _ => ("ASSIGN", 1)
        }
    }

    /** Whether a `=>` cjc keeps whole starts at `at`. */
    func arrowAt(at: Int64): Bool {
        byteAt(at) == b'=' && byteAt(at + 1) == b'>' && byteAt(at + 2) != b'=' &&
            byteAt(at + 2) != b'>'
    }

    /** The byte at `at`, 0 past the end. */
    func byteAt(at: Int64): Byte {
        if (at < bytes.size) { bytes[at] } else { 0 }
    }

    /**
     * A token of kind `name` over `start..end`, whose value is `text[valueStart..valueEnd]`.
     */
    func emit(
        name: String,
        start: Int64,
        end: Int64,
        valueStart!: Int64 = start,
        valueEnd!: Int64 = end,
        delimiterNum!: UInt32 = 1
    ): Unit {
        out
            .add(
                TokenData(
                    kind: numbers.numberOf(name),
                    value: text[valueStart..valueEnd],
                    begin: position(start),
                    end: endPosition(start, end),
                    delimiterNum: delimiterNum
                )
            )
    }

    /**
     * Where a token over `start..end` ends as cjc says: a column past its last byte, on that byte's line, so that
     * an `NL` ends on the line it breaks.
     */
    func endPosition(start: Int64, end: Int64): PositionData {
        if (end == start) {
            return position(start)
        }
        let last = position(end - 1)
        PositionData(fileId: last.fileId, line: last.line, column: last.column + 1)
    }

    /**
     * The position of the byte at `offset`.
     */
    func position(offset: Int64): PositionData {
        let line = lineOf(offset)
        let column =
            if (line == 0) {
                Int64(begin.column) + offset
            } else {
                offset - lineStarts[line - 1] + 1
            }
        PositionData(fileId: begin.fileId, line: begin.line + Int32(line), column: Int32(column))
    }

    /**
     * How many line breaks there are before `offset`.
     */
    func lineOf(offset: Int64): Int64 {
        var lo = 0
        var hi = lineStarts.size
        while (lo < hi) {
            let mid = (lo + hi) / 2
            if (lineStarts[mid] <= offset) { lo = mid + 1 } else { hi = mid }
        }
        lo
    }
}
