macro package stdxx.deriving

import std.ast.*
import std.collection.*

/*
 * A declaration as it is written, read once by `@DeriveExt` whatever it derives, and knowing no
 * interface: what a derivation makes of it - serde's wire names, a field's optionality - is the
 * derivation's.
 */

enum DeclKind {
    | IsStruct
    | IsClass
    | IsEnum
}

/**
 * A primary constructor parameter: a field, when it is declared with `let` or `var`.
 */
struct DeclField {
    DeclField(
        let ident!: Token,
        let fieldType!: Tokens,
        /** Declared with `let` or `var`: a bare parameter is gone once the constructor returns. */
        let isMember!: Bool,
        let isMutable!: Bool,
        /** `name!: T`, passed by name. */
        let isNamed!: Bool,
        /** The whole parameter, for a diagnostic to point at. */
        let tokens!: Tokens
    ) {}
}

/**
 * An enum constructor and the types of its payloads, none for a plain one.
 */
struct DeclVariant {
    DeclVariant(let ident!: Token, let payloadTypes!: Array<Tokens>) {}
}

class DeclShape {
    DeclShape(
        let decl!: Decl,
        let kind!: DeclKind,
        /** The primary constructor's parameters, `None` for a `struct` or `class` without one and for an `enum`. */
        let fields!: ?Array<DeclField>,
        /** The constructors of an `enum`, empty for anything else. */
        let variants!: Array<DeclVariant>
    ) {}

    prop ident: Token {
        get() {
            decl.identifier
        }
    }

    /**
     * @return `None`, reported, for anything but a `struct`, a `class` or an `enum`
     */
    static func of(decl: Decl, derive: String): ?DeclShape {
        if (let enumDecl: EnumDecl <- decl) {
            let variants = enumDecl.constructors.toArray().map {
                ctor => DeclVariant(
                    ident: ctor.identifier,
                    payloadTypes: ctor.typeArguments.toArray().map {payloadType => payloadType.toTokens()}
                )
            }
            return DeclShape(decl: decl, kind: IsEnum, fields: None, variants: variants)
        }
        let kind = if (decl is StructDecl) {
            IsStruct
        } else if (decl is ClassDecl) {
            IsClass
        } else {
            report(decl, "`@DeriveExt[${derive}]` only derives for a `struct`, a `class` or an `enum`",
                "hand-write it for anything else")
            return None
        }
        let fields = primaryCtorOf(decl).map {
            ctor => ctor.funcParams.toArray().map {param => fieldOf(param)}
        }

        DeclShape(decl: decl, kind: kind, fields: fields, variants: [])
    }
}

private func fieldOf(param: FuncParam): DeclField {
    let tokens = param.toTokens()
    let head = headTokenOf(tokens)

    DeclField(
        ident: param.identifier,
        fieldType: param.paramType.toTokens(),
        isMember: head.map {token => token.kind == TokenKind.LET || token.kind == TokenKind.VAR} ?? false,
        isMutable: head.map {token => token.kind == TokenKind.VAR} ?? false,
        isNamed: isNamedParam(tokens),
        tokens: tokens
    )
}

private func isNamedParam(tokens: Tokens): Bool {
    for (token in tokens) {
        if (token.kind == TokenKind.NOT) {
            return true
        }
        if (token.kind == TokenKind.COLON) {
            return false
        }
    }

    false
}

/**
 * The `where` clause asking every type parameter for `bound`, appended to its own bounds -
 * `ToJson`, `FromJson<T>`.
 */
func whereClauseOf(decl: Decl, bound: (String) -> String): Tokens {
    if (!decl.isGenericDecl) {
        return Tokens()
    }

    let clauses = ArrayList<String>()
    for (typeParam in decl.genericParam.parameters) {
        let bounds = ArrayList<String>()
        for (constraint in decl.genericConstraint) {
            if (constraint.typeArgument.toTokens().toString() != typeParam.value) {
                continue
            }
            for (upperBound in constraint.upperBounds) {
                bounds.add(upperBound.toTokens().toString())
            }
        }
        bounds.add(bound(typeParam.value))

        clauses.add("${typeParam.value} <: ${String.join(bounds.toArray(), delimiter: " & ")}")
    }

    cangjieLex("where ${String.join(clauses.toArray(), delimiter: ", ")}")
}

/**
 * `extend<T> Name<T> <: Interface where ... { body }` - every derivation ends in one.
 */
func extensionOf(decl: Decl, interfaceType: Tokens, bound: (String) -> String, body: Tokens): Tokens {
    let typeIdent = decl.identifier
    let typeArgs = typeArgsOf(decl)
    let whereClause = whereClauseOf(decl, bound)

    quote(
        extend $typeArgs $typeIdent$typeArgs <: $interfaceType $whereClause {
            $body
        }
    )
}

/**
 * The type as its own declaration names it, type parameters included - `Box<T>`.
 */
func selfTypeOf(decl: Decl): Tokens {
    let typeIdent = decl.identifier
    let typeArgs = typeArgsOf(decl)
    quote($typeIdent$typeArgs)
}
