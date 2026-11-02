package loupe

import std.collection.*
import cjsyntax.{CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.PropDecl
import ginkgo.TextRange
import loupe.hir.ActiveFilter

/**
 * Checks the accessor set and signatures of a property with a body.
 */
func checkPropertyAccessors(
    node: CjSyntaxNode,
    active: ActiveFilter,
    found: ArrayList<Diagnostic>
): Unit {
    let decl = PropDecl.cast(node) ?? return
    let body = decl.propBody() ?? return
    var getters = 0
    var setters = 0
    var unknown = false
    for (accessor in body.propAccessors()) {
        if (!active.isActive(accessor.syntax)) {
            continue
        }
        let name = accessor.identToken() ?? continue
        let getter = name.text() == "get"
        if (!getter && name.text() != "set") {
            unknown = true
            continue
        }
        if ((getter && getters > 0) || (!getter && setters > 0)) {
            found
                .add(
                    Diagnostic(
                        name.textRange,
                        Severity.Error,
                        "duplicated '${name.text()}' in prop"
                    )
                )
        }
        if (getter) { getters++ } else { setters++ }
        for (params in accessor.paramLists()) {
            let count = (params.params() |> collectArray).size
            if (getter && count != 0) {
                found
                    .add(
                        Diagnostic(
                            TextRange(name.textRange.start, name.textRange.start + 1),
                            Severity.Error,
                            "getter cannot have parameter"
                        )
                    )
            } else if (!getter && count != 1) {
                let message =
                    if (count == 0) {
                        "setter must contain 1 parameter"
                    } else {
                        "setter can only accept 1 parameter"
                    }
                found.add(Diagnostic(params.syntax.textRange, Severity.Error, message))
            }
        }
    }
    // An unknown accessor already has a syntax error; do not cascade missing-accessor errors.
    if (!unknown) {
        let mutable = declarationHas(node, SyntaxKind.MutKw)
        // The compiler treats an explicitly common property with an empty body as declaration-only.
        let commonEmpty = declarationHas(node, SyntaxKind.CommonKw) && getters == 0 && setters == 0
        if (
            !commonEmpty &&
                (
                    (mutable && (getters == 0 || setters == 0)) ||
                        (!mutable && getters == 0 && setters == 0)
                )
        ) {
            found.add(Diagnostic(node.textRange, Severity.Error, "property must have accessors"))
        }
        if (!declarationHas(node, SyntaxKind.MutKw) && setters > 0) {
            found
                .add(
                    Diagnostic(
                        node.textRange,
                        Severity.Error,
                        "immutable property cannot have setter"
                    )
                )
        }
    }
}
