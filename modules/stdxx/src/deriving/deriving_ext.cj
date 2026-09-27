macro package stdxx.deriving

import std.ast.*
import std.collection.*

const DERIVE_EXT_MACRO = "DeriveExt"

/**
 * One interface `@DeriveExt` implements: its name, the markers it reads, and what it generates.
 */
struct Derivation {
    Derivation(let name!: String, let markers!: Array<String>, let derive!: (DeriveContext) -> Tokens) {}
}

/** What `@DeriveExt` can derive. A new derivation is a line here and a function of the context. */
let DERIVATIONS: Array<Derivation> = [
    Derivation(name: "ToJson", markers: [SERDE_MARKER], derive: {context => serde(context, deriveToJson)}),
    Derivation(name: "FromJson", markers: [SERDE_MARKER], derive: {context => serde(context, deriveFromJson)}),
    Derivation(name: "ToToml", markers: [SERDE_MARKER], derive: {context => serdeToml(context, deriveToToml)}),
    Derivation(name: "FromToml", markers: [SERDE_MARKER], derive: {context => serdeToml(context, deriveFromToml)})
]

/**
 * Generates the interface implementations named in the attributes as extensions of the annotated
 * declaration - what `std.deriving`'s `@Derive` cannot be taught, as its registry is `protected` to
 * `std`. serde's derives are its first: `ToJson` and `FromJson` are serde's `Serialize` and
 * `Deserialize`, `@Serde` its `#[serde(...)]`:
 * ```cangjie
 * @DeriveExt[ToJson, FromJson]
 * struct Position {
 *     Position(let line!: UInt32, let character!: UInt32) {}
 * }
 * ```
 *
 * The declaration is read once into its `DeclShape`, and its markers once, whatever is derived
 * from them; a marker none of the requested derivations reads is an error.
 */
public macro DeriveExt(attrs: Tokens, input: Tokens): Tokens {
    let requested = ArrayList<Derivation>()
    for (attr in attrs) {
        if (attr.kind != TokenKind.IDENTIFIER) {
            continue
        }
        match (DERIVATIONS.filter {derivation => derivation.name == attr.value}.first) {
            case Some(derivation) => requested.add(derivation)
            case None => diagReport(
                DiagReportLevel.ERROR,
                Tokens(attr),
                "`@DeriveExt` cannot derive `${attr.value}`",
                "it knows: ${String.join(DERIVATIONS.map {derivation => derivation.name}, delimiter: ", ")}"
            )
        }
    }

    if (requested.isEmpty()) {
        return input
    }

    let names = String.join(requested.toArray().map {derivation => derivation.name}, delimiter: ", ")
    let markers = Markers(knownMarkers())
    let read = ArrayList<String>()
    for (derivation in requested) {
        read.add(all: derivation.markers)
    }
    markers.reportUnread(read.toArray(), names)

    let shape = DeclShape.of(parseDecl(input), names) ?? return input
    let context = DeriveContext(shape, markers, names)
    var extensions = Tokens()
    for (derivation in requested) {
        extensions += derivation.derive(context)
    }

    input + extensions
}

private func knownMarkers(): Array<String> {
    let markers = ArrayList<String>()
    for (derivation in DERIVATIONS) {
        for (marker in derivation.markers where !markers.contains(marker)) {
            markers.add(marker)
        }
    }
    markers.toArray()
}

/**
 * What every derivation of one declaration is given: its shape, its markers, and a place to keep
 * what several of them work out from those alike - serde's model, built once however many of
 * serde's derivations are asked for, so a mistake in it is reported once.
 */
class DeriveContext {
    private let memos = HashMap<String, Any>()

    DeriveContext(let shape: DeclShape, let markers: Markers, let names: String) {}

    /** `compute()`, the first time `key` is asked for; what it gave then, every time after. */
    func memo<T>(key: String, compute: () -> T): T {
        if (let Some(memo) <- memos.get(key)) {
            if (let Some(value) <- (memo as T)) {
                return value
            }
        }
        let value = compute()
        memos[key] = value
        value
    }
}
