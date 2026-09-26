package lsp_codegen

import std.deriving.*
import stdx.serialization.serialization.*
import stdxx.IntegerOrString
import stdxx.serialization.*
import stdxx.deriving.*

/**
 * Mirrors https://microsoft.github.io/language-server-protocol/specifications/lsp/3.18/metaModel/metaModel.ts
 */
@DeriveExt[Serializable]
struct MetaModel {
    MetaModel(
        let metaData!: MetaData,
        let requests!: Array<Request>,
        let notifications!: Array<Notification>,
        let structures!: Array<Structure>,
        let enumerations!: Array<Enumeration>,
        let typeAliases!: Array<TypeAlias>
    ) {}
}

@DeriveExt[Serializable]
struct MetaData {
    MetaData(let version!: String) {}
}

@DeriveExt[Serializable]
@Serde[skipNone]
struct Request {
    Request(
        let method!: String,
        let typeName!: ?String = None,
        let params!: ?OneOrMany<Type> = None,
        let result!: Type,
        let partialResult!: ?Type = None,
        let errorData!: ?Type = None,

        /**
         * Only when it differs from `method`.
         */
        let registrationMethod!: ?String = None,
        let registrationOptions!: ?Type = None,
        let messageDirection!: MessageDirection,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None,
        let clientCapability!: ?String = None,
        let serverCapability!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@Serde[skipNone]
struct Notification {
    Notification(
        let method!: String,
        let typeName!: ?String = None,
        let params!: ?OneOrMany<Type> = None,

        /**
         * Only when it differs from `method`.
         */
        let registrationMethod!: ?String = None,
        let registrationOptions!: ?Type = None,
        let messageDirection!: MessageDirection,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None,
        let clientCapability!: ?String = None,
        let serverCapability!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@Serde[skipNone]
struct Structure {
    Structure(
        let name!: String,
        let extends!: ?Array<Type> = None,
        let mixins!: ?Array<Type> = None,
        let properties!: Array<Property>,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@Serde[skipNone]
struct Enumeration {
    Enumeration(
        let name!: String,
        @Serde[rename: "type"] let enumerationType!: EnumerationType,
        let values!: Array<EnumerationEntry>,

        /**
         * Whether values outside `values` are allowed; absent means they are not.
         */
        let supportsCustomValues!: ?Bool = None,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@Serde[skipNone]
struct TypeAlias {
    TypeAlias(
        let name!: String,
        @Serde[rename: "type"] let typeAliasType!: Type,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
enum BaseTypes {
    | @Serde[rename: "URI"]
    Uri
    | DocumentUri
    | @Serde[rename: "integer"]
    Integer
    | @Serde[rename: "uinteger"]
    UInteger
    | @Serde[rename: "decimal"]
    Decimal
    | RegExp
    | @Serde[rename: "string"]
    String
    | @Serde[rename: "boolean"]
    Boolean
    | @Serde[rename: "null"]
    Null
}

/**
 * Its `toString`, `MessageDirection.Both`, is how the generated code names the variant too.
 */
@DeriveExt[Serializable]
@Derive[ToString]
enum MessageDirection {
    | @Serde[rename: "clientToServer"]
    ClientToServer
    | @Serde[rename: "serverToClient"]
    ServerToClient
    | @Serde[rename: "both"]
    Both
}

@DeriveExt[Serializable]
enum MapKeyName {
    | @Serde[rename: "URI"]
    Uri
    | DocumentUri
    | @Serde[rename: "string"]
    String
    | @Serde[rename: "integer"]
    Integer
}

/**
 * A reference here resolves to a `string` or an `integer`: `ChangeAnnotationIdentifier`.
 */
@DeriveExt[Serializable]
@Serde[tag: "kind"]
enum MapKeyType {
    | @Serde[rename: "base", payload: ["name"]]
    Base(MapKeyName)
    | @Serde[rename: "reference", payload: ["name"]]
    Reference(String)
}

@DeriveExt[Serializable]
@Serde[tag: "kind"]
enum Type {
    | @Serde[rename: "base", payload: ["name"]]
    Base(BaseTypes)

    /**
     * To a `Structure`, an `Enumeration` or a `TypeAlias` of the same meta model.
     */
    | @Serde[rename: "reference", payload: ["name"]]
    Reference(String)

    | @Serde[rename: "array", payload: ["element"]]
    Array(Type)

    | @Serde[rename: "map", payload: ["key", "value"]]
    Map(MapKeyType, Type)

    | @Serde[rename: "and", payload: ["items"]]
    And(Array<Type>)

    | @Serde[rename: "or", payload: ["items"]]
    Or(Array<Type>)

    | @Serde[rename: "tuple", payload: ["items"]]
    Tuple(Array<Type>)

    /**
     * An anonymous structure: `property: { start: uinteger; end: uinteger; }`.
     */
    | @Serde[rename: "literal", payload: ["value"]]
    Literal(StructureLiteral)

    | @Serde[rename: "stringLiteral", payload: ["value"]]
    StringLiteral(String)

    | @Serde[rename: "integerLiteral", payload: ["value"]]
    IntegerLiteral(Int64)

    | @Serde[rename: "booleanLiteral", payload: ["value"]]
    BooleanLiteral(Bool)
}

@DeriveExt[Serializable]
@Serde[skipNone]
struct StructureLiteral {
    StructureLiteral(
        let properties!: Array<Property>,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@Serde[skipNone]
struct Property {
    Property(
        let name!: String,
        @Serde[rename: "type"] let propertyType!: Type,
        let optional!: ?Bool = None,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@Serde[untagged]
enum OneOrMany<T> {
    | One(T)
    | Many(Array<T>)
}

@DeriveExt[Serializable]
@Serde[skipNone]
struct EnumerationEntry {
    EnumerationEntry(
        let name!: String,
        let value!: IntegerOrString,
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: ?Bool = None,
        let deprecated!: ?String = None
    ) {}
}

@DeriveExt[Serializable]
@Serde[tag: "kind", value: "base"]
struct EnumerationType {
    EnumerationType(let name!: EnumerationBaseType) {}
}

@DeriveExt[Serializable]
enum EnumerationBaseType {
    | @Serde[rename: "string"]
    String
    | @Serde[rename: "integer"]
    Integer
    | @Serde[rename: "uinteger"]
    UInteger
}
