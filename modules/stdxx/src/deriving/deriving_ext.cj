macro package stdxx.deriving

import std.ast.*
import std.collection.*

const DERIVE_EXT_MACRO = "DeriveExt"

/**
 * Generates the interface implementations named in the attributes as extensions of the annotated
 * declaration, as serde's derives do - `ToJson` and `FromJson` are its `Serialize` and
 * `Deserialize`, `@Serde` its `#[serde(...)]`:
 * ```cangjie
 * @DeriveExt[ToJson, FromJson]
 * struct Position {
 *     Position(let line!: UInt32, let character!: UInt32) {}
 * }
 * ```
 *
 * The declaration and its markers are read once, whatever is derived from them, so every derivation
 * follows the same rules and a mistake is reported once.
 */
public macro DeriveExt(attrs: Tokens, input: Tokens): Tokens {
    let deriveFns = ArrayList<DeriveFunc>()
    let names = ArrayList<String>()
    for (attr in attrs) {
        if (attr.kind != TokenKind.IDENTIFIER) {
            continue
        }
        match (DeriveExtKind.nameOf(attr.value)) {
            case Some(kind) =>
                deriveFns.add(kind.deriveFn)
                names.add(attr.value)
            case None => diagReport(
                DiagReportLevel.ERROR,
                Tokens(attr),
                "`@DeriveExt` cannot derive `${attr.value}`",
                "it knows: ${DeriveExtKind.known()}"
            )
        }
    }

    if (deriveFns.isEmpty()) {
        return input
    }

    let decl = parseDecl(input)
    let model = modelOf(decl, String.join(names.toArray(), delimiter: ", ")) ?? return input

    var extensions = Tokens()
    for (deriveFn in deriveFns) {
        extensions += deriveFn(model)
    }

    input + extensions
}

enum DeriveExtKind {
    | Serializable
    | ToJson
    | FromJson

    static func nameOf(name: String): ?DeriveExtKind {
        match (name) {
            case "Serializable" => Serializable
            case "ToJson" => ToJson
            case "FromJson" => FromJson
            case _ => None
        }
    }

    static func known(): String {
        "ToJson, FromJson, Serializable"
    }

    prop deriveFn: DeriveFunc {
        get() {
            match (this) {
                case Serializable => deriveSerializable
                case ToJson => deriveToJson
                case FromJson => deriveFromJson
            }
        }
    }
}

type DeriveFunc = (model: DeclModel) -> Tokens
