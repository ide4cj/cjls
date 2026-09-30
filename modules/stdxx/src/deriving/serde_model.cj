macro package stdxx.deriving

import std.ast.*
import std.collection.*

/*
 * What a declaration is on the wire, worked out once from its shape and its `@Serde` markers,
 * whatever serde derivations `@DeriveExt` is asked for: every one is a function of the model, so
 * the rules - and the diagnostics - are the same for all of them, and reported once.
 */

/**
 * A serde derivation of the context's declaration: `derive` of its model, nothing when the model
 * reported a mistake.
 */
func serde(context: DeriveContext, derive: (DeclModel) -> Tokens): Tokens {
    let model = context.memo<?DeclModel>(SERDE_MARKER) {=> modelOf(context.shape, context.markers, context.names)}
    match (model) {
        case Some(m) => derive(m)
        case None => Tokens()
    }
}

enum DeclModel {
    | OfStruct(StructModel)
    | OfEnum(EnumModel)
}

struct StructModel {
    StructModel(
        let decl!: Decl,
        let fields!: Array<DerivedField>,
        /**
         * The tag field's name and this struct's value in it.
         */
        let tag!: ?(String, String),
        let transparent!: Bool
    ) {}
}

enum EnumShape {
    /**
     * No payloads: the variant is the value, integers or strings; `other` holds anything else.
     */
    | Scalar(Bool, ?DerivedVariant)

    /**
     * Payloads and no discriminator: whichever variant the value reads as.
     */
    | Untagged

    /**
     * The discriminator is this field of the object, the payloads the fields beside it.
     */
    | Tagged(String)
}

struct EnumModel {
    EnumModel(let decl!: EnumDecl, let variants!: Array<DerivedVariant>, let shape!: EnumShape, let skipNone!: Bool) {}
}

/**
 * How a field's declared type spells the two independent axes - may the key be absent, and may the
 * value be `null`.
 */
enum FieldShape {
    /**
     * `T`, `Nullable<T>` included: the key is always there. A `Nullable<T>` carries its own `null`.
     */
    | Required

    /**
     * `?T`: absent and `null` both read as `None`.
     */
    | Optional

    /**
     * `?Nullable<T>`: absent reads as `None` and `null` as `Some(Null)` - the one shape where the
     * two stay apart.
     */
    | OptionalNullable

    prop isOptional: Bool {
        get() {
            match (this) {
                case Required => false
                case _ => true
            }
        }
    }
}

/**
 * A primary constructor parameter seen as a field on the wire, or a payload of a tagged variant
 * seen as one.
 */
struct DerivedField {
    DerivedField(
        let ident!: Token,
        let wireName!: String,
        let isNamed!: Bool,
        let fieldType!: Tokens,
        /**
         * What is under the option of an optional field - `T` of `?T`, `Nullable<T>` of
         * `?Nullable<T>` - and the type itself for a required one.
         */
        let innerType!: Tokens,
        let shape!: FieldShape,
        let skipNone!: Bool
    ) {}

    prop wireLiteral: Token {
        get() {
            Token(TokenKind.STRING_LITERAL, wireName)
        }
    }

    /**
     * The local a decoder reads the field into, `?T` whatever its shape.
     */
    prop local: Token {
        get() {
            Token(TokenKind.IDENTIFIER, "f_${stripBackquotes(ident.value)}")
        }
    }
}

/**
 * A variant of an enum, seen as one alternative on the wire.
 */
struct DerivedVariant {
    DerivedVariant(
        let ident!: Token,
        let value!: WireValue,
        let payloadTypes!: Array<Tokens>,
        /**
         * The payloads as fields, named by `payload:` - only for a tagged enum.
         */
        let payloadFields!: Array<DerivedField>
    ) {}

    /**
     * `p0, p1, ...` - the names the generated `match` binds this variant's payload to.
     */
    func payloadBindings(): Array<Tokens> {
        Array(payloadTypes.size) {i => Tokens(Token(TokenKind.IDENTIFIER, "p${i}"))}
    }
}

/**
 * @return `None` when a diagnostic was reported
 */
