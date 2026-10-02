macro package calca.macros

import std.ast.*
import std.collection.*

/**
 * Makes a function of the database and its arguments a query: its
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
 * as one generated `CalcaFields_<function>_S<types>` struct; one is its own key. Overloads are
 * queries of their own: what is generated is named after the types too. A value computed again
 * that equals the one remembered does not make what read it run again, so the result is
 * `Equatable` too, unless `@CalcaTracked[noEq]` says to count every computation as a change.
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
 *
 * On an `extend` of a type of the database (`@CalcaInput`, `@CalcaInterned`), it makes queries of
 * the methods marked `@CalcaTracked` in it, keyed by the value they are called on and their
 * arguments; the other members stay as they are. A method's options
 * go on its own mark, and its fallback takes the value first:
 *
 * ```cangjie
 * @CalcaTracked
 * extend SourceFile {
 *     @CalcaTracked[lru: 128]
 *     public func lineCount(db: Db): Int64 { text(db).split("\n").size }
 * }
 * ```
 */
public macro CalcaTracked(input: Tokens): Tokens {
    tracked(Tokens(), input)
}

public macro CalcaTracked(attrs: Tokens, input: Tokens): Tokens {
    tracked(attrs, input)
}

private func tracked(attrs: Tokens, input: Tokens): Tokens {
    match (parseDecl(input)) {
        // a method of a tracked `extend`: that one makes it a query
        case fd: FuncDecl where insideParentContext("CalcaTracked") =>
            setItem("name", fd.identifier.value)
            if (attrs.size > 0) {
                setItem("attrs", attrs)
            }
            input
        case fd: FuncDecl =>
            let options = parseOptions(attrs) ?? return input
            let (function, holder) = query(fd, input, None, options) ?? return input
            function + holder
        case ed: ExtendDecl =>
            if (attrs.size > 0) {
                diagReport(DiagReportLevel.ERROR, attrs, "an `extend`'s options go on each of its methods", "")
                return input
            }
            trackedExtend(ed, input)
        case _ =>
            diagReport(DiagReportLevel.ERROR, input, "`@CalcaTracked` goes on a function, or an `extend`", "")
            input
    }
}

/**
 * What the options of one query make of it: how values compare, how many it keeps, its fallback.
 */
struct Options {
    Options(let equal: Tokens, let lru: Tokens, let cycleResult: ?Token) {}
}

/**
 * The options in `attrs`, `None` once one that is not was reported.
 */
private func parseOptions(attrs: Tokens): ?Options {
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
                return None
            case "cycleResult" where i + 2 < attrs.size && attrs[i + 1].kind == TokenKind.COLON &&
                attrs[i + 2].kind == TokenKind.IDENTIFIER =>
                cycleResult = attrs[i + 2]
                i += 3
            case "cycleResult" =>
                diagReport(DiagReportLevel.ERROR, attrs,
                    "`cycleResult` takes the function giving the fallback: `cycleResult: f`", "")
                return None
            case _ =>
                diagReport(DiagReportLevel.ERROR, attrs,
                    "`@CalcaTracked` takes no option but `noEq`, `lru: N` and `cycleResult: f`", "")
                return None
        }
        if (i < attrs.size) {
            if (attrs[i].kind != TokenKind.COMMA) {
                diagReport(DiagReportLevel.ERROR, attrs, "`@CalcaTracked`'s options are separated by commas", "")
                return None
            }
            i++
        }
    }
    Options(equal, lru, cycleResult)
}

/**
 * The `extend` with its marked methods made queries, and the holders of those after it.
 */
private func trackedExtend(decl: ExtendDecl, input: Tokens): Tokens {
    if (decl.isGenericDecl) {
        diagReport(DiagReportLevel.ERROR, input, "a tracked method is not of a generic `extend`", "")
        return input
    }
    let marked = HashMap<String, Tokens>()
    // a message without a name is none of a method's
    for (message in getChildMessages("CalcaTracked") where message.hasItem("name")) {
        let name = message.getString("name")
        if (marked.contains(name)) {
            diagReport(DiagReportLevel.ERROR, input, "tracked methods are not overloaded: `${name}`", "")
            return input
        }
        marked.add(name, if (message.hasItem("attrs")) {
            message.getTokens("attrs")
        } else {
            Tokens()
        })
    }
    let receiver = decl.extendType.toTokens()
    var receiverName = ""
    for (token in receiver) {
        receiverName += stripBackquotes(token.value)
    }
    var members = Tokens()
    var holders = Tokens()
    for (member in decl.body.decls) {
        let method = match (member) {
            case fd: FuncDecl where marked.contains(fd.identifier.value) => fd
            case _ =>
                members += member.toTokens()
                continue
        }
        let options = parseOptions(marked[method.identifier.value]) ?? return input
        let (inside, holder) = query(method, member.toTokens(), (receiver, receiverName), options) ?? return input
        members += inside
        holders += holder
    }
    var superTypes = Tokens()
    for (superType in decl.superTypes) {
        superTypes += if (superTypes.size == 0) {
            quote(<: $(superType.toTokens()))
        } else {
            quote(& $(superType.toTokens()))
        }
    }
    let modifiers = modifiersOf(decl.modifiers)
    quote(
        $modifiers extend $receiver $superTypes {
            $members
        }

        $holders
    )
}

/**
 * A tracked function or method: what replaces the declaration (the method with its body, for a
 * method), and what goes at the top level (its holder, and the struct of its key). `receiver` is a
 * method's type, and its name as a word. `None` once what cannot be a query was reported.
 */
