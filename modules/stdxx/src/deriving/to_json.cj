macro package stdxx.deriving

import std.ast.*
import std.collection.*

/*
 * `ToJson`: serde's `Serialize`, straight into an `FjWriter` - no tree on the way.
 */

func deriveToJson(model: DeclModel): Tokens {
    let names = KeyNames(model)
    let body = match (model) {
        case OfStruct(structModel) => structToJson(structModel, names)
        case OfEnum(enumModel) => match (enumModel.shape) {
            case Scalar(isInteger, other) => scalarEnumToJson(enumModel, isInteger, other)
            case Untagged => untaggedEnumToJson(enumModel)
            case Tagged(tag) => taggedEnumToJson(enumModel, tag, names)
        }
    }
    let decl = match (model) {
        case OfStruct(structModel) => structModel.decl
        case OfEnum(enumModel) => enumModel.decl
    }

    // ahead of the extension: a global is used before it is defined when it comes later in the file
    names.declarations() + extensionOf(
        decl,
        quote(ToJson),
        {_ => "ToJson"},
        quote(
            public func toJson(w: FjWriter): Unit {
                $body
            }
        )
    )
}

/**
 * The keys a type writes, each encoded once in a global of its own - `FjWriter.name` then copies it
 * in one piece. Globals, not statics: an extension declares no variables. Their initializers reach
 * nothing the user wrote, so they cannot be used before they are initialized.
 */
class KeyNames {
    private let prefix: String
    private let names = ArrayList<(Token, String)>()

    KeyNames(model: DeclModel) {
        let ident = match (model) {
            case OfStruct(structModel) => structModel.decl.identifier
            case OfEnum(enumModel) => enumModel.decl.identifier
        }
        prefix = "FJ_NAME_${stripBackquotes(ident.value)}_"
    }

    func of(key: String): Token {
        for ((ident, name) in names where name == key) {
            return ident
        }
        let ident = Token(TokenKind.IDENTIFIER, "${prefix}${names.size}")
        names.add((ident, key))
        ident
    }

    func declarations(): Tokens {
        var declared = Tokens()
        for ((ident, key) in names) {
            let literal = Token(TokenKind.STRING_LITERAL, key)
            declared += quote(
                private let $ident = FjName($literal)
            )
        }
        declared
    }
}

private func structToJson(model: StructModel, names: KeyNames): Tokens {
    if (model.transparent) {
        let ident = model.fields[0].ident
        return quote(this.$ident.toJson(w))
    }

    var body = quote(w.beginObject())
    if (let Some((tag, value)) <- model.tag) {
        let name = names.of(tag)
        let literal = Token(TokenKind.STRING_LITERAL, value)
        body += quote(
            w.name($name)
            w.string($literal)
        )
    }
    for (field in model.fields) {
        let ident = field.ident
        body += fieldToJson(field, quote(this.$ident), names)
    }
    body + quote(
        w.endObject()
    )
}

/**
 * `None` of an optional field is `null`, unless `skipNone` leaves the key out. A `?Nullable<T>`
 * writes its `Some(Null)` as `null` either way.
 */
private func fieldToJson(field: DerivedField, value: Tokens, names: KeyNames): Tokens {
    let name = names.of(field.wireName)
    if (field.skipNone && field.shape.isOptional) {
        quote(
            if (let Some(present) <- $value) {
                w.name($name)
                present.toJson(w)
            }
        )
    } else {
        quote(
            w.name($name)
            $value.toJson(w)
        )
    }
}

private func scalarEnumToJson(model: EnumModel, isInteger: Bool, other: ?DerivedVariant): Tokens {
    var cases = Tokens()
    for (variant in model.variants) {
        let ident = variant.ident
        let literal = variant.value.literal
        cases += if (isInteger) {
            quote(
                case $ident => w.int64($literal)
            )
        } else {
            quote(
                case $ident => w.string($literal)
            )
        }
    }
    if (let Some(o) <- other) {
        let ident = o.ident
        cases += quote(
            case $ident(payload) => payload.toJson(w)
        )
    }

    quote(
        match (this) {
            $cases
        }
    )
}

/**
 * A variant is its payload alone, or an array of its payloads when it has several.
 */
private func untaggedEnumToJson(model: EnumModel): Tokens {
    var cases = Tokens()
    for (variant in model.variants) {
        let ident = variant.ident
        if (variant.payloadTypes.size == 1) {
            cases += quote(
                case $ident(payload) => payload.toJson(w)
            )
            continue
        }

        let bindings = variant.payloadBindings()
        var items = Tokens()
        for (binding in bindings) {
            items += quote(
                $binding.toJson(w)
            )
        }
        let pattern = commaSeparated(bindings)
        cases += quote(
            case $ident($pattern) =>
                w.beginArray()
                $items
                w.endArray()
        )
    }

    quote(
        match (this) {
            $cases
        }
    )
}

/**
 * The tag first, then the payloads as the fields beside it.
 */
private func taggedEnumToJson(model: EnumModel, tag: String, names: KeyNames): Tokens {
    let tagName = names.of(tag)
    var cases = Tokens()
    for (variant in model.variants) {
        let ident = variant.ident
        let literal = variant.value.literal
        let bindings = variant.payloadBindings()
        var fields = Tokens()
        for ((i, field) in variant.payloadFields |> enumerate) {
            fields += fieldToJson(field, bindings[i], names)
        }
        let pattern = if (bindings.size == 0) {
            quote($ident)
        } else {
            let payload = commaSeparated(bindings)
            quote($ident($payload))
        }
        cases += quote(
            case $pattern =>
                w.beginObject()
                w.name($tagName)
                w.string($literal)
                $fields
                w.endObject()
        )
    }

    quote(
        match (this) {
            $cases
        }
    )
}
