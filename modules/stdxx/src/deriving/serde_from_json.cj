macro package stdxx.deriving

import std.ast.*

/*
 * `FromJson`: a value read straight from an `FjReader` - keys compared where they lie,
 * unknown ones skipped, no tree on the way.
 */

func deriveFromJson(model: DeclModel): Tokens {
    let (decl, body) = match (model) {
        case OfStruct(structModel) => (structModel.decl, structFromJson(structModel))
        case OfEnum(enumModel) =>
            let body = match (enumModel.shape) {
                case Scalar(isInteger, other) => scalarEnumFromJson(enumModel, isInteger, other)
                case Untagged => untaggedEnumFromJson(enumModel)
                case Tagged(tag) => taggedEnumFromJson(enumModel, tag)
            }
            (enumModel.decl, body)
    }
    let selfType = selfTypeOf(decl)

    extensionOf(
        decl,
        quote(FromJson<$selfType>),
        {param => "FromJson<${param}>"},
        quote(
            public static func fromJson(r: FjReader): $selfType {
                $body
            }
        )
    )
}

private func typeNameOf(decl: Decl): Token {
    Token(TokenKind.STRING_LITERAL, stripBackquotes(decl.identifier.value))
}

private func structFromJson(model: StructModel): Tokens {
    let selfType = selfTypeOf(model.decl)
    if (model.transparent) {
        let field = model.fields[0]
        let ident = field.ident
        let fieldType = field.fieldType
        return if (field.isNamed) {
            quote($selfType($ident: $fieldType.fromJson(r)))
        } else {
            quote($selfType($fieldType.fromJson(r)))
        }
    }

    let typeName = typeNameOf(model.decl)
    var tagLocal = Tokens()
    var tagBranch = Tokens()
    var tagCheck = Tokens()
    if (let Some((tag, value)) <- model.tag) {
        let name = Token(TokenKind.STRING_LITERAL, tag)
        let literal = Token(TokenKind.STRING_LITERAL, value)
        let unexpected = Token(TokenKind.STRING_LITERAL, "unexpected `${typeName.value}` ${tag}: ")
        tagLocal = quote(
            var tagSeen = false
        )
        // an untagged union picks the first variant that reads, and two tagged structs often differ
        // in nothing but the tag
        tagBranch = quote(
            if (r.keyIs($name)) {
                let tag = r.readString()
                if (tag != $literal) {
                    throw FjException($unexpected + tag)
                }
                tagSeen = true
                continue
            }
        )
        tagCheck = quote(
            if (!tagSeen) {
                throw missingField($typeName, $name)
            }
        )
    }

    let (locals, branches) = fieldReaders(model.fields, quote(r))
    let ctorArgs = commaSeparated(
        model.fields.map {
            field =>
            let value = fieldValue(field, typeName)
            let ident = field.ident
            if (field.isNamed) {
                quote($ident: $value)
            } else {
                value
            }
        })

    quote(
        $tagLocal
        $locals
        r.beginObject()
        while (r.nextKey()) {
            $tagBranch
            $branches
            r.skipValue()
        }
        $tagCheck
        $selfType($ctorArgs)
    )
}

/**
 * A local `?T` per field, and the branch that reads the field's key into it. Each branch `continue`s,
 * so a key none of them takes falls through to `skipValue`. A repeated key reads as its last value.
 */
private func fieldReaders(fields: Array<DerivedField>, reader: Tokens): (Tokens, Tokens) {
    var locals = Tokens()
    var branches = Tokens()
    for (field in fields) {
        let local = field.local
        let wireName = field.wireLiteral
        let innerType = field.innerType
        let (localType, read) = match (field.shape) {
            case Required => (quote(?$innerType), quote($innerType.fromJson($reader)))
            // `null` reads as `None`, as an absent key does
            case Optional => (quote(?$innerType), quote(Option<$innerType>.fromJson($reader)))
            // `null` reads as `Some(Null)`: only an absent key is `None`
            case OptionalNullable => (quote(?$innerType), quote(Some($innerType.fromJson($reader))))
        }
        locals += quote(
            var $local: $localType = Option<$innerType>.None
        )
        branches += quote(
            if ($reader.keyIs($wireName)) {
                $local = $read
                continue
            }
        )
    }

    (locals, branches)
}

