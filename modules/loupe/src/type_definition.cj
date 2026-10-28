package loupe

import std.collection.{collectArray, flatMap}
import cjsyntax.{CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{PathType, RefExpr}
import ginkgo.SyntaxNodePtr
import loupe.db.AnalysisDatabase
import loupe.hir.{
    BodySource,
    DefId,
    ItemFile,
    ItemKind,
    MacroCallId,
    Ty,
    TypeTarget,
    bodyWithSourceMap,
    declaredTyOf,
    expandedDeclOf,
    inferBody,
    receiverTyOf,
    scopeFileOf,
    signatureWithSourceMap,
    syntaxOf,
    writtenTypeOf
}
import loupe.vfs.FileId

/**
 * The declaration of a name's semantic type, including inferred locals and substituted members.
 * Aliases expand to their underlying type; generic instances go to their type declaration and
 * type parameters to their parameter declaration. Structural types (tuples, functions, VArray),
 * primitives and unknown types have no target. Missing or mismatched binary sources yield none.
 */
public func typeDefinitionAt(
    db: AnalysisDatabase,
    fileId: FileId,
    offset: Int64
): Array<NavigationTarget> {
    let file = db.sourceFile(fileId) ?? return []
    typeDefinitionIn(db, ItemFile.Source(file), offset)
}

/**
 * Type navigation in current macro output. Copied names go to source; generated declarations
 * may go into an expansion, using the same mapping as definition navigation.
 */
public func typeDefinitionInExpansion(
    db: AnalysisDatabase,
    call: MacroCallId,
    offset: Int64
): Array<NavigationTarget> {
    typeDefinitionIn(db, ItemFile.Expansion(call), offset)
}

/**
 * The source declaration of a semantic type, reusable by features such as type hint links.
 * Only nominal types and type parameters have targets; this does not descend into type arguments
 * or structural components. `intoExpansions` permits targets in generated macro text.
 */
func typeNavigationTarget(
    db: AnalysisDatabase,
    ty: Ty,
    intoExpansions!: Bool = false
): ?NavigationTarget {
    match (ty.kind(db)) {
        case DeclTy(def, _) => declTarget(db, def, intoExpansions: intoExpansions)
        case ParamTy(owner, index) =>
            targetOf(db, TypeTarget.GenericOf(owner, index), intoExpansions)
        case _ => None
    }
}

/**
 * Resolves the selected name before consulting its expression type: a constructor's callee has
 * a function type, but its written type name still denotes the constructed type.
 */
func typeDefinitionIn(
    db: AnalysisDatabase,
    file: ItemFile,
    offset: Int64
): Array<NavigationTarget> {
    let scope = scopeFileOf(db, file) ?? return []
    let (root, _) = syntaxOf(db, file) ?? return []
    let token = tokenAt(root, offset) ?? return []
    let item = itemAround(db, file, token.parent)
    let expansion =
        match (file) {
            case Expansion(call) => Some(call)
            case _ => None<MacroCallId>
        }
    let owner: ?DefId = item ?? expansion.flatMap { call => bodyOfExpressionExpansion(db, call) }
    let origin = if (item.isNone()) { expansion } else { None<MacroCallId> }
    let intoExpansions = expansion.isSome()
    if (let Some(def) <- owner && isDeclaredName(db, def, token)) {
        return typeTargetsOfDefinition(
            db,
            Definition.DeclDef(expandedDeclOf(db, def) ?? def),
            intoExpansions: intoExpansions
        )
    }
    let definitions = classifyName(db, scope, owner, token, expansion: origin)
    // Local generic types are not inferred yet, but a written parameter reference has an identity.
    if (let Some(defs) <- definitions && defs.size == 1 && let TypeParamDef(target) <- defs[0]) {
        return typeTargetsOfDefinition(
            db,
            Definition.TypeParamDef(target),
            intoExpansions: intoExpansions
        )
    }
    if (let Some(def) <- owner && let Some(ty) <- writtenTypeAt(db, def, token, origin)) {
        return typeTargets(db, ty, intoExpansions: intoExpansions)
    }
    if (let Some(defs) <- definitions) {
        // Inference supplies receiver substitutions; looking up the member declaration loses them.
        if (
            let Some(def) <- owner &&
                let Some(ty) <- expressionTypeAt(
                    db,
                    def,
                    token,
                    origin,
                    typeName: defs.any { one => denotesType(db, one) }
                )
        ) {
            return typeTargets(db, ty, intoExpansions: intoExpansions)
        }
        return defs |>
            flatMap {
                one: Definition =>
                typeTargetsOfDefinition(db, one, intoExpansions: intoExpansions)
            } |>
            collectArray
    }
    if (let Some(call) <- expansion && item.isNone()) {
        match (callSiteNameOf(db, call, token, offset)) {
            case Some(AtSource(at)) => return typeDefinitionAt(db, call.file(db).fileId(db), at)
            case Some(AtCall(def, resolution)) =>
                return resolutionDefinitions(def, resolution) |>
                    flatMap {
                        one: Definition =>
                        typeTargetsOfDefinition(db, one, intoExpansions: intoExpansions)
                    } |>
                    collectArray
            case None => ()
        }
    }
    []
}

/**
 * The selected complete path's type, so an alias such as `Identity<User>` keeps its arguments.
 * Qualifier segments are resolved independently by `classifyName`.
 */
func writtenTypeAt(
    db: AnalysisDatabase,
    def: DefId,
    token: CjSyntaxToken,
    expansion: ?MacroCallId
): ?Ty {
    let (node, segment) = typeAt(token) ?? return None
    let path = PathType.cast(node) ?? return None
    if (segment != (path.pathSegments() |> collectArray).size - 1) {
        return None
    }
    let ptr = SyntaxNodePtr(node)
    if (
        expansion.isNone() && let Some(id) <- signatureWithSourceMap(db, def).sourceMap.typeAt(ptr)
    ) {
        return writtenTypeOf(db, def, id)
    }
    let id =
        bodyWithSourceMap(db, def).sourceMap.typeAtSource(BodySource(ptr, expansion: expansion)) ??
            return None
    writtenTypeOf(db, def, id, inBody: true)
}

/**
 * The type of the selected reference or member access, without walking to an enclosing call.
 * A function value has no type declaration even when its return type is nominal.
 */
func expressionTypeAt(
    db: AnalysisDatabase,
    def: DefId,
    token: CjSyntaxToken,
    expansion: ?MacroCallId,
    typeName!: Bool = false
): ?Ty {
    let parent = token.parent
    let node =
        if (parent.kind == SyntaxKind.ThisExpr || parent.kind == SyntaxKind.SuperExpr) {
            parent
        } else {
            let outer = parent.parent ?? return None
            RefExpr.cast(outer).map { it => it.syntax } ?? accessNodeOf(outer) ?? return None
        }
    let expr =
        bodyWithSourceMap(db, def)
            .sourceMap
            .exprAtSource(BodySource(SyntaxNodePtr(node), expansion: expansion)) ??
            return None
    if (typeName) { receiverTyOf(db, def, expr) } else { inferBody(db, def)[expr] }
}

/**
 * Whether a name denotes a type rather than a value whose expression type should be used.
 */
func denotesType(db: AnalysisDatabase, definition: Definition): Bool {
    match (definition) {
        case DeclDef(def) =>
            match (def.item(db).kind) {
                case Class | Struct | Interface | Enum | BuiltIn | TypeAlias => true
                case _ => false
            }
        case TypeParamDef(_) => true
        case _ => false
    }
}

/**
 * Declaration-side types, also used when there is no value expression at the selected name.
 */
func typeTargetsOfDefinition(
    db: AnalysisDatabase,
    definition: Definition,
    intoExpansions!: Bool
): Array<NavigationTarget> {
    let ty =
        match (definition) {
            case DeclDef(def) =>
                match (def.item(db).kind) {
                    case Func | Main | Macro | Finalizer => return []
                    case _ => declaredTyOf(db, def)
                }
            case LocalDef(owner, local) => inferBody(db, owner)[local] ?? return []
            case MemberParamDef(owner, local) => inferBody(db, owner)[local] ?? return []
            case TypeParamDef(target) =>
                return match (targetOf(db, target, intoExpansions)) {
                    case Some(one) => [one]
                    case None => []
                }
            case PackageDef(_) => return []
        }
    typeTargets(db, ty, intoExpansions: intoExpansions)
}

/**
 * The optional target as a navigation result.
 */
func typeTargets(db: AnalysisDatabase, ty: Ty, intoExpansions!: Bool): Array<NavigationTarget> {
    match (typeNavigationTarget(db, ty, intoExpansions: intoExpansions)) {
        case Some(one) => [one]
        case None => []
    }
}
