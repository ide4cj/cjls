package fbs_codegen

import std.collection.*
import std.convert.*
import std.deriving.*

/**
 * A scalar of a schema, by its name there (`uint32`, or its alias `uint`).
 */
@Derive[Equatable]
enum Scalar {
    | FbBool
    | FbInt8
    | FbUInt8
    | FbInt16
    | FbUInt16
    | FbInt32
    | FbUInt32
    | FbInt64
    | FbUInt64
    | FbFloat32
    | FbFloat64

    static func named(name: String): ?Scalar {
        match (name) {
            case "bool" => FbBool
            case "int8" | "byte" => FbInt8
            case "uint8" | "ubyte" => FbUInt8
            case "int16" | "short" => FbInt16
            case "uint16" | "ushort" => FbUInt16
            case "int32" | "int" => FbInt32
            case "uint32" | "uint" => FbUInt32
            case "int64" | "long" => FbInt64
            case "uint64" | "ulong" => FbUInt64
            case "float32" | "float" => FbFloat32
            case "float64" | "double" => FbFloat64
            case _ => Option<Scalar>.None
        }
    }

    /** Its size in bytes, which is also its alignment. */
    prop size: Int64 {
        get() {
            match (this) {
                case FbBool | FbInt8 | FbUInt8 => 1
                case FbInt16 | FbUInt16 => 2
                case FbInt32 | FbUInt32 | FbFloat32 => 4
                case FbInt64 | FbUInt64 | FbFloat64 => 8
            }
        }
    }

    /** The Cangjie type it reads as. */
    prop cangjie: String {
        get() {
            match (this) {
                case FbBool => "Bool"
                case FbInt8 => "Int8"
                case FbUInt8 => "UInt8"
                case FbInt16 => "Int16"
                case FbUInt16 => "UInt16"
                case FbInt32 => "Int32"
                case FbUInt32 => "UInt32"
                case FbInt64 => "Int64"
                case FbUInt64 => "UInt64"
                case FbFloat32 => "Float32"
                case FbFloat64 => "Float64"
            }
        }
    }

    prop isInteger: Bool {
        get() {
            match (this) {
                case FbBool | FbFloat32 | FbFloat64 => false
                case _ => true
            }
        }
    }
}

/**
 * The type of a field: a scalar, a string, a declaration of the schema by its name, or a vector of one of
 * these.
 */
enum FbType {
    | ScalarType(Scalar)
    | StringType
    | NamedType(String)
    | VectorType(FbType)
}

class Field {
    Field(
        let name: String,
        let fbType: FbType,
        let defaultValue: ?String,
        let required: Bool,
        let deprecated: Bool,
        let doc: Array<String>
    ) {}
}

class EnumMember {
    EnumMember(let name: String, let value: Int64, let doc: Array<String>) {}
}

/**
 * A member of a union: `name` is what the union calls it, `typeName` what it holds (they differ for
 * `StringValue:string`).
 */
class UnionMember {
    UnionMember(let name: String, let typeName: String, let doc: Array<String>) {}
}

@Derive[Equatable]
enum DeclKind {
    | EnumDecl
    | UnionDecl
    | StructDecl
    | TableDecl
}

/**
 * A declaration of the schema: an enum with its `underlying` scalar and `members`, a union with its
 * `unionMembers`, a struct or a table with its `fields`.
 */
class Decl {
    Decl(
        let kind: DeclKind,
        let name: String,
        let doc: Array<String>,
        let underlying!: ?Scalar = None,
        let members!: Array<EnumMember> = [],
        let unionMembers!: Array<UnionMember> = [],
        let fields!: Array<Field> = []
    ) {}
}

class Schema {
    Schema(
        let namespace: String,
        let fileIdentifier: ?String,
        let rootType: ?String,
        let decls: Array<Decl>
    ) {}

    func find(name: String): ?Decl {
        for (d in decls where d.name == name) {
            return d
        }
        Option<Decl>.None
    }
}

class SchemaException <: Exception {
    SchemaException(message: String) {
        super(message)
    }

    protected override func getClassName(): String {
        "SchemaException"
    }
}

// ---- lexer

@Derive[Equatable]
enum TokenKind {
    | Ident
    | Number
    | StringLit
    | Punct
    | Eof
}

struct Token {
    Token(let kind: TokenKind, let text: String, let line: Int64) {}
}

/**
 * The tokens of `text`, and its `//` comments by the line they are on: a comment documents the declaration
 * on its line, or the one under the lines it fills.
 */
