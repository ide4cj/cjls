package syntax_codegen

import std.collection.*

let NODE_TYPE = "SyntaxNode<SyntaxKind>"
let TOKEN_TYPE = "SyntaxToken<SyntaxKind>"

/**
 * The typed views of the grammar: a struct for every node, an enum for every rule listing nodes, and the
 * interfaces they share.
 */
func emitAst(model: Model, header: String, packageName: String): String {
    let interfaces = interfacesOf(model, INTERFACES)
    let views = CodeWriter()
    // the token sets the accessors use, by name: a global must come before what uses it in its file
    let sets = ArrayList<(String, Array<String>)>()
    for (i in interfaces) {
        views.blank()
        emitInterface(views, model, i)
    }
    for (r in model.grammar.rules) {
        views.blank()
        let implemented = interfaces.filter {i => i.implementedBy(r.name)}
        match (model.enumOf(r.name)) {
            case Some(e) => emitEnum(views, model, e, implemented)
            case None => emitNode(views, nodeIr(model, r.name), sets, implemented)
        }
    }
    let w = CodeWriter()
    w.line(header)
    w.blank()
    w.line("package ${packageName}")
    w.blank()
    w.line("import std.deriving.*")
    w.line("import ginkgo.*")
    w.line("import cjsyntax.SyntaxKind")
    for ((name, kinds) in sets) {
        w.blank()
        w.wrapped("let ${name} = TokenSet<SyntaxKind>([", kinds.map {k => "SyntaxKind.${k}"}, ",", "])")
    }
    "${w}${views}"
}

func nodeIr(model: Model, name: String): NodeIr {
    for (n in model.nodes where n.name == name) {
        return n
    }
    throw IllegalStateException("no node `${name}`")
}

/**
 * What a view's declaration says it is: an `AstNode`, and its interfaces.
 */
func supertypes(view: String, implemented: Array<InterfaceIr>): String {
    let names = ArrayList<String>(["AstNode<SyntaxKind, ${view}>"])
    names.add(all: implemented.map {i => i.spec.name})
    String.join(names.toArray(), delimiter: " & ")
}

func emitNode(w: CodeWriter, n: NodeIr, sets: ArrayList<(String, Array<String>)>,
    implemented: Array<InterfaceIr>): Unit {
    let doc = ArrayList<String>(n.doc)
    if (!n.handWritten.isEmpty()) {
        if (!doc.isEmpty()) {
            doc.add("")
        }
        let names = n.handWritten.map {f => "`${f}`"}
        doc.add("Written by hand, as the grammar cannot tell them by position: ${String.join(names, delimiter: ", ")}.")
    }
    w.doc(doc.toArray())
    w.line("@Derive[Equatable, Hashable]")
    w.block("public struct ${n.name} <: ${supertypes(n.name, implemented)} & ToString") {
        =>
        w.line("${n.name}(let node: ${NODE_TYPE}) {}")
        w.blank()
        w.block("public static func canCast(kind: SyntaxKind): Bool") {=> w.line("kind == SyntaxKind.${n.name}")}
        w.blank()
        w.block("public static func cast(node: ${NODE_TYPE}): ?${n.name}") {
            =>
            w.line("if (canCast(node.kind)) {")
            w.indented {=> w.line("${n.name}(node)")}
            w.line("} else {")
            w.indented {=> w.line("None")}
            w.line("}")
        }
        w.blank()
        w.block("public prop syntax: ${NODE_TYPE}") {=> w.block("get()") {=> w.line("node")}}
        for (f in n.fields) {
            w.blank()
            emitField(w, n.name, f, sets)
        }
        w.blank()
        // a view prints as the text of its node; two are equal when they view one node, which is all it holds
        w.block("public func toString(): String") {=> w.line("node.text()")}
    }
}

