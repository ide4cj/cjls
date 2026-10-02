macro package stdxx.deriving

import std.ast.*
import std.collection.*

/*
 * `ToToml`: a value written straight into an `FtWriter`. Where TOML differs from JSON the
 * derivation says so when it expands, not a writer when it runs: a `Nullable` is an error, as
 * TOML has no `null`, and a `None` is left out whatever `skipNone` says.
 */

/**
 * A codec derivation for TOML: `derive` of the model, nothing when the model or the check that it
 * holds no `null` reported a mistake - once, however many TOML derivations are asked for.
 */
func serdeToml(context: DeriveContext, derive: (DeclModel) -> Tokens): Tokens {
    serde(context) {
        model => if (context.memo<Bool>("toml") {=> holdsNoNull(model)}) {
            derive(model)
        } else {
            Tokens()
        }
    }
}

/** Whether no field or payload is a `Nullable`, reported where one is. */
private func holdsNoNull(model: DeclModel): Bool {
    let (fields, payloadTypes) = match (model) {
        case OfStruct(structModel) => (structModel.fields, Array<(Token, Tokens)>())
        case OfEnum(enumModel) =>
            let fields = ArrayList<DerivedField>()
            let payloadTypes = ArrayList<(Token, Tokens)>()
            for (variant in enumModel.variants) {
                fields.add(all: variant.payloadFields)
                for (payloadType in variant.payloadTypes) {
                    payloadTypes.add((variant.ident, payloadType))
                }
            }
            (fields.toArray(), payloadTypes.toArray())
    }
    for (field in fields where isNullable(field.innerType)) {
        report(field.ident, "TOML has no `null`: a `Nullable` has nothing to be written as",
            "declare it `?T`, left out when `None`")
        return false
    }
    for ((ident, payloadType) in payloadTypes where isNullable(payloadType)) {
        report(ident, "TOML has no `null`: a `Nullable` payload has nothing to be written as",
            "carry `T`, and a variant without it")
        return false
    }
    true
}

private func isNullable(tokens: Tokens): Bool {
    tokens.size > 0 && tokens[0].value == "Nullable"
}

func deriveToToml(model: DeclModel): Tokens {
    let (decl, body, shape) = match (model) {
        case OfStruct(structModel) => (structModel.decl, structToToml(structModel), structShape(structModel))
        case OfEnum(enumModel) =>
            let (body, shape) = match (enumModel.shape) {
                case Scalar(isInteger, other) => (scalarEnumToToml(enumModel, isInteger, other), quote(FtShape.Inline))
                case Untagged => untaggedEnumToToml(enumModel)
                case Tagged(tag) => (taggedEnumToToml(enumModel, tag), quote(FtShape.Table))
            }
            (enumModel.decl, body, shape)
    }

    extensionOf(
        decl,
        quote(ToToml),
        {_ => "ToToml"},
        quote(
            public func toToml(w: FtWriter): Unit {
                $body
            }

            public prop tomlShape: FtShape {
                get() {
                    $shape
                }
            }
        )
    )
}

private func structShape(model: StructModel): Tokens {
    if (model.transparent) {
        let ident = model.fields[0].ident
        quote(this.$ident.tomlShape)
    } else {
        quote(FtShape.Table)
    }
}

private func structToToml(model: StructModel): Tokens {
    if (model.transparent) {
        let ident = model.fields[0].ident
        return quote(this.$ident.toToml(w))
    }

    var body = quote(w.beginTable())
    if (let Some((tag, value)) <- model.tag) {
        body += tagToToml(tag, Token(TokenKind.STRING_LITERAL, value))
    }
    body += fieldsToToml(model.fields.map {field => (field, quote(this.$(field.ident)))})
    body + quote(
        w.endTable()
    )
}

private func tagToToml(tag: String, literal: Tokens): Tokens {
    let name = Token(TokenKind.STRING_LITERAL, tag)
    quote(
        w.key($name)
        w.string($literal)
    )
}

private func tagToToml(tag: String, literal: Token): Tokens {
    tagToToml(tag, Tokens(literal))
}

/**
 * The fields in the order TOML wants: those written on their key's line first, then the tables
 * and arrays of tables under their headers. `None` is written in neither.
 */
private func fieldsToToml(fields: Array<(DerivedField, Tokens)>): Tokens {
    var inline = Tokens()
    var block = Tokens()
    for ((field, value) in fields) {
        let name = field.wireLiteral
        inline += quote(
            if (!$value.tomlShape.isBlock && !$value.tomlShape.isOmitted) {
                w.key($name)
                $value.toToml(w)
            }
        )
        block += quote(
            if ($value.tomlShape.isBlock) {
                w.key($name)
                $value.toToml(w)
            }
        )
    }
    inline + block
}

private func scalarEnumToToml(model: EnumModel, isInteger: Bool, other: ?DerivedVariant): Tokens {
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
            case $ident(payload) => payload.toToml(w)
        )
    }

    quote(
        match (this) {
            $cases
        }
    )
}

/**
 * A variant is its payload alone, or an array of its payloads when it has several; its shape is
 * its payload's, so a variant holding a table is written under a header.
 */
private func untaggedEnumToToml(model: EnumModel): (Tokens, Tokens) {
    var cases = Tokens()
    var shapes = Tokens()
    for (variant in model.variants) {
        let ident = variant.ident
        if (variant.payloadTypes.size == 1) {
            cases += quote(
                case $ident(payload) => payload.toToml(w)
            )
            shapes += quote(
                case $ident(payload) => payload.tomlShape
            )
            continue
        }

        let bindings = variant.payloadBindings()
        var items = Tokens()
        for (binding in bindings) {
            items += quote(
                $binding.toToml(w)
            )
        }
        let pattern = commaSeparated(bindings)
        cases += quote(
            case $ident($pattern) =>
                w.beginArray()
                $items
                w.endArray()
        )
        let wildcards = commaSeparated(bindings.map {_ => Tokens(Token(TokenKind.WILDCARD, "_"))})
        shapes += quote(
            case $ident($wildcards) => FtShape.Inline
        )
    }

    (quote(
        match (this) {
            $cases
        }
    ), quote(
        match (this) {
            $shapes
        }
    ))
}

/** A table: the tag, then the payloads as the keys beside it. */
private func taggedEnumToToml(model: EnumModel, tag: String): Tokens {
    var cases = Tokens()
    for (variant in model.variants) {
        let ident = variant.ident
        let bindings = variant.payloadBindings()
        let fields = fieldsToToml(Array(variant.payloadFields.size) {i => (variant.payloadFields[i], bindings[i])})
        let pattern = if (bindings.size == 0) {
            quote($ident)
        } else {
            let payload = commaSeparated(bindings)
            quote($ident($payload))
        }
        let tagged = tagToToml(tag, variant.value.literal)
        cases += quote(
            case $pattern =>
                w.beginTable()
                $tagged
                $fields
                w.endTable()
        )
    }

    quote(
        match (this) {
            $cases
        }
    )
}