func tokenize(text: String): (Array<Token>, HashMap<Int64, String>) {
    let tokens = ArrayList<Token>()
    let comments = HashMap<Int64, String>()
    let b = text.toArray()
    var i = 0
    var line = 1
    while (i < b.size) {
        let c = b[i]
        if (c == b'\n') {
            line++
            i++
        } else if (c == b' ' || c == b'\t' || c == b'\r') {
            i++
        } else if (c == b'/' && i + 1 < b.size && b[i + 1] == b'/') {
            var j = i
            while (j < b.size && b[j] != b'\n') {
                j++
            }
            var start = i + 2
            while (start < j && b[start] == b'/') {
                start++
            }
            comments[line] = String.fromUtf8(b[start..j]).trimAscii()
            i = j
        } else if (c == b'/' && i + 1 < b.size && b[i + 1] == b'*') {
            var j = i + 2
            while (j + 1 < b.size && !(b[j] == b'*' && b[j + 1] == b'/')) {
                if (b[j] == b'\n') {
                    line++
                }
                j++
            }
            i = j + 2
        } else if (isIdentStart(c)) {
            var j = i
            while (j < b.size && (isIdentStart(b[j]) || isDigit(b[j]))) {
                j++
            }
            tokens.add(Token(Ident, String.fromUtf8(b[i..j]), line))
            i = j
        } else if (isDigit(c) || (c == b'-' && i + 1 < b.size && isDigit(b[i + 1]))) {
            var j = i + 1
            while (j < b.size && (isDigit(b[j]) || isIdentStart(b[j]) || b[j] == b'.')) {
                j++
            }
            tokens.add(Token(Number, String.fromUtf8(b[i..j]), line))
            i = j
        } else if (c == b'"') {
            var j = i + 1
            while (j < b.size && b[j] != b'"') {
                j++
            }
            tokens.add(Token(StringLit, String.fromUtf8(b[i + 1..j]), line))
            i = j + 1
        } else {
            tokens.add(Token(Punct, String.fromUtf8(b[i..i + 1]), line))
            i++
        }
    }
    tokens.add(Token(Eof, "", line))
    (tokens.toArray(), comments)
}

func isIdentStart(c: Byte): Bool {
    (c >= b'a' && c <= b'z') || (c >= b'A' && c <= b'Z') || c == b'_'
}

func isDigit(c: Byte): Bool {
    c >= b'0' && c <= b'9'
}

// ---- parser

/**
 * The schema `text` declares. What it reads is the part of the flatbuffers grammar a schema of one file
 * uses: `namespace`, `file_identifier`, `root_type`, `attribute`, and enums, unions, structs and tables
 * whose fields may have a default and metadata in parentheses. An `include` or an `rpc_service` is refused.
 *
 * @throws SchemaException - at the first token it cannot read, naming its line
 */
func parseSchema(text: String): Schema {
    SchemaParser(text).parse()
}

class SchemaParser {
    let tokens: Array<Token>
    let comments: HashMap<Int64, String>
    var at = 0

    init(text: String) {
        (tokens, comments) = tokenize(text)
    }

    func parse(): Schema {
        var namespace = ""
        var fileIdentifier = Option<String>.None
        var rootType = Option<String>.None
        let decls = ArrayList<Decl>()
        while (peek().kind != Eof) {
            let start = peek().line
            let keyword = expect(Ident).text
            match (keyword) {
                case "namespace" =>
                    namespace = qualifiedName()
                    expectPunct(";")
                case "file_identifier" =>
                    fileIdentifier = expect(StringLit).text
                    expectPunct(";")
                case "root_type" =>
                    rootType = expect(Ident).text
                    expectPunct(";")
                case "attribute" =>
                    expect(StringLit)
                    expectPunct(";")
                case "enum" => decls.add(enumDecl(docBefore(start)))
                case "union" => decls.add(unionDecl(docBefore(start)))
                case "struct" => decls.add(fieldsDecl(StructDecl, docBefore(start)))
                case "table" => decls.add(fieldsDecl(TableDecl, docBefore(start)))
                case _ => throw fail("`${keyword}` is not read here")
            }
        }
        Schema(namespace, fileIdentifier, rootType, decls.toArray())
    }

    private func enumDecl(doc: Array<String>): Decl {
        let name = expect(Ident).text
        expectPunct(":")
        let underlyingName = expect(Ident).text
        let underlying = match (Scalar.named(underlyingName)) {
            case Some(s) where s.isInteger => s
            case _ => throw fail("enum ${name} is of ${underlyingName}, not an integer")
        }
        skipMetadata()
        expectPunct("{")
        let members = ArrayList<EnumMember>()
        var next = 0
        while (!isPunct("}")) {
            let token = expect(Ident)
            if (isPunct("=")) {
                advance()
                next = integer(expect(Number))
            }
            let end = peek().line
            if (isPunct(",")) {
                advance()
            }
            members.add(EnumMember(token.text, next, docOf(token.line, end)))
            next++
        }
        expectPunct("}")
        Decl(EnumDecl, name, doc, underlying: underlying, members: members.toArray())
    }

