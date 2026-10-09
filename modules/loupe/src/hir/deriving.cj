package loupe.hir

import std.collection.*
import std.deriving.*
import ginkgo.{SyntaxElement, TextRange}
import cjsyntax.{CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{AnyHasName, AnyHasTypeParams, Decl, MacroAttr, MacroExpandDecl, TypeParam, identText}

/**
 * An interface `@Derive[...]` lists: the last segment of its path, where that is written, and the bounds of its
 * `where` (`T <: Comparable<T> & ToString`), each a type parameter and its bounds as written, in order.
 */
struct DeriveEntry {
    DeriveEntry(let name: String, let nameRange: TextRange, let bounds: Array<(String, String)>) {}
}

/**
 * What `@Derive[I]` adds for one interface it knows (#175, std's `std.deriving.builtins`): `I`'s `extend` of the type,
 * with its members, all `public`.
 */
@Derive[Equatable]
enum Derivable {
    | DeriveEquatable
    | DeriveHashable
    | DeriveToString
    | DeriveComparable
    | DeriveArbitrary
    | DeriveShrink

    static func named(name: String): ?Derivable {
        match (name) {
            case "Equatable" => DeriveEquatable
            case "Hashable" => DeriveHashable
            case "ToString" => DeriveToString
            case "Comparable" => DeriveComparable
            case "Arbitrary" => DeriveArbitrary
            case "Shrink" => DeriveShrink
            case _ => None
        }
    }

    /**
     * The interface the `extend` of `selfTy`, the type, lists.
     */
    func superOf(selfTy: String): String {
        match (this) {
            case DeriveEquatable => "Equatable<${selfTy}>"
            case DeriveHashable => "Hashable"
            case DeriveToString => "ToString"
            case DeriveComparable => "Comparable<${selfTy}>"
            case DeriveArbitrary => "Arbitrary<${selfTy}>"
            case DeriveShrink => "Shrink<${selfTy}>"
        }
    }

    /**
     * The bound of a type parameter `param` when `@Derive` writes none: its being of the interface.
     */
    func defaultBound(param: String): String {
        match (this) {
            case DeriveEquatable => "Equatable<${param}>"
            case DeriveHashable => "Hashable"
            case DeriveToString => "ToString"
            case DeriveComparable => "Comparable<${param}>"
            case DeriveArbitrary => "Arbitrary<${param}>"
            case DeriveShrink => "Shrink<${param}>"
        }
    }

    /**
     * The members of the `extend` of `selfTy`, their bodies empty.
     */
    func membersOf(selfTy: String): Array<String> {
        let operators = {ops: Array<String> => ops.map {op => "public operator func ${op}(other: ${selfTy}): Bool {}"}}
        match (this) {
            case DeriveEquatable => operators(["==", "!="])
            case DeriveHashable => ["public func hashCode(): Int64 {}"]
            case DeriveToString => ["public func toString(): String {}"]
            case DeriveComparable => ["public func compare(other: ${selfTy}): Ordering {}"].concat(
                operators(["<", "<=", ">", ">="]))
            case DeriveArbitrary => ["public static func arbitrary(random: RandomSource): Generator<${selfTy}> {}"]
            case DeriveShrink => ["public func shrink(): Iterable<${selfTy}> {}"]
        }
    }
}

/**
 * What std's `@Derive[...]`, `call`, adds after the type `decl` (#175, checked with `cjc --debug-macro`, 1.3.0-alpha):
 * one `extend` per interface it lists and knows, in their order, each type parameter bound by the interface unless
 * the interface's `where` bounds it; `Comparable`'s followed by `Equatable`'s, unless the call lists `Equatable`. An
 * interface it does not know adds nothing. Left out: the `private` `extend`s that check the fields, which nobody
 * names, and every body. `None` for a type whose name is not written yet.
 */
func deriveExpansion(decl: Decl, call: MacroExpandDecl): ?Expansion {
    let name = AnyHasName.cast(decl.syntax).flatMap {it => it.name()}.flatMap {name => name.identToken()} ?? return None
    let generics = match (AnyHasTypeParams.cast(decl.syntax).flatMap {it => it.typeParamList()}) {
        case Some(list) => list.typeParams() |> filterMap {param: TypeParam => param.name().flatMap {name => name.identToken()}} |>
            map {token: CjSyntaxToken => token.text()} |> collectArray
        case None => Array<String>()
    }
    let entries = match (call.macroAttr()) {
        case Some(attr) => deriveEntries(attr)
        case None => Array<DeriveEntry>()
    }
    let listsEquatable = entries.iterator().any {entry => entry.name == "Equatable"}
    let text = StringBuilder()
    let origins = ArrayList<Int64>()
    for (i in 0..entries.size) {
        let derivable = Derivable.named(entries[i].name) ?? continue
        appendExtend(text, name.text(), generics, derivable, entries[i].bounds)
        origins.add(i)
        if (derivable == Derivable.DeriveComparable && !listsEquatable) {
            appendExtend(text, name.text(), generics, Derivable.DeriveEquatable, [])
            origins.add(i)
        }
    }
    Expansion(text.toString(), origins.toArray())
}

/**
 * Appends to `text` the `extend` of `derivable` of the type `name` of the type parameters `generics`, those `bounds`
 * names bound by them.
 */
func appendExtend(text: StringBuilder, name: String, generics: Array<String>, derivable: Derivable,
    bounds: Array<(String, String)>): Unit {
    let params = String.join(generics, delimiter: ", ")
    let selfTy = if (generics.isEmpty()) {
        name
    } else {
        "${name}<${params}>"
    }
    if (generics.isEmpty()) {
        text.append("extend ${selfTy}")
    } else {
        text.append("extend<${params}> ${selfTy}")
    }
    text.append(" <: ${derivable.superOf(selfTy)}")
    let constraints = generics |> flatMap {
        param: String =>
        let written = bounds.filter {bound => identName(bound[0]) == identName(param)}
        if (written.isEmpty()) {
            ["${param} <: ${derivable.defaultBound(param)}"]
        } else {
            written.map {bound => "${param} <: ${bound[1]}"}
        }
    } |> collectArray
    if (!constraints.isEmpty()) {
        text.append(" where ${String.join(constraints, delimiter: ", ")}")
    }
    text.append(" {\n")
    for (member in derivable.membersOf(selfTy)) {
        text.append("    ${member}\n")
    }
    text.append("}\n")
}

/**
 * An identifier without its backquotes.
 */
func identName(ident: String): String {
    if (ident.size >= 2 && ident.startsWith("`") && ident.endsWith("`")) {
        ident[1..ident.size - 1]
    } else {
        ident
    }
}

/**
 * The interfaces `attr`, the `[...]` of `@Derive`, lists, read as std's `DeriveInputParser` does: comma-separated
 * paths, each maybe followed by `where` and constraints, a comma followed by `T <:` one more constraint, else the
 * next interface. What is neither is skipped up to the next comma.
 */
func deriveEntries(attr: MacroAttr): Array<DeriveEntry> {
    let tokens = ArrayList<CjSyntaxToken>()
    for (element in attr.syntax.descendantsWithTokens()) {
        if (let SyntaxElement.Token(token) <- element) {
            if (!token.kind.isTrivia()) {
                tokens.add(token)
            }
        }
    }
    let start = if (tokens.size > 0 && tokens[0].kind == SyntaxKind.LBracket) {
        1
    } else {
        0
    }
    let end = if (tokens.size > start && tokens[tokens.size - 1].kind == SyntaxKind.RBracket) {
        tokens.size - 1
    } else {
        tokens.size
    }
    DeriveAttrParser(tokens.toArray()[start..end]).entries()
}

/**
 * Reads the tokens of `@Derive`'s `[...]`, the brackets left out.
 */
class DeriveAttrParser {
    private var pos = 0

    DeriveAttrParser(private let tokens: Array<CjSyntaxToken>) {}

    func entries(): Array<DeriveEntry> {
        let found = ArrayList<DeriveEntry>()
        while (pos < tokens.size) {
            if (!at(pos, SyntaxKind.Ident)) {
                skipPastComma()
                continue
            }
            var last = tokens[pos]
            pos++
            while (at(pos, SyntaxKind.Dot) && at(pos + 1, SyntaxKind.Ident)) {
                last = tokens[pos + 1]
                pos += 2
            }
            let bounds = ArrayList<(String, String)>()
            if (at(pos, SyntaxKind.WhereKw)) {
                pos++
                while (let Some(from) <- boundsAt(pos)) {
                    let param = tokens[pos].text()
                    let to = constraintEnd(from)
                    bounds.add((param, textOf(from, to)))
                    pos = to
                    if (at(pos, SyntaxKind.Comma) && boundsAt(pos + 1).isSome()) {
                        pos++
                    } else {
                        break
                    }
                }
            }
            found.add(DeriveEntry(identText(last), last.textRange, bounds.toArray()))
            skipPastComma()
        }
        found.toArray()
    }

    /**
     * The tokens from `from` up to `to` as written, one space where anything was between two.
     */
    private func textOf(from: Int64, to: Int64): String {
        let text = StringBuilder()
        for (i in from..to) {
            if (i > from && tokens[i - 1].textRange.end != tokens[i].textRange.start) {
                text.append(" ")
            }
            text.append(tokens[i].text())
        }
        text.toString()
    }

    private func at(index: Int64, kind: SyntaxKind): Bool {
        index < tokens.size && tokens[index].kind == kind
    }

    /**
     * Where the bounds start if a constraint, `T <:`, starts at `index`; the lexer leaves `<:` two tokens there.
     */
    private func boundsAt(index: Int64): ?Int64 {
        if (!at(index, SyntaxKind.Ident)) {
            return None
        }
        if (at(index + 1, SyntaxKind.LtColon)) {
            return index + 2
        }
        if (at(index + 1, SyntaxKind.Lt) && at(index + 2, SyntaxKind.Colon) &&
            tokens[index + 1].textRange.end == tokens[index + 2].textRange.start) {
            return index + 3
        }
        None
    }

    /**
     * Where the bounds starting at `from` end: at a comma outside brackets, or at the end.
     */
    private func constraintEnd(from: Int64): Int64 {
        var depth = 0
        var index = from
        while (index < tokens.size) {
            match (tokens[index].kind) {
                case SyntaxKind.Comma where depth <= 0 => return index
                case SyntaxKind.Lt | SyntaxKind.LParen | SyntaxKind.LBracket => depth++
                case SyntaxKind.Gt | SyntaxKind.RParen | SyntaxKind.RBracket => depth--
                case SyntaxKind.GtGt => depth -= 2
                case _ => ()
            }
            index++
        }
        index
    }

    /**
     * Past the next comma outside brackets, or to the end.
     */
    private func skipPastComma(): Unit {
        pos = constraintEnd(pos)
        if (pos < tokens.size) {
            pos++
        }
    }
}