func emitField(w: CodeWriter, owner: String, f: FieldIr, sets: ArrayList<(String, Array<String>)>): Unit {
    func setNamed(kinds: Array<String>): String {
        let name = setName(owner, f.name)
        sets.add((name, kinds))
        name
    }
    match (f) {
        case NodeField(name, typeName, access) =>
            match (access) {
                case Nth(_, counted) => setNamed(counted)
                case AllFrom(_, counted) => setNamed(counted)
                case First | All => ()
            }
            w.block("public func ${name}(): ${accessorType(typeName, access)}") {
                => w.line(childCall(owner, name, typeName, access))
            }
        case TokenField(name, kind, many) =>
            w.block("public func ${name}(): ?${TOKEN_TYPE}") {=> w.line("astToken(node, SyntaxKind.${kind})")}
            if (many) {
                w.blank()
                w.block("public func ${name}s(): Iterator<${TOKEN_TYPE}>") {
                    => w.line("astTokens(node, SyntaxKind.${kind})")
                }
            }
        case TokenSetField(name, kinds) => w.block("public func ${name}(): ?${TOKEN_TYPE}") {
            => w.line("astToken(node, ${setNamed(kinds)})")
        }
    }
}

/**
 * The name of the set of kinds an accessor counts, or of the tokens it is any of.
 */
func setName(owner: String, field: String): String {
    "${screamingSnake(owner)}_${screamingSnake(field)}"
}

func accessorType(typeName: String, access: ChildAccess): String {
    match (access) {
        case First | Nth(_, _) => accessorType(typeName, false)
        case All | AllFrom(_, _) => accessorType(typeName, true)
    }
}

func accessorType(typeName: String, many: Bool): String {
    if (many) {
        "Iterator<${typeName}>"
    } else {
        "?${typeName}"
    }
}

/**
 * How the accessor `name` of `owner` finds its child in `node`.
 */
func childCall(owner: String, name: String, typeName: String, access: ChildAccess): String {
    let call = "<SyntaxKind, ${typeName}>"
    match (access) {
        case First => "astChild${call}(node)"
        case Nth(i, _) => "astNthChild${call}(node, ${i}, ${setName(owner, name)})"
        case All => "astChildren${call}(node)"
        case AllFrom(i, _) => "astChildrenFrom${call}(node, ${i}, ${setName(owner, name)})"
    }
}

func emitEnum(w: CodeWriter, model: Model, e: EnumIr, implemented: Array<InterfaceIr>): Unit {
    w.doc(e.doc)
    let supertypesOfEnum = "${supertypes(e.name, implemented)} & Equatable<${e.name}> & Hashable & ToString"
    w.block("public enum ${e.name} <: ${supertypesOfEnum}") {
        =>
        for (v in e.variants) {
            w.line("| ${v.name}(${v.typeName})")
        }
        w.blank()
        w.block("public static func canCast(kind: SyntaxKind): Bool") {
            => w.block("match (kind)") {
                =>
                let kinds = model.kindsOf(e.name).map {k => "SyntaxKind.${k}"}
                w.wrapped("case ", kinds, " |", " => true", leading: true)
                w.line("case _ => false")
            }
        }
        w.blank()
        w.block("public static func cast(node: ${NODE_TYPE}): ?${e.name}") {
            =>
            if (e.variants.all {v => !model.isEnum(v.typeName)}) {
                w.block("match (node.kind)") {
                    =>
                    for (v in e.variants) {
                        w.line("case SyntaxKind.${v.typeName} => ${v.name}(${v.typeName}(node))")
                    }
                    w.line("case _ => None")
                }
            } else {
                for (v in e.variants) {
                    if (model.isEnum(v.typeName)) {
                        w.block("if (let Some(it) <- ${v.typeName}.cast(node))") {=> w.line("return ${v.name}(it)")}
                    } else {
                        w.block("if (node.kind == SyntaxKind.${v.typeName})") {
                            => w.line("return ${v.name}(${v.typeName}(node))")
                        }
                    }
                }
                w.line("None")
            }
        }
        w.blank()
        w.block("public prop syntax: ${NODE_TYPE}") {
            => w.block("get()") {
                => w.block("match (this)") {
                    => for (v in e.variants) {
                        w.line("case ${v.name}(it) => it.syntax")
                    }
                }
            }
        }
        for (i in implemented) {
            if (let Accessor(name, typeName, many) <- i.spec.method) {
                w.blank()
                w.block("public func ${name}(): ${accessorType(typeName, many)}") {
                    => w.block("match (this)") {
                        => for (v in e.variants) {
                            w.line("case ${v.name}(it) => it.${name}()")
                        }
                    }
                }
            }
        }
        w.blank()
        // not derived: two variants may view one node (a macro call on a declaration is a `Decl` and an `Expr`)
        w.block("public operator func ==(other: ${e.name}): Bool") {=> w.line("syntax == other.syntax")}
        w.blank()
        w.block("public operator func !=(other: ${e.name}): Bool") {=> w.line("syntax != other.syntax")}
        w.blank()
        w.block("public func hashCode(): Int64") {=> w.line("syntax.hashCode()")}
        w.blank()
        w.block("public func toString(): String") {=> w.line("syntax.text()")}
    }
}