    private func unionDecl(doc: Array<String>): Decl {
        let name = expect(Ident).text
        skipMetadata()
        expectPunct("{")
        let members = ArrayList<UnionMember>()
        while (!isPunct("}")) {
            let token = expect(Ident)
            var typeName = token.text
            if (isPunct(":")) {
                advance()
                typeName = expect(Ident).text
            }
            if (isPunct(",")) {
                advance()
            }
            members.add(UnionMember(token.text, typeName, docOf(token.line, token.line)))
        }
        expectPunct("}")
        Decl(UnionDecl, name, doc, unionMembers: members.toArray())
    }

    private func fieldsDecl(kind: DeclKind, doc: Array<String>): Decl {
        let name = expect(Ident).text
        skipMetadata()
        expectPunct("{")
        let fields = ArrayList<Field>()
        while (!isPunct("}")) {
            let token = expect(Ident)
            expectPunct(":")
            let fbType = fieldType()
            var defaultValue = Option<String>.None
            if (isPunct("=")) {
                advance()
                defaultValue = advance().text
            }
            let (required, deprecated) = metadata()
            let end = peek().line
            expectPunct(";")
            fields.add(Field(token.text, fbType, defaultValue, required, deprecated, docOf(token.line, end)))
        }
        expectPunct("}")
        Decl(kind, name, doc, fields: fields.toArray())
    }

    private func fieldType(): FbType {
        if (isPunct("[")) {
            advance()
            let element = fieldType()
            expectPunct("]")
            return VectorType(element)
        }
        let name = qualifiedName()
        if (name == "string") {
            return StringType
        }
        match (Scalar.named(name)) {
            case Some(s) => ScalarType(s)
            case _ => NamedType(name)
        }
    }

    /**
     * `(required, deprecated)` of the metadata in parentheses, if there is any; the rest is skipped.
     */
    private func metadata(): (Bool, Bool) {
        var required = false
        var deprecated = false
        if (!isPunct("(")) {
            return (required, deprecated)
        }
        advance()
        while (!isPunct(")")) {
            let key = expect(Ident).text
            if (isPunct(":")) {
                advance()
                advance()
            }
            if (isPunct(",")) {
                advance()
            }
            match (key) {
                case "required" => required = true
                case "deprecated" => deprecated = true
                case "id" => throw fail("explicit field ids are not read")
                case _ => ()
            }
        }
        expectPunct(")")
        (required, deprecated)
    }

    private func skipMetadata(): Unit {
        metadata()
    }

    private func qualifiedName(): String {
        var name = expect(Ident).text
        while (isPunct(".")) {
            advance()
            name = "${name}.${expect(Ident).text}"
        }
        name
    }

    /**
     * The comments on the lines right above `line`, and the one at the end of `end`.
     */
    private func docOf(line: Int64, end: Int64): Array<String> {
        let doc = ArrayList<String>(docBefore(line))
        if (let Some(c) <- comments.get(end) && !c.isEmpty()) {
            doc.add(c)
        }
        doc.toArray()
    }

    private func docBefore(line: Int64): Array<String> {
        var first = line
        while (comments.contains(first - 1) && !lineHasToken(first - 1)) {
            first--
        }
        let doc = ArrayList<String>()
        for (l in first..line) {
            doc.add(comments[l])
        }
        doc.toArray()
    }

    private func lineHasToken(line: Int64): Bool {
        for (t in tokens where t.line == line) {
            return true
        }
        false
    }

    private func integer(token: Token): Int64 {
        match (Int64.tryParse(token.text)) {
            case Some(v) => v
            case _ => throw fail("`${token.text}` is not an integer")
        }
    }

    private func peek(): Token {
        tokens[at]
    }

    private func advance(): Token {
        let t = tokens[at]
        if (t.kind != Eof) {
            at++
        }
        t
    }

    private func isPunct(text: String): Bool {
        peek().kind == Punct && peek().text == text
    }

    private func expect(kind: TokenKind): Token {
        if (peek().kind != kind) {
            throw fail("unexpected `${peek().text}`")
        }
        advance()
    }

    private func expectPunct(text: String): Unit {
        if (!isPunct(text)) {
            throw fail("expected `${text}`, found `${peek().text}`")
        }
        advance()
    }

    private func fail(message: String): SchemaException {
        SchemaException("line ${peek().line}: ${message}")
    }
}