func modelOf(shape: DeclShape, markers: Markers, derive: String): ?DeclModel {
    let (typeOptions, memberOptions) = serdeOptionsOf(markers)
    if (let enumDecl: EnumDecl <- shape.decl) {
        return enumModelOf(enumDecl, shape.variants, typeOptions, memberOptions).map {model => OfEnum(model)}
    }
    let fields = shape.fields ?? return reportNone(shape.decl,
        "`@DeriveExt[${derive}]` needs a primary constructor to read the fields from",
        "declare the fields as primary constructor parameters, or hand-write it")

    structModelOf(shape.decl, fields, typeOptions, memberOptions).map {model => OfStruct(model)}
}

private func reportNone<T>(decl: Decl, message: String, hint: String): ?T {
    report(decl, message, hint)
    None
}

private func reportNone<T>(ident: Token, message: String, hint: String): ?T {
    report(ident, message, hint)
    None
}

private func structModelOf(
    decl: Decl,
    declFields: Array<DeclField>,
    typeOptions: MarkerOptions,
    memberOptions: (String) -> MarkerOptions
): ?StructModel {
    let typeIdent = decl.identifier
    if (typeOptions.untagged) {
        return reportNone(typeIdent, "`untagged` applies to an enum", "a struct is always an object")
    }

    let fields = ArrayList<DerivedField>()
    for (declField in declFields) {
        let options = memberOptions(declField.ident.value)
        if (options.value.isSome()) {
            return reportNone(declField.ident, "`value` does not apply to a field", "name it on the wire with `rename`")
        }
        fields.add(fieldOf(declField, options, typeOptions.skipNone) ?? return None)
    }

    // two fields of one wire name would write the same key, and both read whichever value came last
    if (let Some((wireName, clash)) <- firstDuplicate(fields.map {field => (field.wireName, field.ident)}.toArray())) {
        return reportNone(clash, "two fields share the wire name \"${wireName}\"", "rename one of them")
    }

    if (typeOptions.transparent) {
        return transparentModelOf(decl, typeOptions, fields, memberOptions)
    }

    // the tag holds the struct's name - its `rename`, or its identifier as a variant's would
    let tag: ?(String, String) = match ((typeOptions.tag, typeOptions.rename)) {
        case (None, None) => None
        case (None, Some(_)) => return reportNone(typeIdent, "`rename` on a struct needs a `tag`",
            "name the field its name goes into, e.g. `tag: \"kind\"`")
        case (Some(tag), rename) =>
            for (field in fields where field.wireName == tag) {
                return reportNone(field.ident, "the tag \"${tag}\" is also the wire name of a field",
                    "drop the field - the tag is written in its place")
            }
            (tag, rename ?? stripBackquotes(typeIdent.value))
    }

    StructModel(decl: decl, fields: fields.toArray(), tag: tag, transparent: false)
}

/**
 * The one field has to be required: its name never reaches the wire, so neither does anything that
 * would tell an absent value from a present one.
 */
private func transparentModelOf(
    decl: Decl,
    typeOptions: MarkerOptions,
    fields: ArrayList<DerivedField>,
    memberOptions: (String) -> MarkerOptions
): ?StructModel {
    let typeIdent = decl.identifier
    if (fields.size != 1) {
        return reportNone(typeIdent, "`transparent` needs exactly one field", "`${typeIdent.value}` declares ${fields.size}")
    }
    if (typeOptions.skipNone || typeOptions.tag.isSome() || typeOptions.rename.isSome()) {
        return reportNone(typeIdent, "`transparent` takes no other option on the type",
            "the struct has no object of its own to tag or to omit keys from")
    }

    let field = fields[0]
    let options = memberOptions(field.ident.value)
    if (options.rename.isSome() || options.skipNone) {
        return reportNone(field.ident, "the field of a `transparent` struct takes no options",
            "its name never reaches the wire")
    }
    if (field.shape.isOptional) {
        return reportNone(field.ident, "the field of a `transparent` struct has to be required",
            "declare it as `${stripBackquotes(field.ident.value)}: T`, not `?T`")
    }

    StructModel(decl: decl, fields: fields.toArray(), tag: None, transparent: true)
}

