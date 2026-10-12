package loupe.hir

import std.collection.*
import cjsyntax.{CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{AnyHasName, AnyHasTypeParams, ClassDecl, Decl, FuncDecl, MacroArgs, MacroExpandDecl, ParamList, TypeParam,
    identText}

// What `std.unittest.testmacro`'s macros declare (#175), read from cangjie_runtime's `testmacro` and checked with
// `cjc --debug-macro` (1.3.0-alpha.20260918): the declarations a name can reach, their bodies empty. Left out: the
// `private` helpers of a test class (`classConfiguration`, `inheritedFromClassAnnotatedByTestTemplate`), the
// constructor it adds when it has none (the default one cjc adds anyway), the registrations of `@UnittestOption`
// (`let _ = ...`), and every body. The names they are written with resolve in the file of the call, as cjc's:
// `TestClass`, `TestSuite`, `TestPackage`, `DataStrategyProcessor`, `KeyFor` need the user's `import std.unittest.*`.

/**
 * What `@Test` (`template` false) or `@TestTemplate` adds to the class `decl`: its being a `TestClass`, with
 * `asTestSuite`, as an `extend`, for cjc rewrites the class itself (`InstrumentedClass`); after it, for `@Test` on a
 * class with a constructor of no parameters, the registration of the suite in the package's `TestPackage`. `None` for
 * a class whose name is not written yet.
 */
func testClassExpansion(decl: Decl, template!: Bool): ?Expansion {
    let cls = ClassDecl.cast(decl.syntax) ?? return None
    let name = identText(nameTokenOf(decl) ?? return None)
    let generics = genericsOf(decl)
    let text = StringBuilder()
    let params = String.join(generics, delimiter: ", ")
    if (generics.isEmpty()) {
        text.append("extend ${name} <: TestClass")
    } else {
        text.append("extend<${params}> ${name}<${params}> <: TestClass")
    }
    if (let Some(clause) <- cls.whereClause()) {
        text.append(" ${tokensText(tokensOf(clause.syntax))}")
    }
    text.append(" {\n    public func asTestSuite(): TestSuite {}\n}\n")
    let origins = ArrayList<ExpansionOrigin>([ExpansionOrigin.OfMacro])
    if (!template && hasConstructorOfNoParameters(cls)) {
        appendRegistration(text, "TestPackageExtension_${name}", "register${name}")
        origins.add(all: [ExpansionOrigin.OfMacro, ExpansionOrigin.OfMacro])
    }
    Expansion(text.toString(), origins.toArray())
}

/**
 * What `@Test` adds after the function `decl`, which it keeps: a test class of it, `TestCase_<name>`, and its
 * registration.
 */
func testFuncExpansion(decl: Decl): ?Expansion {
    let fn = FuncDecl.cast(decl.syntax) ?? return None
    let name = "TestCase_${identText(nameTokenOf(decl) ?? return None)}"
    let text = StringBuilder()
    text.append("class ${name} <: TestClass {\n    public func asTestSuite(): TestSuite {}\n}\n")
    appendRegistration(text, "TestPackageExtension_${name}", "register${name}")
    Expansion(text.toString(), Array(3, repeat: ExpansionOrigin.OfMacro))
}

/**
 * What `@TestBuilder` adds after the function `decl`, which it keeps: the registration of the suite it builds.
 */
func testBuilderExpansion(decl: Decl): ?Expansion {
    let fn = FuncDecl.cast(decl.syntax) ?? return None
    let name = identText(nameTokenOf(decl) ?? return None)
    let text = StringBuilder()
    appendRegistration(text, "TestPackageExtension_${name}", "register_${name}")
    Expansion(text.toString(), Array(2, repeat: ExpansionOrigin.OfMacro))
}

/**
 * What `@Strategy` makes of the function `decl`, which it replaces: a `let` of its name and modifiers, a
 * `DataStrategyProcessor` of the type it returns, its body in a lambda of the `let`'s value. Without a return type,
 * which cjc rejects, the `let` is of no type written: the name stands.
 */
func strategyExpansion(decl: Decl): ?Expansion {
    let fn = FuncDecl.cast(decl.syntax) ?? return None
    let name = (nameTokenOf(decl) ?? return None).text()
    let text = StringBuilder()
    if (let Some(modifiers) <- fn.modifiers()) {
        text.append("${tokensText(tokensOf(modifiers.syntax))} ")
    }
    text.append("let ${name}")
    if (let Some(ty) <- fn.retType().flatMap {it => it.ty()}) {
        text.append(": DataStrategyProcessor<${tokensText(tokensOf(ty.syntax))}>")
    }
    text.append("\n")
    Expansion(text.toString(), [ExpansionOrigin.OfName], replaces: true)
}

/**
 * What `@UnittestOption[T, ...](name, ...)`, `call`, declares: the key of the option, `Key<Name>`, a struct of
 * `KeyFor` each type, with `static prop <name>` itself, `public` if `public` comes before the name. `None` without
 * types or a name, which cjc rejects.
 */
func optionExpansion(call: MacroExpandDecl): ?Expansion {
    let attr = call.macroAttr() ?? return None
    let types = splitAtCommas(tokensInside(attr.syntax, SyntaxKind.LBracket, SyntaxKind.RBracket)).map {
        tokens => "KeyFor<${tokensText(tokens)}>"
    }
    if (types.isEmpty()) {
        return None
    }
    let (token, isPublic) = optionNameOf(call.macroArgs() ?? return None) ?? return None
    let name = identText(token)
    let runes = name.toRuneArray()
    let key = "Key${String(runes[..1]).toAsciiUpper()}${String(runes[1..])}"
    let access = if (isPublic) {
        "public "
    } else {
        ""
    }
    let text = "${access}struct ${key} <: ${String.join(types, delimiter: " & ")} {\n" +
        "    public static prop ${token.text()}: ${key} {\n" +
        "        get() {}\n" +
        "    }\n" +
        "    public prop name: String {\n" +
        "        get() {}\n" +
        "    }\n" +
        "}\n"
    Expansion(text, [ExpansionOrigin.OfOption])
}

/**
 * The name of the option `args`, the `(...)` of `@UnittestOption`, names: its first identifier, and whether `public`
 * is before it.
 */
func optionNameOf(args: MacroArgs): ?(CjSyntaxToken, Bool) {
    let tokens = tokensInside(args.syntax, SyntaxKind.LParen, SyntaxKind.RParen)
    let isPublic = tokens.size > 0 && tokens[0].kind == SyntaxKind.PublicKw
    let at = if (isPublic) {
        1
    } else {
        0
    }
    if (at < tokens.size && tokens[at].kind == SyntaxKind.Ident) {
        (tokens[at], isPublic)
    } else {
        None
    }
}

/**
 * Appends to `text` the registration `@Test` and `@TestBuilder` add: an interface `extension` of one function
 * `register`, and the `extend` of `TestPackage` that implements it.
 */
func appendRegistration(text: StringBuilder, extension: String, register: String): Unit {
    text.append("interface ${extension} {\n    func ${register}(): Unit\n}\n")
    text.append("extend TestPackage <: ${extension} {\n    public func ${register}(): Unit {}\n}\n")
}

/**
 * The names of the type parameters of `decl`, as written.
 */
func genericsOf(decl: Decl): Array<String> {
    match (AnyHasTypeParams.cast(decl.syntax).flatMap {it => it.typeParamList()}) {
        case Some(list) => list.typeParams() |> filterMap {param: TypeParam => param.name().flatMap {name => name.identToken()}} |>
            map {token: CjSyntaxToken => token.text()} |> collectArray
        case None => Array<String>()
    }
}

/**
 * Whether the class `cls` can be made of no arguments: it declares no constructor, or one of no parameters, which a
 * test class needs to be registered (`InstrumentedClass.toTokens`).
 */
func hasConstructorOfNoParameters(cls: ClassDecl): Bool {
    let paramLists = ArrayList<?ParamList>()
    for (member in cls.declBody()?.decls() ?? Array<Decl>().iterator()) {
        match (member) {
            case Decl.AsInitDecl(it) => paramLists.add(it.paramLists().next())
            case Decl.AsPrimaryInitDecl(it) => paramLists.add(it.paramLists().next())
            case _ => ()
        }
    }
    paramLists.isEmpty() || paramLists.iterator().any {list => list.map {it => it.params().next().isNone()} ?? true}
}

/**
 * The token of the name `decl` declares, if it is written.
 */
func nameTokenOf(decl: Decl): ?CjSyntaxToken {
    AnyHasName.cast(decl.syntax).flatMap {it => it.name()}.flatMap {name => name.identToken()}
}

/**
 * `tokens` cut at their commas outside brackets, the empty parts left out.
 */
func splitAtCommas(tokens: Array<CjSyntaxToken>): Array<Array<CjSyntaxToken>> {
    let parts = ArrayList<Array<CjSyntaxToken>>()
    var depth = 0
    var start = 0
    for (i in 0..=tokens.size) {
        if (i == tokens.size || (tokens[i].kind == SyntaxKind.Comma && depth <= 0)) {
            if (i > start) {
                parts.add(tokens[start..i])
            }
            start = i + 1
            continue
        }
        match (tokens[i].kind) {
            case SyntaxKind.Lt | SyntaxKind.LParen | SyntaxKind.LBracket => depth++
            case SyntaxKind.Gt | SyntaxKind.RParen | SyntaxKind.RBracket => depth--
            case SyntaxKind.GtGt => depth -= 2
            case _ => ()
        }
    }
    parts.toArray()
}
