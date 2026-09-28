package stdxx

import std.deriving.*
import stdxx.deriving.*
import fjson.*

// The fixtures of `deriving_json_test.cj`, which also pins what a user of `@DeriveExt[ToJson,
// FromJson]` has to import: `fjson.*` and `stdxx.deriving.*`, plus `std.deriving.*` for `@Derive`.

@DeriveExt[ToJson, FromJson]
struct DerivedPosition {
    DerivedPosition(let line!: Int64, let character!: Int64) {}
}

@DeriveExt[ToJson, FromJson]
struct DerivedShapes {
    DerivedShapes(
        let required!: String,
        let nullable!: Nullable<String>,
        let optional!: ?String = None,
        let optionalNullable!: ?Nullable<String> = None
    ) {}
}

@DeriveExt[ToJson, FromJson]
@Serde[skipNone]
struct DerivedSkipped {
    DerivedSkipped(
        let required!: String,
        let optional!: ?String = None,
        let optionalNullable!: ?Nullable<String> = None
    ) {}
}

@DeriveExt[ToJson, FromJson]
struct DerivedRenamedAndSkipped {
    DerivedRenamedAndSkipped(@Serde[rename: "textDocument", skipNone] let document!: ?String = None) {}
}

@DeriveExt[ToJson, FromJson]
struct DerivedPartlySkipped {
    DerivedPartlySkipped(
        @Serde[skipNone] let skipped!: ?String = None,
        let kept!: ?String = None
    ) {}
}

@DeriveExt[ToJson, FromJson]
@Serde[skipNone]
public struct DerivedPublicSkipped {
    public DerivedPublicSkipped(
        public let required!: String,
        public let optional!: ?String = None
    ) {}
}

@DeriveExt[ToJson, FromJson]
struct DerivedNames {
    DerivedNames(
        @Serde[rename: "textDocument"] let document!: String,
        let `type`!: String
    ) {}
}

@DeriveExt[ToJson, FromJson]
struct DerivedBox<T> {
    DerivedBox(let value!: T) {}
}

@DeriveExt[ToJson, FromJson]
struct DerivedPositional {
    DerivedPositional(let x: Int64, let y: Int64) {}
}

@DeriveExt[ToJson, FromJson]
@Derive[ToString]
struct DerivedAndDescribed {
    DerivedAndDescribed(let name!: String) {}
}

/**
 * An open enumeration: a newtype with constants, the marker between the two derives.
 */
@DeriveExt[ToJson, FromJson]
@Serde[transparent]
@Derive[Equatable, Hashable]
public struct DerivedOpenCode {
    public const DerivedOpenCode(public let value: Int32) {}

    public static const PARSE_ERROR: DerivedOpenCode = DerivedOpenCode(-32700)
}

@DeriveExt[ToJson, FromJson]
@Serde[tag: "kind", rename: "create", skipNone]
struct DerivedCreateFile {
    DerivedCreateFile(let uri!: String, let overwrite!: ?Bool = None) {}
}

@DeriveExt[ToJson, FromJson]
@Serde[tag: "kind", rename: "delete", skipNone]
struct DerivedDeleteFile {
    DerivedDeleteFile(let uri!: String, let recursive!: ?Bool = None) {}
}

@DeriveExt[ToJson, FromJson]
@Serde[tag: "kind"]
struct DerivedRenameFile {
    DerivedRenameFile(let uri!: String) {}
}

@DeriveExt[ToJson, FromJson]
@Serde[untagged]
enum DerivedFileOperation {
    | Create(DerivedCreateFile)
    | Delete(DerivedDeleteFile)
}

@DeriveExt[ToJson, FromJson]
@Serde[transparent]
struct DerivedOpenUnsigned {
    DerivedOpenUnsigned(let value: UInt32) {}
}

@DeriveExt[ToJson, FromJson]
@Serde[transparent]
struct DerivedOpenKind {
    DerivedOpenKind(let `value`!: String) {}
}

@DeriveExt[ToJson, FromJson]
@Derive[Equatable]
enum DerivedBaseTypes {
    | @Serde[rename: "URI"]
    Uri
    | @Serde[rename: "integer"]
    Numeric
    | Boolean
}

@DeriveExt[ToJson, FromJson]
@Derive[Equatable]
enum DerivedSeverity {
    | @Serde[value: 1]
    Fatal
    | @Serde[value: 2]
    Warn
}

/**
 * A closed enumeration open to values it does not know; `Equatable` compares the payload too.
 */
@DeriveExt[ToJson, FromJson]
@Derive[Equatable]
enum DerivedSymbolKind {
    | @Serde[value: 1]
    File
    | @Serde[value: 2]
    Module
    | @Serde[other]
    Unknown(UInt32)
}

@DeriveExt[ToJson, FromJson]
@Derive[Equatable]
enum DerivedMarkupKind {
    | @Serde[rename: "plaintext"]
    PlainText
    | @Serde[other]
    Unknown(String)
}

@DeriveExt[ToJson, FromJson]
@Derive[Equatable]
enum DerivedErrorCode {
    | @Serde[value: -32700]
    ParseError
    | @Serde[value: -32601]
    MethodNotFound
    | @Serde[value: 1]
    Custom
}

@DeriveExt[ToJson, FromJson]
@Serde[untagged]
@Derive[Equatable]
enum DerivedNarrowOrWide {
    | Narrow(Int32)
    | Wide(Int64)
}

@DeriveExt[ToJson, FromJson]
@Serde[tag: "kind", skipNone]
@Derive[Equatable]
enum DerivedTaggedPayload {
    | @Serde[rename: "note", payload: ["text", "detail"]]
    Note(String, ?String)
}

@DeriveExt[ToJson, FromJson]
@Serde[untagged]
@Derive[Equatable]
enum DerivedScalarOrList {
    | Single(String)
    | Many(Array<String>)
}

@DeriveExt[ToJson, FromJson]
@Serde[untagged]
@Derive[Equatable]
enum DerivedOneOrMany<T> {
    | One(T)
    | Several(Array<T>)
}

@DeriveExt[ToJson, FromJson]
@Serde[tag: "kind"]
@Derive[Equatable]
enum DerivedShape {
    | @Serde[rename: "circle", payload: ["radius"]]
    Circle(Int64)
    | @Serde[rename: "rect", payload: ["width", "height"]]
    Rect(Int64, Int64)
    | @Serde[rename: "point"]
    Point
}