private func fieldOf(declField: DeclField, options: MarkerOptions, skipNoneOnType: Bool): ?DerivedField {
    if (!declField.isMember) {
        diagReport(
            DiagReportLevel.ERROR,
            declField.tokens,
            "`@DeriveExt` needs every primary constructor parameter to declare a field",
            "prefix it with `let`, or hand-write the derivation"
        )
        return None
    }

    let (shape, innerType) = shapeOf(declField.fieldType)

    DerivedField(
        ident: declField.ident,
        wireName: options.rename ?? stripBackquotes(declField.ident.value),
        isNamed: declField.isNamed,
        fieldType: declField.fieldType,
        innerType: innerType,
        shape: shape,
        skipNone: skipNoneOnType || options.skipNone
    )
}

/**
 * The shape a type spells, and what is under its option.
 *
 * `Nullable<T>` under the option is the only inner type that changes what an absent key means, so
 * it is the only one worth looking at. The name is matched against the source, and nothing more is
 * knowable at expansion time: a field declared through an alias of it (`import stdxx.Nullable as
 * MaybeNull`, `?MaybeNull<T>`) reads as a plain optional, and an explicit `null` then collapses to
 * `None` instead of `Some(Null)`. Spell `Nullable` outright wherever the distinction matters.
 */
func shapeOf(tokens: Tokens): (FieldShape, Tokens) {
    if (tokens.size == 0) {
        return (Required, tokens)
    }

    let head = tokens[0]
    let inner = if (head.kind == TokenKind.QUEST) {
        tokens[1..tokens.size]
    } else if (head.kind == TokenKind.IDENTIFIER && head.value == "Option" && tokens.size > 3) {
        tokens[2..tokens.size - 1]
    } else {
        return (Required, tokens)
    }
    if (inner.size > 0 && inner[0].value == "Nullable") {
        (OptionalNullable, inner)
    } else {
        (Optional, inner)
    }
}

