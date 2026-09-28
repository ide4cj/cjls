macro package stdxx.deriving

import std.ast.*
import std.collection.*

/*
 * `FromToml`: serde's `Deserialize`, from a document read by `ftoml`. A table is looked up key by
 * key, so their order does not matter and one no field names is skipped; a required key missing is
 * an error naming it, at its table. An untagged enum tries each variant on the value, which a
 * document makes cheap: nothing is read twice.
 */

func deriveFromToml(model: DeclModel): Tokens {
    let (decl, body) = match (model) {
        case OfStruct(structModel) => (structModel.decl, structFromToml(structModel))
        case OfEnum(enumModel) =>
            let body = match (enumModel.shape) {
                case Scalar(isInteger, other) => scalarEnumFromToml(enumModel, isInteger, other)
                case Untagged => untaggedEnumFromToml(enumModel)
                case Tagged(tag) => taggedEnumFromToml(enumModel, tag)
            }
            (enumModel.decl, body)
    }
    let selfType = selfTypeOf(decl)

    extensionOf(
        decl,
        quote(FromToml<$selfType>),
        {param => "FromToml<${param}>"},
        quote(
            public static func fromToml(v: FtValue): $selfType {
                $body
            }
        )
    )
}

private func typeNameOf(decl: Decl): Token {
    Token(TokenKind.STRING_LITERAL, stripBackquotes(decl.identifier.value))
}

private func structFromToml(model: StructModel): Tokens {
    let selfType = selfTypeOf(model.decl)
    if (model.transparent) {
        let field = model.fields[0]
        let ident = field.ident
        let fieldType = field.fieldType
        return if (field.isNamed) {
            quote($selfType($ident: $fieldType.fromToml(v)))
        } else {
            quote($selfType($fieldType.fromToml(v)))
        }
    }

    let typeName = typeNameOf(model.decl)
    var tagCheck = Tokens()
    if (let Some((tag, value)) <- model.tag) {
        tagCheck = tagFromToml(typeName, tag, quote(
            if (tag != $(Token(TokenKind.STRING_LITERAL, value))) {
                throw tagValue.error($(Token(TokenKind.STRING_LITERAL, "unexpected `${typeName.value}` ${tag}: ")) + tag)
            }
        ))
    }
    let ctorArgs = commaSeparated(
        model.fields.map {
            field =>
            let value = fieldFromToml(field, typeName)
            let ident = field.ident
            if (field.isNamed) {
                quote($ident: $value)
            } else {
                value
            }
        })

    quote(
        let table = v.asTable()
        $tagCheck
        $selfType($ctorArgs)
    )
}

/**
 * The tag, read from `table` into `tag` (its value in `tagValue`), then `check`: checked before any
 * field, as two tagged structs often differ in nothing but the tag.
 */
private func tagFromToml(typeName: Token, tag: String, check: Tokens): Tokens {
    let name = Token(TokenKind.STRING_LITERAL, tag)
    quote(
        let tagValue = table.get($name) ?? throw missingKey(v, $typeName, $name)
        let tag = tagValue.asString()
        $check
    )
}

/** The field's key in `table`, read as its type; `None` for an optional one that is not there. */
private func fieldFromToml(field: DerivedField, typeName: Token): Tokens {
    let name = field.wireLiteral
    let innerType = field.innerType
    if (field.shape.isOptional) {
        quote(
            match (table.get($name)) {
                case Some(item) => Some($innerType.fromToml(item))
                case None => Option<$innerType>.None
            }
        )
    } else {
        quote($innerType.fromToml(table.get($name) ?? throw missingKey(v, $typeName, $name)))
    }
}

/**
 * The value matched against every variant's; an integer `other` narrows it into its payload type,
 * refusing one that does not fit rather than wrapping it.
 */
private func scalarEnumFromToml(model: EnumModel, isInteger: Bool, other: ?DerivedVariant): Tokens {
    let typeName = typeNameOf(model.decl)
    var cases = Tokens()
    for (variant in model.variants) {
        let ident = variant.ident
        let literal = variant.value.literal
        cases += quote(
            case $literal => $ident
        )
    }
    let unexpected = Token(TokenKind.STRING_LITERAL, "unexpected `${typeName.value}` value: ")
    cases += match (other) {
        case Some(o) where isInteger =>
            let ident = o.ident
            let payloadType = o.payloadTypes[0]
            let outOfRange = Token(TokenKind.STRING_LITERAL, "`${typeName.value}` value out of range: ")
            quote(
                case value => $ident(
                    try {
                        $payloadType(value)
                    } catch (_: OverflowException) {
                        throw v.error($outOfRange + value.toString())
                    }
                )
            )
        case Some(o) =>
            let ident = o.ident
            quote(
                case value => $ident(value)
            )
        case None => quote(
            case value => throw v.error($unexpected + value.toString())
        )
    }
    let read = if (isInteger) {
        quote(v.asInteger())
    } else {
        quote(v.asString())
    }

    quote(
        match ($read) {
            $cases
        }
    )
}

/**
 * Each variant tried in declaration order on the value, the first that reads is the one; a tuple
 * reads from an array of exactly its payloads. Any exception means "not this variant".
 */
private func untaggedEnumFromToml(model: EnumModel): Tokens {
    let typeName = typeNameOf(model.decl)
    var attempts = Tokens()
    for (variant in model.variants) {
        let ident = variant.ident
        if (variant.payloadTypes.size == 1) {
            let payloadType = variant.payloadTypes[0]
            attempts += quote(
                try {
                    return $ident($payloadType.fromToml(v))
                } catch (_: Exception) {}
            )
            continue
        }

        let count = Token(TokenKind.INTEGER_LITERAL, "${variant.payloadTypes.size}")
        let args = commaSeparated(
            Array(variant.payloadTypes.size) {
                i =>
                let payloadType = variant.payloadTypes[i]
                let index = Token(TokenKind.INTEGER_LITERAL, "${i}")
                quote($payloadType.fromToml(items[$index]))
            })
        attempts += quote(
            try {
                let items = v.asArray()
                if (items.size == $count) {
                    return $ident($args)
                }
            } catch (_: Exception) {}
        )
    }
    let unmatched = Token(TokenKind.STRING_LITERAL, "no `${typeName.value}` variant matched the value")

    quote(
        $attempts
        throw v.error($unmatched)
    )
}

/** The tag looked up first, then the keys of the variant it names. */
private func taggedEnumFromToml(model: EnumModel, tag: String): Tokens {
    let typeName = typeNameOf(model.decl)
    var cases = Tokens()
    for (variant in model.variants) {
        let ident = variant.ident
        let literal = variant.value.literal
        if (variant.payloadFields.isEmpty()) {
            cases += quote(
                case $literal => $ident
            )
            continue
        }

        let args = commaSeparated(variant.payloadFields.map {field => fieldFromToml(field, typeName)})
        cases += quote(
            case $literal => $ident($args)
        )
    }
    let unexpected = Token(TokenKind.STRING_LITERAL, "unexpected `${typeName.value}` ${tag}: ")
    let read = tagFromToml(typeName, tag, Tokens())

    quote(
        let table = v.asTable()
        $read
        match (tag) {
            $cases
            case other => throw tagValue.error($unexpected + other)
        }
    )
}
