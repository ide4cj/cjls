macro package stdxx.deriving

import std.ast.*
import std.collection.*

/*
 * `Serializable`: stdx's `DataModel`, what TOML and anything else of stdx.serialization read and write.
 */

func deriveSerializable(model: DeclModel): Tokens {
    match (model) {
        case OfStruct(structModel) => serializableStruct(structModel)
        case OfEnum(enumModel) => match (enumModel.shape) {
            case Scalar(isInteger, other) => serializableScalarEnum(enumModel, isInteger, other)
            case Untagged => serializableUntaggedEnum(enumModel)
            case Tagged(tag) => serializableTaggedEnum(enumModel, tag)
        }
    }
}

private func serializableStruct(model: StructModel): Tokens {
    let decl = model.decl
    let selfType = selfTypeOf(decl)
    if (model.transparent) {
        let field = model.fields[0]
        let ident = field.ident
        let fieldType = field.fieldType
        let ctorArg = if (field.isNamed) {
            quote($ident: $fieldType.deserialize(dm))
        } else {
            quote($fieldType.deserialize(dm))
        }
        return serializableExtension(decl, quote($selfType($ctorArg)), quote(this.$ident.serialize()))
    }

    var tagCheck = Tokens()
    var serializeChain = Tokens()
    if (let Some((tag, value)) <- model.tag) {
        let name = Token(TokenKind.STRING_LITERAL, tag)
        let literal = Token(TokenKind.STRING_LITERAL, value)
        let unexpected = Token(TokenKind.STRING_LITERAL, "unexpected `${decl.identifier.value}` ${tag}: ")
        // checked before any field: an untagged union picks the first variant that reads, and two
        // tagged structs often differ in nothing but the tag
        tagCheck = quote(
            let tag = dms.getOrThrow($name).asStringOrThrow()
            if (tag != $literal) {
                throw DataModelException($unexpected + tag)
            }
        )
        serializeChain = quote(.add(field($name, $literal)))
    }

    for (field in model.fields) {
        let ident = field.ident
        serializeChain += dataModelWriter(field, quote(this.$ident))
    }
    let ctorArgs = commaSeparated(
        model.fields.map {
            field =>
            let value = dataModelReader(field)
            let ident = field.ident
            if (field.isNamed) {
                quote($ident: $value)
            } else {
                value
            }
        })

    serializableExtension(
        decl,
        quote(
            let dms = dm.asStructOrThrow()
            $tagCheck

            $selfType($ctorArgs)
        ),
        quote(DataModelStruct()$serializeChain)
    )
}

/**
 * Reads the field's key of `dms` the way its shape wants it read.
 */
private func dataModelReader(field: DerivedField): Tokens {
    let wireName = field.wireLiteral
    match (field.shape) {
        case Required => quote(dms.getDeserializedOrThrow($wireName))
        case Optional => quote(dms.getDeserializedOrNoneOnNull($wireName))
        case OptionalNullable => quote(dms.getDeserializedOrNone($wireName))
    }
}

/**
 * The link that writes `value` under the field's key onto a `DataModelStruct` chain.
 *
 * `Option<T>` serializes itself as `null`, so writing it is the same call whatever the shape - until
 * `skipNone` asks for the key to be dropped instead.
 */
private func dataModelWriter(field: DerivedField, value: Tokens): Tokens {
    let wireName = field.wireLiteral
    if (field.skipNone && field.shape.isOptional) {
        quote(.addFieldIfSome($wireName, $value))
    } else {
        quote(.add(field($wireName, $value)))
    }
}

/**
 * Variants without a payload are the value itself - a string, or an integer when `value:` says so.
 */
private func serializableScalarEnum(model: EnumModel, isInteger: Bool, other: ?DerivedVariant): Tokens {
    let reader = if (isInteger) {
        quote(dm.asIntOrThrow())
    } else {
        quote(dm.asStringOrThrow())
    }
    let dataModel = if (isInteger) {
        quote(DataModelInt)
    } else {
        quote(DataModelString)
    }

    var readCases = Tokens()
    var writeCases = Tokens()
    for (variant in model.variants) {
        let ident = variant.ident
        let literal = variant.value.literal
        readCases += quote(
            case $literal => $ident
        )
        writeCases += quote(
            case $ident => $dataModel($literal)
        )
    }
    let unexpected = Token(TokenKind.STRING_LITERAL, "unexpected `${model.decl.identifier.value}` value: ")
    var fallback = quote(case value => throw DataModelException($unexpected + value.toString()))
    if (let Some(o) <- other) {
        let payloadType = o.payloadTypes[0]
        let ident = o.ident
        // read through the payload's own `Serializable`: it narrows the `Int64` the reader matched on, and
        // throws on a value that does not fit instead of wrapping it
        fallback = quote(case _ => $ident($payloadType.deserialize(dm)))
        writeCases += quote(
            case $ident(payload) => payload.serialize()
        )
    }

    serializableExtension(
        model.decl,
        quote(
            match ($reader) {
                $readCases
                $fallback
            }
        ),
        quote(
            match (this) {
                $writeCases
            }
        )
    )
}

