package loupe

import std.collection.ArrayList
import loupe.hir.TypeTarget

/**
 * A call's instantiated types, with only the hovered callable's own generic arguments.
 */
struct CallHoverSignature {
    CallHoverSignature(
        let params: Array<SemanticType>,
        let ret: SemanticType,
        let generics: Array<String>
    ) {}
}

/**
 * Use selected, complete evidence for the exact callable. Receiver and captured binders affect
 * the signature, but never become the function's own generic argument list. Failed or partial
 * inference keeps the declaration hover rather than presenting speculative substitutions.
 */
func callHoverSignature(
    call: SemanticCallResolution,
    identity: SemanticIdentity,
    parameters: Array<TypeTarget>
): ?CallHoverSignature {
    if (
        call.status != SemanticResolutionStatus.ResolvedMeaning ||
            !(call.callable().map { target => target.identity == identity } ?? false)
    ) {
        return None
    }
    let signature = call.signature() ?? return None
    if (!knownCallHoverType(signature)) {
        return None
    }
    let (params, ret) =
        match (signature.kind()) {
            case FunctionType(params, ret, _) => (params, ret)
            case _ => return None
        }
    let bindings = call.bindings()
    let generics = ArrayList<String>()
    for (parameter in parameters) {
        let selected =
            bindings
                .filter {
                    binding =>
                    binding.parameter.identity == NamedIdentity(Definition.TypeParamDef(parameter))
                }
                .get(0) ??
                return None
        if (!knownCallHoverType(selected.valueType)) {
            return None
        }
        generics.add(selected.valueType.display())
    }
    CallHoverSignature(params, ret, generics.toArray())
}

/**
 * A retained signature can still contain unavailable types after conservative inference.
 * Outer generic parameters remain valid types and must not be mistaken for inference variables.
 */
private func knownCallHoverType(value: SemanticType): Bool {
    match (value.kind()) {
        case PrimitiveType(_) | TypeParameterType(_) | SelfType => true
        case DeclaredType(_, args) => args.all { one => knownCallHoverType(one) }
        case CompilerOwnedType(_, args) => args.all { one => knownCallHoverType(one) }
        case TupleType(elements) => elements.all { one => knownCallHoverType(one) }
        case FunctionType(params, ret, _) =>
            params.all { one => knownCallHoverType(one) } && knownCallHoverType(ret)
        case FixedArrayType(element, _) => knownCallHoverType(element)
        case InvalidType | UnsupportedType(_) | UnavailableType(_) | InferenceVariableType => false
    }
}
