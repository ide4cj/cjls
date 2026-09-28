macro package stdxx.deriving

import std.ast.*
import std.collection.*

/*
 * Markers: the attribute macros that configure a derivation from inside the declaration, one per
 * type, field or variant - serde's `#[serde(...)]`, here `@Serde[...]`. A marker expands to
 * nothing and hands its options to the enclosing `@DeriveExt` as a message, which reads every
 * marker it knows of generically; what the options mean is the business of the derivations that
 * read that marker.
 */

const ITEM_IDENT = "ident"
const ITEM_ON_TYPE = "onType"
const ITEM_AT = "at"

/**
 * Where a marker sits, which is what decides the options it may carry. Read off the declaration it
 * was given: a type opens with its keyword, a field with `let` or `var`, and what is left in an
 * enum body is a constructor.
 */
enum MarkerPosition {
    | OnType
    | OnField
    | OnVariant

    prop isType: Bool {
        get() {
            match (this) {
                case OnType => true
                case _ => false
            }
        }
    }

    prop name: String {
        get() {
            match (this) {
                case OnType => "a type"
                case OnField => "a field"
                case OnVariant => "an enum variant"
            }
        }
    }
}

/**
 * What every marker does first, whatever its options: says it is inside `@DeriveExt`, and records
 * what it sits on and where it was written.
 *
 * @return where it sits
 */
func beginMarker(marker: String, attrs: Tokens, input: Tokens): MarkerPosition {
    assertParentContext(DERIVE_EXT_MACRO)

    let position = markerPositionOf(input)
    let ident = identOf(input) ?? Token(TokenKind.IDENTIFIER, "")
    setItem(ITEM_IDENT, ident.value)
    setItem(ITEM_ON_TYPE, position.isType)
    let at = if (attrs.size > 0) { attrs } else { ident.toTokens() }
    setItem(ITEM_AT, at)

    position
}

private func markerPositionOf(input: Tokens): MarkerPosition {
    let head = headTokenOf(input) ?? return OnVariant

    match (head.kind) {
        case TokenKind.STRUCT | TokenKind.CLASS | TokenKind.ENUM => OnType
        case TokenKind.LET | TokenKind.VAR => OnField
        case _ => OnVariant
    }
}

/**
 * The messages of every marker inside one `@DeriveExt`: for each marker, the one on the type and
 * those on its fields or variants, by identifier.
 */
class Markers {
    private let onType = HashMap<String, MacroMessage>()
    private let onMembers = HashMap<String, HashMap<String, MacroMessage>>()
    private let written = ArrayList<(String, Tokens)>()

    /** Reads the messages of these markers. */
    init(markers: Array<String>) {
        for (marker in markers) {
            let members = HashMap<String, MacroMessage>()
            for (message in getChildMessages(marker)) {
                written.add((marker, message.getTokens(ITEM_AT)))
                if (message.getBool(ITEM_ON_TYPE)) {
                    onType[marker] = message
                } else {
                    members[message.getString(ITEM_IDENT)] = message
                }
            }
            onMembers[marker] = members
        }
    }

    func ofType(marker: String): ?MacroMessage {
        onType.get(marker)
    }

    func ofMember(marker: String, ident: String): ?MacroMessage {
        match (onMembers.get(marker)) {
            case Some(members) => members.get(ident)
            case None => None
        }
    }

    /**
     * Reports every marker written that none of `read` is: one that configures nothing asked for,
     * `@Serde` on a type deriving nothing of serde's.
     */
    func reportUnread(read: Array<String>, derive: String): Unit {
        for ((marker, at) in written where !read.contains(marker)) {
            diagReport(
                DiagReportLevel.ERROR,
                at,
                "`@${marker}` configures nothing `@DeriveExt[${derive}]` derives",
                "drop it, or derive what reads it"
            )
        }
    }
}
