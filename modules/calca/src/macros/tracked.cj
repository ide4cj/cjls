macro package calca.macros

import std.ast.*
import std.collection.*

/**
 * Makes a function of the database and its arguments a query, as salsa's `#[salsa::tracked]` is: its
 * value is remembered per argument, along with everything it read, and computed again only once
 * something it read has changed.
 *
 * ```cangjie
 * @CalcaTracked
 * public func lineCount(db: Db, file: SourceFile): Int64 {
 *     file.text(db).split("\n").size
 * }
 * ```
 *
 * The database comes first, typed as the database interface the body needs; the arguments are
 * positional, `Hashable` and `Equatable`, an `@CalcaInput` for one. Several are remembered together,
 * as one generated `CalcaFields_<function>` struct; one is its own key. A value computed again that equals the one
 * remembered does not make what read it run again, so the result is `Equatable` too, unless
 * `@CalcaTracked[noEq]` says to count every computation as a change.
 *
 * `@CalcaTracked[lru: 128]` keeps the values of the 128 keys fetched last from one revision to the
 * next, and lets go of the others; what they read is kept, so they are verified without being
 * computed, and computed again only when fetched. For values that are large and cheap to compute
 * again (a file's tree).
 *
 * `@CalcaTracked[cycleResult: fallback]` recovers from a cycle: `fallback` takes what the function
 * takes and returns what it returns. When a cycle is found and every query on it has one, each of
 * them returns its fallback, and is computed again once anything the cycle read changes; when one
 * has none, the cycle is a `CycleException`.
 *
 * Options go together: `@CalcaTracked[noEq, lru: 128, cycleResult: fallback]`.
 */
public macro CalcaTracked(input: Tokens): Tokens {
    tracked(input, quote({old, new => old == new}), quote(), None)
}

public macro CalcaTracked(attrs: Tokens, input: Tokens): Tokens {
    var equal = quote({old, new => old == new})
    var lru = quote()
    var cycleResult: ?Token = None
    var i = 0
    while (i < attrs.size) {
        let option = attrs[i]
        match (option.value) {
            case "noEq" =>
                equal = quote({_, _ => false})
                i++
            // a literal has no sign, `-` is a token of its own
            case "lru" where i + 2 < attrs.size && attrs[i + 1].kind == TokenKind.COLON && attrs[i + 2].kind ==
                TokenKind.INTEGER_LITERAL =>
                let capacity = attrs[i + 2]
                lru = quote(, lru: $capacity)
                i += 3
            case "lru" =>
                diagReport(DiagReportLevel.ERROR, attrs, "`lru` takes how many values to keep: `lru: 128`", "")
                return input
            case "cycleResult" where i + 2 < attrs.size && attrs[i + 1].kind == TokenKind.COLON &&
                attrs[i + 2].kind == TokenKind.IDENTIFIER =>
                cycleResult = attrs[i + 2]
                i += 3
            case "cycleResult" =>
                diagReport(DiagReportLevel.ERROR, attrs,
                    "`cycleResult` takes the function giving the fallback: `cycleResult: f`", "")
                return input
            case _ =>
                diagReport(DiagReportLevel.ERROR, attrs,
                    "`@CalcaTracked` takes no option but `noEq`, `lru: N` and `cycleResult: f`", "")
                return input
        }
        if (i < attrs.size) {
            if (attrs[i].kind != TokenKind.COMMA) {
                diagReport(DiagReportLevel.ERROR, attrs, "`@CalcaTracked`'s options are separated by commas", "")
                return input
            }
            i++
        }
    }
    tracked(input, equal, lru, cycleResult)
}

private func tracked(input: Tokens, equal: Tokens, lru: Tokens, cycleResult: ?Token): Tokens {
    let decl = match (parseDecl(input)) {
        case fd: FuncDecl => fd
        case _ =>
            diagReport(DiagReportLevel.ERROR, input, "`@CalcaTracked` goes on a function", "")
            return input
    }
    let params = decl.funcParams
    if (decl.isGenericDecl) {
        diagReport(DiagReportLevel.ERROR, input, "a tracked function is not generic", "")
        return input
    }
    if (params.isEmpty()) {
        diagReport(DiagReportLevel.ERROR, input, "a tracked function takes the database first", "")
        return input
    }
    for (param in params where param.not.kind == TokenKind.NOT) {
        diagReport(DiagReportLevel.ERROR, param.toTokens(), "a tracked function's parameters are positional", "")
        return input
    }
    let returnType = try {
        decl.declType.toTokens()
    } catch (_: ASTException) {
        diagReport(DiagReportLevel.ERROR, input, "a tracked function declares its return type", "")
        return input
    }

    let name = decl.identifier
    let holder = Token(TokenKind.IDENTIFIER, "CalcaTracked_" + stripBackquotes(name.value))
    let db = params[0].identifier
    let dbType = params[0].paramType.toTokens()
    let args = params.toArray()[1..].map {param => (param.identifier, param.paramType.toTokens())}
    var signature = quote($db: $dbType)
    var values = Tokens()
    var fields = Tokens()
    for (i in 0..args.size) {
        let (ident, argType) = args[i]
        signature += quote(, $ident: $argType)
        if (i > 0) {
            values += Token(TokenKind.COMMA)
        }
        values += ident
        fields += quote(, calcaKey.$ident)
    }
    let modifiers = modifiersOf(decl.modifiers)
    let body = decl.block.toTokens()

    // no argument is a key of `Unit`, one its own key, several a struct of them all
    let (keyType, keyArg, keyParam, keyValues, execute, keyStruct) = match (args.size) {
        case 0 => (quote(Unit), quote(()), quote(_: Unit), quote(),
            quote(static func calcaExecute($db: $dbType, _: Unit): $returnType $body), quote())
        case 1 =>
            let (ident, argType) = args[0]
            (argType, values, quote($ident: $argType), quote(, $ident),
                quote(static func calcaExecute($db: $dbType, $ident: $argType): $returnType $body), quote())
        case _ =>
            let keyName = Token(TokenKind.IDENTIFIER, "CalcaFields_" + stripBackquotes(name.value))
            let execute = quote(
                static func calcaExecute($db: $dbType, calcaKey: $keyName): $returnType {
                    calcaRun($db $fields)
                }

                static func calcaRun($signature): $returnType $body
            )
            (quote($keyName), quote($keyName($values)), quote(calcaKey: $keyName), fields, execute,
                fieldsStruct(keyName, args))
    }
    let (recoverArg, fallback) = match (cycleResult) {
        case Some(recover) => (quote(, recover: $holder.calcaFallback), quote(
            static func calcaFallback($db: $dbType, $keyParam): $returnType {
                $recover($db $keyValues)
            }
        ))
        case None => (quote(), quote())
    }

    quote(
        $modifiers func $name($signature): $returnType {
            $holder.FUNCTION.fetch($db, $keyArg, $holder.calcaExecute $recoverArg)
        }

        private struct $holder {
            static let FUNCTION = TrackedFunction<$dbType, $keyType, $returnType>($(nameLiteral(name)), $equal $lru)

            $execute

            $fallback
        }

        $keyStruct
    )
}
