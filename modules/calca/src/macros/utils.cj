macro package calca.macros

import std.ast.*
import std.collection.*

func modifiersOf(modifiers: ArrayList<Modifier>): Tokens {
    var tokens = Tokens()
    for (modifier in modifiers) {
        tokens += modifier.toTokens()
    }
    tokens
}

/**
 * `` `type` `` -> `type`: backquotes escape an identifier in the source and are no part of its name.
 */
func stripBackquotes(ident: String): String {
    if (ident.size >= 2 && ident.startsWith("`") && ident.endsWith("`")) {
        ident[1..ident.size - 1]
    } else {
        ident
    }
}

/**
 * `name` and the types of a signature as one identifier, a different one for every signature, so
 * overloads generate names of their own: `f(db: Db, x: ?Int64)` is `f_SDb_SQInt64`. Each type
 * follows `_S`; in a name or a type, `_` is `__`, a sign `_` and a letter, anything else `_X`, its
 * code and `_`.
 */
func mangled(name: String, types: Array<Tokens>): String {
    let out = StringBuilder()
    escapeInto(out, stripBackquotes(name))
    for (tokens in types) {
        out.append("_S")
        for (token in tokens where token.kind != TokenKind.NL) {
            escapeInto(out, stripBackquotes(token.value))
        }
    }
    out.toString()
}

private func escapeInto(out: StringBuilder, text: String): Unit {
    for (rune in text.runes()) {
        let code = UInt32(rune)
        let sign = match (rune) {
            case '_' => "__"
            case '<' => "_L"
            case '>' => "_G"
            case ',' => "_C"
            case '?' => "_Q"
            case '.' => "_D"
            case '(' => "_P"
            case ')' => "_R"
            case '-' => "_M"
            // letters and digits, and whatever is past ASCII, which only an identifier holds
            case _ where code > 0x7F || rune.isAsciiLetter() || rune.isAsciiNumber() => rune.toString()
            case _ => "_X${code}_"
        }
        out.append(sign)
    }
}

func capitalized(name: String): String {
    if (name.isEmpty()) {
        name
    } else {
        name[0..1].toAsciiUpper() + name[1..]
    }
}

/**
 * The struct `input` declares, reporting anything else, or a generic one.
 */
func plainStruct(input: Tokens, macroName: String): ?StructDecl {
    match (parseDecl(input)) {
        case sd: StructDecl where sd.isGenericDecl =>
            diagReport(DiagReportLevel.ERROR, input, "a `@${macroName}` type is not generic", "")
            None
        case sd: StructDecl => sd
        case _ =>
            diagReport(DiagReportLevel.ERROR, input, "`@${macroName}` goes on a struct", "")
            None
    }
}

/**
 * The fields of a type whose fields live in the database, and the rest of its members, kept as they
 * are. `None` once a field that cannot be one was reported.
 */
func storedFields(decl: StructDecl, macroName: String): ?(ArrayList<VarDecl>, Tokens) {
    let fields = ArrayList<VarDecl>()
    var kept = Tokens()
    for (member in decl.body.decls) {
        match (member) {
            case field: VarDecl =>
                if (!isFieldValid(field, macroName)) {
                    return None
                }
                fields.add(field)
            case _ => kept += member.toTokens()
        }
    }
    (fields, kept)
}

private func isFieldValid(field: VarDecl, macroName: String): Bool {
    if (isPresent {=> field.expr}) {
        diagReport(DiagReportLevel.ERROR, field.toTokens(), "a `@${macroName}` field has no initializer",
            "its value is given to the constructor")
        return false
    }
    if (!isPresent {=> field.declType}) {
        diagReport(DiagReportLevel.ERROR, field.toTokens(), "a `@${macroName}` field declares its type", "")
        return false
    }
    for (modifier in field.modifiers where modifier.keyword.kind == TokenKind.STATIC) {
        diagReport(DiagReportLevel.ERROR, field.toTokens(), "a `@${macroName}` type has no static fields", "")
        return false
    }
    true
}

/**
 * Whether the optional part of a node `read` gets is there: `std.ast` throws for one that is not.
 */
private func isPresent<T>(read: () -> T): Bool {
    try {
        read()
        true
    } catch (_: ASTException) {
        false
    }
}

/**
 * A type that is its `calcaId`, in the database `ingredient` keeps: a constructor of the database
 * and `params` setting it to what `create` gives, the `accessors`, then the identity members,
 * described by that ingredient, and the members the user wrote, `kept`. Its supertypes are the
 * identity ones, `identity` after them (`& InternedValue`), then those the user wrote.
 */
func identityStruct(decl: StructDecl, ingredient: Tokens, params: Tokens, create: Tokens, accessors: Tokens,
    kept: Tokens, identity!: Tokens = quote()): Tokens {
    let visibility = modifiersOf(decl.modifiers)
    let name = decl.identifier
    var superTypes = quote(Hashable & Equatable<$name> & ToString $identity)
    for (superType in decl.superTypes) {
        superTypes += quote(& $(superType.toTokens()))
    }
    quote(
        $visibility struct $name <: $superTypes {
            private static let CALCA_INGREDIENT = $ingredient

            private let calcaId: Id

            $visibility $name(db: Database, $params) {
                calcaId = $create
            }

            $accessors

            public func hashCode(): Int64 {
                calcaId.hashCode()
            }

            public operator func ==(other: $name): Bool {
                calcaId == other.calcaId
            }

            public operator func !=(other: $name): Bool {
                calcaId != other.calcaId
            }

            public func toString(): String {
                CALCA_INGREDIENT.describe(calcaId)
            }

            $kept
        }
    )
}

/**
 * A declared name as a string literal, the way calca names it in what it reports.
 */
func nameLiteral(name: Token): Token {
    Token(TokenKind.STRING_LITERAL, stripBackquotes(name.value))
}

/**
 * A struct of `fields`, `Hashable` and `Equatable` by all of them: several values as one key, which
 * a tuple cannot be.
 */
func fieldsStruct(name: Token, fields: Array<(Token, Tokens)>): Tokens {
    var params = Tokens()
    var hashes = Tokens()
    var equal = quote(true)
    for ((ident, fieldType) in fields) {
        params += quote(let $ident: $fieldType, )
        hashes += quote(hasher.write($ident.hashCode())
        )
        equal += quote(&& $ident == other.$ident)
    }
    quote(
        struct $name <: Hashable & Equatable<$name> {
            $name($params) {}

            public func hashCode(): Int64 {
                var hasher = DefaultHasher()
                $hashes
                hasher.finish()
            }

            public operator func ==(other: $name): Bool {
                $equal
            }

            public operator func !=(other: $name): Bool {
                !(this == other)
            }
        }
    )
}
