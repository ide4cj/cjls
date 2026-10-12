package macro_server

import std.collection.*
import std.fs.*

/**
 * cjc's `TokenKind` numbers by name, as an SDK lists them in its `include/cangjie/Lex/Tokens.inc`: a kind's number
 * is its line's place among the `TOKEN` and `EXPERIMENTAL_TOKEN` lines, the order cjc's enum takes them in (D95).
 * The numbers are read from the SDK the server comes with, so no table of ours has to match its nightly.
 */
public class TokenNumbers {
    let numbers = HashMap<String, UInt8>()

    /**
     * `names`: each kind's name (`DOT`) by its number, what std.ast's `TokenKind.toString` gives.
     */
    TokenNumbers(public let names: Array<String>) {
        for (i in 0..names.size) {
            numbers.add(names[i], UInt8(i))
        }
    }

    /**
     * The numbers the file `tokensInc` lists, as `parse` reads them; `None` if it cannot be read either.
     */
    public static func read(tokensInc: Path): ?TokenNumbers {
        let text = try {
            String.fromUtf8(File.readFrom(tokensInc))
        } catch (_: Exception) {
            return None
        }
        parse(text)
    }

    /**
     * The numbers `tokensInc` lists, or `None` if it lists more than a `UInt8` numbers, or lacks a kind `macroTokens`
     * sends: then nothing can be sent to this SDK's server.
     */
    public static func parse(tokensInc: String): ?TokenNumbers {
        let names = ArrayList<String>()
        for (line in tokensInc.lines()) {
            let entry = line.trimAscii()
            let args = if (entry.startsWith("TOKEN(")) {
                entry["TOKEN(".size..]
            } else if (entry.startsWith("EXPERIMENTAL_TOKEN(")) {
                entry["EXPERIMENTAL_TOKEN(".size..]
            } else {
                continue
            }
            names.add(args[..(args.indexOf(",") ?? return None)].trimAscii())
        }
        ofNames(names.toArray())
    }

    /**
     * The numbers of kinds named by `names`, each name at its number, as `std.ast`'s `getTokenKind(n).toString()`
     * gives them for an SDK without `Tokens.inc` (D104), up to the first it names again: `AT_EXCLAMATION` is
     * `AT_EXCL`. `None` as for `parse`.
     */
    public static func ofNames(names: Array<String>): ?TokenNumbers {
        let kinds = ArrayList<String>()
        for (name in names) {
            let kind = if (name == "AT_EXCLAMATION") {
                "AT_EXCL"
            } else {
                name
            }
            if (kinds.contains(kind)) {
                break
            }
            kinds.add(kind)
        }
        if (kinds.size > Int64(UInt8.Max) + 1) {
            return None
        }
        let numbers = TokenNumbers(kinds.toArray())
        if (SENT_KINDS.iterator().any {name => !numbers.numbers.contains(name)}) {
            return None
        }
        numbers
    }

    /**
     * The number of the kind named `name` (`DOT`).
     *
     * @throws NoneValueException - if there is no such kind; `parse` saw every kind `macroTokens` sends
     */
    public func numberOf(name: String): UInt8 {
        numbers.get(name).getOrThrow()
    }
}