/**
 * The local a field was read into, as its constructor argument: a required one has to have been there.
 */
private func fieldValue(field: DerivedField, typeName: Token): Tokens {
    let local = field.local
    let wireName = field.wireLiteral
    if (field.shape.isOptional) {
        quote($local)
    } else {
        quote($local ?? throw missingField($typeName, $wireName))
    }
}

/**
 * The value matched against every variant's; an integer `other` narrows it into its payload type,
 * throwing on one that does not fit rather than wrapping it.
 */
private func scalarEnumFromJson(model: EnumModel, isInteger: Bool, other: ?DerivedVariant): Tokens {
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
                        throw FjException($outOfRange + value.toString())
                    }
                )
            )
        case Some(o) =>
            let ident = o.ident
            quote(
                case value => $ident(value)
            )
        case None => quote(
            case value => throw FjException($unexpected + value.toString())
        )
    }
    let read = if (isInteger) {
        quote(r.readInt64())
    } else {
        quote(r.readString())
    }

    quote(
        match ($read) {
            $cases
        }
    )
}

/**
 * Each variant tried in declaration order from the value's start - the reader rewound to its mark
 * between attempts, so nothing is sliced or copied - and the first that reads is the one: a
 * decoder reads exactly one value, so one that read is at the value's end. Any exception means
 * "not this variant".
 */
private func untaggedEnumFromJson(model: EnumModel): Tokens {
    let typeName = typeNameOf(model.decl)
    var attempts = Tokens()
    for (variant in model.variants) {
        let ident = variant.ident
        if (variant.payloadTypes.size == 1) {
            let payloadType = variant.payloadTypes[0]
            attempts += quote(
                try {
                    r.rewind(mark)
                    return $ident($payloadType.fromJson(r))
                } catch (_: Exception) {}
            )
            continue
        }

        // a tuple: an array of exactly its payloads
        let bindings = variant.payloadBindings()
        var reads = Tokens()
        for (i in 0..bindings.size) {
            let binding = bindings[i]
            let payloadType = variant.payloadTypes[i]
            reads += quote(
                if (!r.nextItem()) {
                    throw FjException("")
                }
                let $binding = $payloadType.fromJson(r)
            )
        }
        let args = commaSeparated(bindings)
        attempts += quote(
            try {
                r.rewind(mark)
                r.beginArray()
                $reads
                if (!r.nextItem()) {
                    return $ident($args)
                }
            } catch (_: Exception) {}
        )
    }
    let unmatched = Token(TokenKind.STRING_LITERAL, "no `${typeName.value}` variant matched the value at byte ")

    quote(
        let mark = r.mark()
        $attempts
        throw FjException($unmatched + mark.toString())
    )
}

/**
 * The tag may come after the payload, so the value is read twice: once for the tag, then, the
 * reader rewound to its mark, for the fields of the variant it names.
 */
private func taggedEnumFromJson(model: EnumModel, tag: String): Tokens {
    let typeName = typeNameOf(model.decl)
    let tagLiteral = Token(TokenKind.STRING_LITERAL, tag)
    var cases = Tokens()
    for (variant in model.variants) {
        let ident = variant.ident
        let literal = variant.value.literal
        if (variant.payloadFields.isEmpty()) {
            // the reader is at the object's start again: past it, as reading its fields would be
            cases += quote(
                case $literal =>
                    r.skipValue()
                    $ident
            )
            continue
        }

        let (locals, branches) = fieldReaders(variant.payloadFields, quote(r))
        let args = commaSeparated(variant.payloadFields.map {field => fieldValue(field, typeName)})
        cases += quote(
            case $literal =>
                $locals
                r.beginObject()
                while (r.nextKey()) {
                    $branches
                    r.skipValue()
                }
                $ident($args)
        )
    }
    let unexpected = Token(TokenKind.STRING_LITERAL, "unexpected `${typeName.value}` ${tag}: ")

    quote(
        let mark = r.mark()
        var tag: ?String = Option<String>.None
        r.beginObject()
        while (r.nextKey()) {
            if (r.keyIs($tagLiteral)) {
                tag = r.readString()
            } else {
                r.skipValue()
            }
        }
        r.rewind(mark)
        match (tag ?? throw missingField($typeName, $tagLiteral)) {
            $cases
            case other => throw FjException($unexpected + other)
        }
    )
}