/**
 * The variant is whichever one the value can be read as, tried in declaration order - serde's
 * `untagged`, with the same caveat about an earlier variant shadowing a later one.
 *
 * A variant with one payload is that payload alone; one with several is a tuple, which travels the
 * way JSON spells one - an array holding the payloads in order, of exactly that length.
 *
 * Any exception means "not this variant", not just a `DataModelException`: reading an `Int32` out
 * of a value too large for it throws `OverflowException`, and a narrower variant failing that way
 * is exactly what the next one is for.
 */
private func serializableUntaggedEnum(model: EnumModel): Tokens {
    var attempts = Tokens()
    var writeCases = Tokens()
    for (variant in model.variants) {
        let ident = variant.ident
        if (variant.payloadTypes.size == 1) {
            let payloadType = variant.payloadTypes[0]
            attempts += quote(
                try {
                    return $ident($payloadType.deserialize(dm))
                } catch (_: Exception) {}
            )
            writeCases += quote(
                case $ident(payload) => payload.serialize()
            )
            continue
        }

        let arity = variant.payloadTypes.size
        let bindings = variant.payloadBindings()
        let readArgs = commaSeparated(
            Array(arity) {
                i =>
                let payloadType = variant.payloadTypes[i]
                let index = Token(TokenKind.INTEGER_LITERAL, "${i}")
                quote($payloadType.deserialize(items[$index]))
            }
        )
        // one `add` per payload rather than an `ArrayList` literal: the expansion must not
        // depend on the caller importing `std.collection`
        var writeItems = Tokens()
        for (binding in bindings) {
            writeItems += quote(
                items.add($binding.serialize())
            )
        }
        let size = Token(TokenKind.INTEGER_LITERAL, "${arity}")
        let pattern = commaSeparated(bindings)
        attempts += quote(
            try {
                let items = dm.asSeqOrThrow().getItems()
                if (items.size == $size) {
                    return $ident($readArgs)
                }
            } catch (_: Exception) {}
        )
        writeCases += quote(
            case $ident($pattern) =>
                let items = DataModelSeq()
                $writeItems
                items
        )
    }
    let unexpected = Token(TokenKind.STRING_LITERAL, "no `${model.decl.identifier.value}` variant matched the value")

    serializableExtension(
        model.decl,
        quote(
            $attempts
            throw DataModelException($unexpected)
        ),
        quote(
            match (this) {
                $writeCases
            }
        )
    )
}

/**
 * The discriminator travels in a field of the object, next to the payload.
 */
private func serializableTaggedEnum(model: EnumModel, tag: String): Tokens {
    let tagLiteral = Token(TokenKind.STRING_LITERAL, tag)

    var readCases = Tokens()
    var writeCases = Tokens()
    for (variant in model.variants) {
        let ident = variant.ident
        let literal = variant.value.literal
        let bindings = variant.payloadBindings()

        let readArgs = commaSeparated(variant.payloadFields.map {field => dataModelReader(field)})
        var writeFields = Tokens()
        for ((i, field) in variant.payloadFields |> enumerate) {
            writeFields += dataModelWriter(field, bindings[i])
        }

        if (bindings.size == 0) {
            readCases += quote(
                case $literal => $ident
            )
            writeCases += quote(
                case $ident => DataModelStruct().add(field($tagLiteral, $literal))
            )
        } else {
            let pattern = commaSeparated(bindings)
            readCases += quote(
                case $literal => $ident($readArgs)
            )
            writeCases += quote(
                case $ident($pattern) => DataModelStruct().add(field($tagLiteral, $literal))$writeFields
            )
        }
    }
    let unexpected = Token(TokenKind.STRING_LITERAL, "unexpected `${model.decl.identifier.value}` ${tag}: ")

    serializableExtension(
        model.decl,
        quote(
            let dms = dm.asStructOrThrow()

            match (dms.getDeserializedOrThrow<String>($tagLiteral)) {
                $readCases
                case tag => throw DataModelException($unexpected + tag)
            }
        ),
        quote(
            match (this) {
                $writeCases
            }
        )
    )
}

/**
 * `extend T <: Serializable<T>` around the two bodies given.
 */
private func serializableExtension(decl: Decl, deserializeBody: Tokens, serializeBody: Tokens): Tokens {
    let selfType = selfTypeOf(decl)

    extensionOf(
        decl,
        quote(Serializable<$selfType>),
        {param => "Serializable<${param}>"},
        quote(
            public static func deserialize(dm: DataModel): $selfType {
                $deserializeBody
            }

            public func serialize(): DataModel {
                $serializeBody
            }
        )
    )
}