private func enumModelOf(
    decl: EnumDecl,
    declVariants: Array<DeclVariant>,
    typeOptions: MarkerOptions,
    variantOptions: (String) -> MarkerOptions
): ?EnumModel {
    if (typeOptions.transparent) {
        return reportNone(decl, "`transparent` does not apply to an enum", "it belongs on a struct or a class with one field")
    }
    if (typeOptions.rename.isSome()) {
        return reportNone(decl, "`rename` on an enum belongs on its variants", "move it onto the variant it names")
    }
    if (typeOptions.untagged && typeOptions.tag.isSome()) {
        return reportNone(decl, "an enum is either `untagged` or has a `tag`", "drop one of them")
    }

    let variants = ArrayList<DerivedVariant>()
    var other: ?DerivedVariant = None
    for (declVariant in declVariants) {
        let ident = declVariant.ident
        let options = variantOptions(ident.value)
        let payloadTypes = declVariant.payloadTypes

        if (let Some(value) <- options.value) {
            if (!value.isInteger) {
                return reportNone(ident, "a variant's string is its `rename`, not its `value`",
                    "spell it `rename: \"${value.text}\"`; `value` is for an integer")
            }
            if (options.rename.isSome()) {
                return reportNone(ident, "a variant takes a `rename` or a `value`, not both",
                    "it travels as one string or one integer")
            }
        }
        let wireValue = options.value ?? WireValue.ofString(options.rename ?? stripBackquotes(ident.value))
        let payloadFields = if (typeOptions.tag.isSome()) {
            if (options.payload.size != payloadTypes.size) {
                return reportNone(ident, "a tagged enum needs `payload:` to name every payload of a variant",
                    "`${ident.value}` carries ${payloadTypes.size} of them, `payload:` names ${options.payload.size}")
            }
            Array(payloadTypes.size) {
                i =>
                let (shape, innerType) = shapeOf(payloadTypes[i])
                DerivedField(
                    ident: Token(TokenKind.IDENTIFIER, "p${i}"),
                    wireName: options.payload[i],
                    isNamed: false,
                    fieldType: payloadTypes[i],
                    innerType: innerType,
                    shape: shape,
                    skipNone: typeOptions.skipNone
                )
            }
        } else {
            if (!options.payload.isEmpty()) {
                return reportNone(ident, "`payload` applies to a variant of a tagged enum",
                    "its payloads are fields of the object only beside a `tag`")
            }
            Array<DerivedField>()
        }
        let variant = DerivedVariant(ident: ident, value: wireValue, payloadTypes: payloadTypes,
            payloadFields: payloadFields)
        if (!options.other) {
            variants.add(variant)
            continue
        }

        if (other.isSome()) {
            return reportNone(ident, "an enum takes one `other` variant", "`${other.getOrThrow().ident.value}` already is")
        }
        if (options.value.isSome() || options.rename.isSome() || !options.payload.isEmpty()) {
            return reportNone(ident, "an `other` variant takes no `rename`, `value` or `payload`",
                "it has no value of its own - it holds whatever the wire carried")
        }
        if (payloadTypes.size != 1) {
            return reportNone(ident, "an `other` variant needs exactly one payload",
                "it is where the unrecognised value goes, e.g. `Unknown(Int32)`")
        }
        other = variant
    }

    if (variants.isEmpty()) {
        return reportNone(decl, "`@DeriveExt` needs at least one variant besides `other`", "there is nothing to recognise")
    }

    // two variants of one value would be indistinguishable, and the earlier one would answer for both
    if (let Some((_, clash)) <- firstDuplicate(variants.map {variant => (variant.value.text, variant.ident)}.toArray())) {
        return reportNone(clash, "two variants share the same value on the wire", "give one of them another `rename`")
    }

    let isScalar = variants.all {variant => variant.payloadTypes.isEmpty()}
    if (let Some(o) <- other) {
        if (typeOptions.tag.isSome() || !isScalar) {
            return reportNone(o.ident, "`other` applies only to an enum whose variants are plain values",
                "a tagged or an untagged enum has no single value to fall back on")
        }
    }

    let shape = match (typeOptions.tag) {
        case Some(tag) =>
            if (let Some(variant) <- variants.filter {variant => variant.value.isInteger}.first) {
                return reportNone(variant.ident, "a tagged enum needs a string on every variant",
                    "`${variant.ident.value}` asks for an integer, and the tag field holds a string")
            }
            Tagged(tag)
        case None where isScalar =>
            if (typeOptions.untagged) {
                return reportNone(decl, "`untagged` applies to an enum whose variants carry payloads",
                    "variants without one are the value itself already")
            }
            scalarShapeOf(decl, variants, other) ?? return None
        case None =>
            if (!typeOptions.untagged) {
                return reportNone(decl, "an enum with payloads needs `untagged` or a `tag`",
                    "`@Serde[untagged]` reads whichever variant the value reads as, `@Serde[tag: \"kind\"]` reads it by a field")
            }
            if (let Some(variant) <- variants.filter {variant => variant.payloadTypes.isEmpty()}.first) {
                return reportNone(variant.ident, "an untagged enum needs a payload on every variant",
                    "`${variant.ident.value}` carries none - make the enum tagged")
            }
            Untagged
    }

    EnumModel(decl: decl, variants: variants.toArray(), shape: shape, skipNone: typeOptions.skipNone)
}

private func scalarShapeOf(decl: EnumDecl, variants: ArrayList<DerivedVariant>, other: ?DerivedVariant): ?EnumShape {
    let isInteger = variants[0].value.isInteger
    if (let Some(variant) <- variants.filter {variant => variant.value.isInteger != isInteger}.first) {
        return reportNone(decl, "every value of an enum has to be of one kind",
            "`${variant.ident.value}` breaks the string/integer choice the other variants made")
    }
    if (let Some(o) <- other) {
        let payloadType = o.payloadTypes[0]
        if (isIntegerType(payloadType) != isInteger) {
            return reportNone(o.ident, "the payload of `other` has to be of the kind the values are",
                "the values are ${if (isInteger) { "integers" } else { "strings" }}, `${payloadType.toString()}` is not")
        }
    }

    Scalar(isInteger, other)
}

func isIntegerType(tokens: Tokens): Bool {
    if (tokens.size != 1) {
        return false
    }

    match (tokens[0].kind) {
        case TokenKind.INT8 | TokenKind.INT16 | TokenKind.INT32 | TokenKind.INT64 | TokenKind.INTNATIVE
            | TokenKind.UINT8 | TokenKind.UINT16 | TokenKind.UINT32 | TokenKind.UINT64 | TokenKind.UINTNATIVE => true
        case _ => false
    }
}
