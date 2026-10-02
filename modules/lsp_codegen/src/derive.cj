package lsp_codegen

import std.ast.*
import std.collection.*
import stdxx.IntegerOrString

enum DeriveIr {
    | Equatable
    | Hashable
    /**
     * `ToJson` and `FromJson`, configured by one `@Serde` marker.
     */
    | Json(SerdeTypeOptions)
}

struct SerdeTypeOptions <: ToTokens {
    SerdeTypeOptions(
        let transparent!: Bool = false,
        let untagged!: Bool = false,
        let skipNone!: Bool = false,
        let tag!: ?SerdeTag = None
    ) {}

    public func toTokens(): Tokens {
        let options = ArrayList<Tokens>()
        if (transparent) {
            options.add(quote(transparent))
        }
        if (untagged) {
            options.add(quote(untagged))
        }
        if (skipNone) {
            options.add(quote(skipNone))
        }
        if (let Some(t) <- tag) {
            options.add(quote(tag: $(t.field), rename: $(t.value)))
        }

        markerOf(options)
    }
}

struct SerdeTag {
    SerdeTag(let field!: String, let value!: String) {}
}

struct SerdeMemberOptions <: ToTokens {
    SerdeMemberOptions(let value!: ?IntegerOrString = None, let other!: Bool = false) {}

    public func toTokens(): Tokens {
        let options = ArrayList<Tokens>()
        // a variant's string is its `rename`, an integer its `value`
        match (value) {
            case Some(Integer(int)) =>
                let literal = int.toTokens()
                options.add(quote(value: $literal))
            case Some(String(str)) =>
                let literal = str.toTokens()
                options.add(quote(rename: $literal))
            case None => ()
        }
        if (other) {
            options.add(quote(other))
        }

        markerOf(options)
    }
}

private func markerOf(options: Iterable<Tokens>): Tokens {
    match (joined(options)) {
        case Some(joinedOptions) => quote(@Serde[$joinedOptions])
        case None => Tokens()
    }
}

/**
 * @note a function rather than `ToTokens` on `IntegerOrString`: this package can't extend an
 *       imported type with an imported interface, and implementing it in `stdxx` would link
 *       `std.ast` - and the compiler's parser under it - into the server.
 */
func literalOf(value: IntegerOrString): Tokens {
    match (value) {
        case Integer(int) => int.toTokens()
        case String(str) => str.toTokens()
    }
}

func serdeMarkerOf(options: ?SerdeMemberOptions): Tokens {
    options.map {it: SerdeMemberOptions => it.toTokens()} ?? Tokens()
}

extend CjEmitter {
    /**
     * The order is load-bearing: macros expand inside out and `@DeriveExt` appends to whatever
     * `@Derive` produced, so it has to be the outer one, with its type-level marker inside it.
     */
    func emitDerives(derives: Collection<DeriveIr>): Unit {
        let std = ArrayList<Tokens>()
        let ext = ArrayList<Tokens>()
        var typeMarker = Tokens()
        for (derive in derives) {
            match (derive) {
                case DeriveIr.Equatable => std.add(quote(Equatable))
                case DeriveIr.Hashable => std.add(quote(Hashable))
                case Json(options) =>
                    ext.add(quote(ToJson))
                    ext.add(quote(FromJson))
                    typeMarker = options.toTokens()
            }
        }

        if (let Some(names) <- joined(ext)) {
            emitln(quote(@DeriveExt[$names]))
        }
        if (typeMarker.size > 0) {
            emitln(typeMarker)
        }
        if (let Some(names) <- joined(std)) {
            emitln(quote(@Derive[$names]))
        }
    }
}

func joined(parts: Iterable<Tokens>): ?Tokens {
    parts |> reduce {acc: Tokens, it: Tokens => quote($acc, $it)}
}
