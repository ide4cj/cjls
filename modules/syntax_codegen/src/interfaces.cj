package syntax_codegen

import std.collection.*

/**
 * What an interface of the views asks.
 */
enum InterfaceMethod {
    /** an accessor its implementors have: name, type, whether it returns several */
    | Accessor(String, String, Bool)
    /** a method with a body of its own, for the views named: doc, signature, body; an enum's variants as well */
    | Provided(String, String, String, Array<String>)
}

/**
 * An interface of the views: what every node that has it is asked alike, a declaration its name or its modifiers.
 */
struct InterfaceSpec {
    InterfaceSpec(let name: String, let doc: String, let method: InterfaceMethod) {}
}

/**
 * The interfaces of `cjsyntax.ast`. A view implements one when it has its accessor, an enum when all its variants
 * do; each comes with `AnyHas…`, a view of any node that does.
 */
let INTERFACES: Array<InterfaceSpec> = [
    InterfaceSpec("HasName", "A node that declares a name.", Accessor("name", "Name", false)),
    InterfaceSpec("HasModifiers", "A node that may have modifiers.", Accessor("modifiers", "Modifiers", false)),
    InterfaceSpec("HasAnnotations", "A node that may have annotations.", Accessor("annotations", "Annotation", true)),
    InterfaceSpec("HasTypeParams", "A node that may have type parameters.",
        Accessor("typeParamList", "TypeParamList", false)),
    InterfaceSpec("HasWhereClause", "A node that may have a `where` clause.",
        Accessor("whereClause", "WhereClause", false)),
    InterfaceSpec("HasDocComment", "A node the parser gives the comments right before it, its documentation.",
        Provided(
            "The comments before the rest of it, in order: none but the documentation is there.",
            "func docComments(): Array<${TOKEN_TYPE}>",
            "docCommentsOf(syntax)",
            ["Decl", "PackageHeader"]
        ))
]

/**
 * An interface, and the views that implement it, in the order of the grammar.
 */
struct InterfaceIr {
    InterfaceIr(let spec: InterfaceSpec, let implementors: Array<String>) {}

    func implementedBy(view: String): Bool {
        implementors.contains(view)
    }
}

/**
 * Which views implement each of `specs`.
 *
 * @throws GrammarException - if a view a spec names has no rule, or nothing implements a spec
 */
func interfacesOf(model: Model, specs: Array<InterfaceSpec>): Array<InterfaceIr> {
    specs.map {
        spec =>
        let implementors = match (spec.method) {
            case Accessor(name, typeName, many) => accessorImplementors(model, name, typeName, many)
            case Provided(_, _, _, views) => providedImplementors(model, spec.name, views)
        }
        if (implementors.isEmpty()) {
            throw GrammarException("nothing implements `${spec.name}`")
        }
        InterfaceIr(spec, implementors)
    }
}

func accessorImplementors(model: Model, name: String, typeName: String, many: Bool): Array<String> {
    let nodes = HashSet<String>()
    for (n in model.nodes where n.fields.any {f => hasAccessor(f, name, typeName, many)}) {
        nodes.add(n.name)
    }
    let decided = HashMap<String, Bool>()
    func implements(view: String): Bool {
        if (let Some(it) <- decided.get(view)) {
            return it
        }
        // an enum that refers to itself through its variants does not implement it on that account
        decided.add(view, false)
        let result = match (model.enumOf(view)) {
            case Some(e) => e.variants.all {v => implements(v.typeName)}
            case None => nodes.contains(view)
        }
        decided.add(view, result)
        result
    }
    model.grammar.rules.map {r => r.name}.filter {view => implements(view)}
}

func hasAccessor(f: FieldIr, name: String, typeName: String, many: Bool): Bool {
    match (f) {
        case NodeField(n, t, access) where n == name && t == typeName => match (access) {
            case First | Nth(_, _) => !many
            case All | AllFrom(_, _) => many
        }
        case _ => false
    }
}

func providedImplementors(model: Model, spec: String, views: Array<String>): Array<String> {
    let result = HashSet<String>()
    func add(view: String): Unit {
        if (!result.add(view)) {
            return
        }
        for (v in model.enumOf(view)?.variants ?? []) {
            add(v.typeName)
        }
    }
    for (view in views) {
        if (!model.grammar.rules.any {r => r.name == view}) {
            throw GrammarException("`${spec}` names `${view}`, which has no rule")
        }
        add(view)
    }
    model.grammar.rules.map {r => r.name}.filter {view => result.contains(view)}
}
