package loupe

import py_interop.*
import py_interop.internal_macros.DerivePython
import loupe.hir.{CompilerType, Todo, Ty, TypeTarget, UnknownReason}

/**
 * Resolved type structure. Child types and definitions share the originating snapshot;
 * copied names, sizes and reasons remain descriptions of that revision after cancellation.
 * FunctionType carries parameter types, return type and whether it uses the C calling convention.
 * FixedArrayType carries its element type and length. TypeParameterType names the binder's parameter.
 */
@DerivePython
@PyDoc["Resolved type structure. Child types and definitions share the originating snapshot; copied names, sizes and reasons remain descriptions of that revision after cancellation. FunctionType carries parameter types, return type and whether it uses the C calling convention. FixedArrayType carries its element type and length. TypeParameterType names the binder's parameter."]
public enum SemanticTypeKind {
    | PrimitiveType(String)
    | DeclaredType(SemanticObject, Array<SemanticType>)
    | CompilerOwnedType(CompilerType, Array<SemanticType>)
    | TupleType(Array<SemanticType>)
    | FunctionType(Array<SemanticType>, SemanticType, Bool)
    | FixedArrayType(SemanticType, Int64)
    | TypeParameterType(SemanticObject)
    | SelfType
    | InvalidType
    | UnsupportedType(Todo)
    | UnavailableType(UnknownReason)
    | InferenceVariableType
}

/**
 * A resolved type bound to the same snapshot as its semantic object. Used from one thread
 * at a time; operations throw CancelledException after an input write or request cancellation.
 * Nested types retain this context without creating another snapshot or exposing interned ids.
 */
@DerivePython
@PyDoc["A resolved type bound to the same snapshot as its semantic object. Used from one thread at a time; operations throw CancelledException after an input write or request cancellation. Nested types retain this context without creating another snapshot or exposing interned ids."]
public class SemanticType {
    @PyIgnore
    let analysis: SemanticAnalysis
    @PyIgnore
    let ty: Ty

    @PyIgnore
    init(analysis: SemanticAnalysis, ty: Ty) {
        this.analysis = analysis
        this.ty = ty
    }

    /**
     * Structure with aliases resolved; related definitions and child types need no database argument.
     * Invalid, unsupported and unavailable types retain their distinct meanings and reasons.
     */
    @PyDoc["Structure with aliases resolved; related definitions and child types need no database argument. Invalid, unsupported and unavailable types retain their distinct meanings and reasons."]
    public func kind(): SemanticTypeKind {
        let db = analysis.db
        db.unwindIfCancelled()
        match (ty.kind(db)) {
            case PrimTy(name) => PrimitiveType(name)
            case DeclTy(def, args) =>
                DeclaredType(analysis.object(NamedIdentity(Definition.DeclDef(def))), wrap(args))
            case BuiltInTy(head, args) => CompilerOwnedType(head, wrap(args))
            case TupleTy(elements) => TupleType(wrap(elements))
            case FuncTy(params, ret, isC) =>
                FunctionType(wrap(params), SemanticType(analysis, ret), isC)
            case VArrayTy(element, size) => FixedArrayType(SemanticType(analysis, element), size)
            case ParamTy(owner, index) =>
                let target =
                    match (owner) {
                        case Declaration(def) => TypeTarget.GenericOf(def, index)
                        case LocalFunction(def, local) =>
                            TypeTarget.LocalGenericOf(def, local, index)
                    }
                TypeParameterType(analysis.object(NamedIdentity(Definition.TypeParamDef(target))))
            case ThisTy => SelfType
            case ErrorTy => InvalidType
            case TodoTy(reason) => UnsupportedType(reason)
            case UnknownTy(reason) => UnavailableType(reason)
            case InferTy(_) => InferenceVariableType
        }
    }

    /**
     * Type display read from this revision; unknown/error details remain available through kind().
     */
    @PyDoc["Type display read from this revision; unknown/error details remain available through kind()."]
    public func display(): String {
        analysis.db.unwindIfCancelled()
        ty.text(analysis.db)
    }

    private func wrap(types: Array<Ty>): Array<SemanticType> {
        types.map { child => SemanticType(analysis, child) }
    }
}
