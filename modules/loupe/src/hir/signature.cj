package loupe.hir

import std.collection.*
import std.deriving.*
import ginkgo.SyntaxNodePtr
import cjsyntax.{CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.{AnyHasTypeParams, AnyHasWhereClause, Decl, GenericConstraint, NamedType, ParamList, PathSegment, Type,
    TypeBoundList, TypeParam}
import calca.*
import calca.macros.*
import loupe.db.AnalysisDatabase
import loupe.syntax.parse

/**
 * A type of a signature, by its place among the signature's `types`.
 */
@Derive[Equatable, Hashable, ToString]
public struct TypeRefId {
    public TypeRefId(public let index: Int64) {}
}

/**
 * A segment of a path in a type, `C<T>` of `a.C<T>`: its name and its type arguments.
 */
@Derive[Equatable]
public struct TypeSegment {
    public TypeSegment(public let name: String, public let args: Array<TypeRefId>) {}
}

/**
 * A type as a signature writes it, its names not resolved yet: rust-analyzer's `TypeRef`. What it
 * holds are other types of the same signature; a type in parentheses is the type in them.
 */
@Derive[Equatable]
public enum TypeRef {
    /**
     * `a.C<T>`: what each segment names is resolution's (`resolveTypePath`).
     */
    | PathRef(Array<TypeSegment>)
    /**
     * `Int64`, `Unit`: a keyword, no name.
     */
    | PrimRef(String)
    | TupleRef(Array<TypeRefId>)
    | FuncRef(Array<TypeRefId>, TypeRefId)
    /**
     * `?T`: `std.core`'s `Option` whatever `Option` names in the file (N58).
     */
    | OptionRef(TypeRefId)
    | ThisRef
    /**
     * `VArray<T, $n>`, its size as written; `None` if the parser did not find it.
     */
    | VArrayRef(TypeRefId, ?String)
    /**
     * A type the declaration does not write, or the parser did not find.
     */
    | MissingRef
}

/**
 * A type and its bounds, `T <: A & B` of a `where`.
 */
@Derive[Equatable]
public struct TypeBound {
    public TypeBound(public let ty: TypeRefId, public let bounds: Array<TypeRefId>) {}
}

/**
 * The types a declaration's signature writes, nothing of its body: rust-analyzer's signatures, a
 * query of each declaration apart from the item tree (D48), so that an edit to a type runs again
 * what read this declaration's, not the package's names.
 */
@Derive[Equatable]
public struct Signature {
    public Signature(
        /**
         * Its type parameters by name, in order.
         */
        public let generics!: Array<String> = [],
        /**
         * Every type it writes, one inside another before it.
         */
        public let types!: Array<TypeRef> = [],
        /**
         * Those of its parameters, of every list in order; an enum constructor's.
         */
        public let params!: Array<TypeRefId> = [],
        /**
         * Its declared type: a function's return type, a variable's or property's type, what an
         * alias names, the type an `extend` extends.
         */
        public let ty!: ?TypeRefId = None,
        /**
         * The types after `<:`: a type's supertypes, an `extend`'s interfaces.
         */
        public let supers!: Array<TypeRefId> = [],
        /**
         * Its `where`.
         */
        public let bounds!: Array<TypeBound> = []
    ) {}

    public operator func [](id: TypeRefId): TypeRef {
        types[id.index]
    }

    /**
     * `id` as written, but for whitespace and parameter names: `a.C<?Int64>`, `(Int64) -> Unit`.
     */
    public func text(id: TypeRefId): String {
        let list = {ids: Array<TypeRefId> => String.join(ids.map {one => text(one)}, delimiter: ", ")}
        match (this[id]) {
            case PathRef(segments) => String.join(segments.map {
                segment => if (segment.args.isEmpty()) {
                    segment.name
                } else {
                    "${segment.name}<${list(segment.args)}>"
                }
            }, delimiter: ".")
            case PrimRef(name) => name
            case TupleRef(elements) => "(${list(elements)})"
            case FuncRef(params, ret) => "(${list(params)}) -> ${text(ret)}"
            case OptionRef(inner) => "?${text(inner)}"
            case ThisRef => "This"
            case VArrayRef(element, size) => "VArray<${text(element)}, $${size ?? "_"}>"
            case MissingRef => "_"
        }
    }
}

/**
 * Where each type of a signature is written: the node of each, by its id, `None` for a missing
 * one. It changes with every edit that moves the declaration, which the signature does not.
 */
@Derive[Equatable]
public struct SignatureSourceMap {
    public SignatureSourceMap(public let ptrs: Array<?SyntaxNodePtr<SyntaxKind>>) {}

    /**
     * The type whose node `ptr` points to.
     */
    public func typeAt(ptr: SyntaxNodePtr<SyntaxKind>): ?TypeRefId {
        for (i in 0..ptrs.size where ptrs[i] == ptr) {
            return TypeRefId(i)
        }
        None
    }
}

/**
 * A declaration's signature, and where its types are written.
 */
@Derive[Equatable]
public struct LoweredSignature {
    public LoweredSignature(public let signature: Signature, public let sourceMap: SignatureSourceMap) {}
}

/**
 * The `LoweredSignature` of `def`: of its node in a source file; an empty one for a declaration of a
 * package compiled already, whose types its `.cjo` has resolved, or for an item no longer there.
 */
@CalcaTracked
public func signatureWithSourceMap(db: AnalysisDatabase, def: DefId): LoweredSignature {
    if (let Source(file) <- def.file(db)) {
        let root = parse(db, file).syntaxNode()
        if (let Some(decl) <- itemIdMap(db, file).node(def.item(db), root).flatMap {node => Decl.cast(node)}) {
            return lowerSignature(decl)
        }
    }
    LoweredSignature(Signature(), SignatureSourceMap([]))
}

/**
 * The `Signature` of `def`. An edit of the file but of its types leaves it equal, and what read it
 * is not run again.
 */
@CalcaTracked
public func signature(db: AnalysisDatabase, def: DefId): Signature {
    signatureWithSourceMap(db, def).signature
}

/**
 * The signature of `decl`.
 */
func lowerSignature(decl: Decl): LoweredSignature {
    let lowering = SignatureLowering()
    let generics = match (AnyHasTypeParams.cast(decl.syntax).flatMap {it => it.typeParamList()}) {
        case Some(list) => list.typeParams() |> map {param: TypeParam => param.name()?.text() ?? ""} |> collectArray
        case None => Array<String>()
    }
    var params = Array<TypeRefId>()
    var ty: ?TypeRefId = None
    var supers = Array<TypeRefId>()
    match (decl) {
        case Decl.AsFuncDecl(it) => (params, ty) = (lowering.params(it.paramLists()), lowering.retType(it.retType().flatMap {ret => ret.ty()}))
        case Decl.AsMainDecl(it) => (params, ty) = (lowering.params(it.paramLists()), lowering.retType(it.retType().flatMap {ret => ret.ty()}))
        case Decl.AsMacroDecl(it) => (params, ty) = (lowering.params(it.paramLists()), lowering.retType(it.retType().flatMap {ret => ret.ty()}))
        case Decl.AsInitDecl(it) => params = lowering.params(it.paramLists())
        case Decl.AsPrimaryInitDecl(it) => params = lowering.params(it.paramLists())
        case Decl.AsClassDecl(it) => supers = lowering.bounds(it.typeBoundList())
        case Decl.AsInterfaceDecl(it) => supers = lowering.bounds(it.typeBoundList())
        case Decl.AsStructDecl(it) => supers = lowering.bounds(it.typeBoundList())
        case Decl.AsEnumDecl(it) => supers = lowering.bounds(it.typeBoundList())
        case Decl.AsExtendDecl(it) => (ty, supers) = (lowering.lower(it.ty()), lowering.bounds(it.typeBoundList()))
        case Decl.AsTypeAliasDecl(it) => ty = lowering.lower(it.ty())
        case Decl.AsVarDecl(it) => ty = lowering.retType(it.ty())
        case Decl.AsPropDecl(it) => ty = lowering.lower(it.ty())
        case Decl.AsEnumCtor(it) => params = it.types() |> map {one => lowering.lower(one)} |> collectArray
        case _ => ()
    }
    let bounds = match (AnyHasWhereClause.cast(decl.syntax).flatMap {it => it.whereClause()}) {
        case Some(clause) => clause.genericConstraints() |> map {
            constraint: GenericConstraint => TypeBound(lowering.lower(constraint.ty()), lowering.bounds(constraint.typeBoundList()))
        } |> collectArray
        case None => Array<TypeBound>()
    }
    LoweredSignature(
        Signature(generics: generics, types: lowering.types.toArray(), params: params, ty: ty, supers: supers, bounds: bounds),
        SignatureSourceMap(lowering.ptrs.toArray())
    )
}

/**
 * The types of one signature as they are lowered, and their nodes.
 */
class SignatureLowering {
    let types = ArrayList<TypeRef>()
    let ptrs = ArrayList<?SyntaxNodePtr<SyntaxKind>>()

    func params(lists: Iterator<ParamList>): Array<TypeRefId> {
        let ids = ArrayList<TypeRefId>()
        for (list in lists) {
            for (param in list.params()) {
                ids.add(lower(param.ty()))
            }
        }
        ids.toArray()
    }

    /**
     * A type that may be left out, a return type or a variable's: `None` then.
     */
    func retType(ty: ?Type): ?TypeRefId {
        ty.map {one => lower(one)}
    }

    func bounds(list: ?TypeBoundList): Array<TypeRefId> {
        let types = list?.types() ?? return []
        types |> map {one => lower(one)} |> collectArray
    }

    func lower(ty: ?Type): TypeRefId {
        match (ty) {
            case Some(one) => lowerType(one)
            case None => add(TypeRef.MissingRef, None)
        }
    }

    private func lowerType(ty: Type): TypeRefId {
        let lowered = match (ty) {
            case Type.AsPathType(it) => TypeRef.PathRef(it.pathSegments() |> map {
                segment: PathSegment =>
                let args = match (segment.typeArgList()) {
                    case Some(list) => list.types() |> map {arg: Type => lower(arg)} |> collectArray
                    case None => Array<TypeRefId>()
                }
                TypeSegment(segment.nameRef()?.text() ?? "", args)
            } |> collectArray)
            case Type.AsPrimType(it) => TypeRef.PrimRef(it.keyword()?.text() ?? "")
            case Type.AsTupleType(it) => TypeRef.TupleRef(elements(it.syntax, None))
            case Type.AsParenType(it) => return lower(it.ty() ?? it.namedType().flatMap {named => named.ty()})
            case Type.AsFuncType(it) => TypeRef.FuncRef(elements(it.syntax, it.arrowToken()?.textRange.start), lower(it.ret()))
            case Type.AsOptionType(it) => TypeRef.OptionRef(lower(it.ty()))
            case Type.AsThisType(_) => TypeRef.ThisRef
            case Type.AsVArrayType(it) => TypeRef.VArrayRef(lower(it.ty()), it.intLitToken()?.text())
        }
        add(lowered, SyntaxNodePtr(ty.syntax))
    }

    /**
     * The types of a tuple or of a function's parameters, named or not, in order: those before
     * `end`, the function's arrow.
     */
    private func elements(node: CjSyntaxNode, end: ?Int64): Array<TypeRefId> {
        let ids = ArrayList<TypeRefId>()
        for (child in node.children() where child.textRange.end <= (end ?? Int64.Max)) {
            if (let Some(one) <- Type.cast(child)) {
                ids.add(lowerType(one))
            } else if (let Some(named) <- NamedType.cast(child)) {
                ids.add(lower(named.ty()))
            }
        }
        ids.toArray()
    }

    private func add(ty: TypeRef, ptr: ?SyntaxNodePtr<SyntaxKind>): TypeRefId {
        types.add(ty)
        ptrs.add(ptr)
        TypeRefId(types.size - 1)
    }
}