/**
 * An interface, and `AnyHas…`: a view of any node that implements it, whatever its kind.
 */
func emitInterface(w: CodeWriter, model: Model, i: InterfaceIr): Unit {
    let spec = i.spec
    w.doc([spec.doc])
    w.block("public interface ${spec.name}") {
        =>
        w.line("prop syntax: ${NODE_TYPE}")
        w.blank()
        match (spec.method) {
            case Accessor(name, typeName, many) => w.line("func ${name}(): ${accessorType(typeName, many)}")
            case Provided(doc, signature, body, _) =>
                w.doc([doc])
                w.block(signature) {=> w.line(body)}
        }
    }
    w.blank()
    let any = "Any${spec.name}"
    w.doc(["Any node that is a `${spec.name}`, viewed as one."])
    w.line("@Derive[Equatable, Hashable]")
    w.block("public struct ${any} <: AstNode<SyntaxKind, ${any}> & ${spec.name} & ToString") {
        =>
        w.line("${any}(let node: ${NODE_TYPE}) {}")
        w.blank()
        w.block("public static func canCast(kind: SyntaxKind): Bool") {
            => w.block("match (kind)") {
                =>
                let kinds = i.implementors.filter {v => !model.isEnum(v)}.map {k => "SyntaxKind.${k}"}
                w.wrapped("case ", kinds, " |", " => true", leading: true)
                w.line("case _ => false")
            }
        }
        w.blank()
        w.block("public static func cast(node: ${NODE_TYPE}): ?${any}") {
            =>
            w.line("if (canCast(node.kind)) {")
            w.indented {=> w.line("${any}(node)")}
            w.line("} else {")
            w.indented {=> w.line("None")}
            w.line("}")
        }
        w.blank()
        w.block("public prop syntax: ${NODE_TYPE}") {=> w.block("get()") {=> w.line("node")}}
        if (let Accessor(name, typeName, many) <- spec.method) {
            w.blank()
            emitAnyAccessor(w, model, i, name, accessorType(typeName, many))
        }
        w.blank()
        w.block("public func toString(): String") {=> w.line("node.text()")}
    }
}

/**
 * The accessor of `AnyHas…`, as each kind's view finds its child: one call where they all find it alike.
 */
func emitAnyAccessor(w: CodeWriter, model: Model, i: InterfaceIr, name: String, returnType: String): Unit {
    // the calls, each with the kinds that make it, in the order first met
    let calls = ArrayList<(String, ArrayList<String>)>()
    for (view in i.implementors where !model.isEnum(view)) {
        for (f in nodeIr(model, view).fields) {
            if (let NodeField(n, typeName, access) <- f && n == name) {
                let call = childCall(view, n, typeName, access)
                match (calls.iterator().filter {c => c[0] == call}.next()) {
                    case Some((_, kinds)) => kinds.add(view)
                    case None => calls.add((call, ArrayList<String>([view])))
                }
            }
        }
    }
    w.block("public func ${name}(): ${returnType}") {
        =>
        if (calls.size == 1) {
            w.line(calls[0][0])
        } else {
            w.block("match (node.kind)") {
                =>
                for ((call, kinds) in calls[..calls.size - 1]) {
                    w.wrapped("case ", kinds.toArray().map {k => "SyntaxKind.${k}"}, " |", " => ${call}", leading: true)
                }
                w.line("case _ => ${calls[calls.size - 1][0]}")
            }
        }
    }
}