private func query(decl: FuncDecl, input: Tokens, receiver: ?(Tokens, String), options: Options): ?(Tokens, Tokens) {
    let params = decl.funcParams
    let what = if (receiver.isSome()) {
        "tracked method"
    } else {
        "tracked function"
    }
    if (decl.isGenericDecl) {
        diagReport(DiagReportLevel.ERROR, input, "a ${what} is not generic", "")
        return None
    }
    if (params.isEmpty()) {
        diagReport(DiagReportLevel.ERROR, input, "a ${what} takes the database first", "")
        return None
    }
    for (param in params where param.not.kind == TokenKind.NOT) {
        diagReport(DiagReportLevel.ERROR, param.toTokens(), "a ${what}'s parameters are positional", "")
        return None
    }
    let returnType = try {
        decl.declType.toTokens()
    } catch (_: ASTException) {
        diagReport(DiagReportLevel.ERROR, input, "a ${what} declares its return type", "")
        return None
    }

    let name = decl.identifier
    let plain = stripBackquotes(name.value)
    let described = match (receiver) {
        case Some((_, typeName)) => "${typeName}.${plain}"
        case None => plain
    }
    // the types too, or two overloads would declare one holder; a method's `.` keeps it from a
    // function named `Type_method`
    let prefix = mangled(described, params.toArray().map {param => param.paramType.toTokens()})
    let holder = Token(TokenKind.IDENTIFIER, "CalcaTracked_" + prefix)
    let db = params[0].identifier
    let dbType = params[0].paramType.toTokens()
    let args = params.toArray()[1..].map {param => (param.identifier, param.paramType.toTokens())}
    var signature = quote($db: $dbType)
    for ((ident, argType) in args) {
        signature += quote(, $ident: $argType)
    }

    // the key's fields: the value an instance method is called on, then the arguments
    let isStatic = decl.modifiers.iterator().any {modifier => modifier.keyword.value == "static"}
    let fields = ArrayList<(Token, Tokens, Tokens)>()
    if (let Some((receiverType, _)) <- receiver) {
        if (!isStatic) {
            fields.add((Token(TokenKind.IDENTIFIER, "calcaSelf"), receiverType, quote(this)))
        }
    }
    for ((ident, argType) in args) {
        fields.add((ident, argType, quote($ident)))
    }
    var made = Tokens()
    let taken = ArrayList<Tokens>()
    for (i in 0..fields.size) {
        let (ident, _, value) = fields[i]
        if (i > 0) {
            made += Token(TokenKind.COMMA)
        }
        made += value
        taken.add(if (fields.size == 1) {
            quote(calcaKey)
        } else {
            quote(calcaKey.$ident)
        })
    }
    let unpacked = arguments(taken.toArray())

    // no field is a key of `Unit`, one its own key, several a struct of them all
    let (keyType, keyArg, keyStruct) = match (fields.size) {
        case 0 => (quote(Unit), quote(()), quote())
        case 1 => (fields[0][1], made, quote())
        case _ =>
            let keyName = Token(TokenKind.IDENTIFIER, "CalcaFields_" + prefix)
            (quote($keyName), quote($keyName($made)), fieldsStruct(keyName, fields.toArray().map {field => (field[0], field[1])}))
    }

    let modifiers = modifiersOf(decl.modifiers)
    let body = decl.block.toTokens()
    let (execute, method) = match (receiver) {
        case Some((receiverType, _)) =>
            // the body stays a member, for `this` and the type's other members
            let bodyName = Token(TokenKind.IDENTIFIER, "calcaBody_" + plain)
            let (call, staticMark) = if (isStatic) {
                (quote($receiverType.$bodyName($db $unpacked)), quote(static))
            } else {
                let rest = arguments(taken.toArray()[1..])
                (quote($(taken[0]).$bodyName($db $rest)), quote())
            }
            (quote(
                public static func calcaExecute($db: $dbType, calcaKey: $keyType): $returnType {
                    $call
                }
            ), quote($staticMark func $bodyName($signature): $returnType $body))
        case None => (quote(
            public static func calcaExecute($db: $dbType, calcaKey: $keyType): $returnType {
                calcaRun($db $unpacked)
            }

            static func calcaRun($signature): $returnType $body
        ), quote())
    }
    let fallback = match (options.cycleResult) {
        case Some(recover) => quote(
            public static func calcaHasFallback(): Bool {
                true
            }

            public static func calcaFallback($db: $dbType, calcaKey: $keyType): $returnType {
                $recover($db $unpacked)
            }
        )
        case None => quote()
    }
    let equal = options.equal
    let lru = options.lru
    let describedName = Token(TokenKind.STRING_LITERAL, described)

    let declaration = quote(
        $modifiers func $name($signature): $returnType {
            $holder.FUNCTION.fetch<$holder>($db, $keyArg)
        }

        $method
    )
    let topLevel = quote(
        private struct $holder <: TrackedBody<$dbType, $keyType, $returnType> {
            static let FUNCTION = TrackedFunction<$dbType, $keyType, $returnType>($describedName, $equal $lru)

            $execute

            $fallback
        }

        $keyStruct
    )
    (declaration, topLevel)
}

/**
 * `, a, b`: what follows the database in a call.
 */
private func arguments(values: Array<Tokens>): Tokens {
    var tokens = Tokens()
    for (value in values) {
        tokens += quote(, $value)
    }
    tokens
}
