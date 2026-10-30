package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import cjsyntax.{CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.{
    AnyHasTypeParams,
    AnyHasWhereClause,
    Decl,
    GenericConstraint,
    NamedType,
    ParamList,
    PathSegment,
    Type,
    TypeBoundList,
    TypeParam
}
import ginkgo.{SyntaxNodePtr, TextRange}
import loupe.db.AnalysisDatabase
import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * A type of a signature, by its place among the signature's `types`.
 */
@DerivePython
public struct TypeRefId <: Equatable<TypeRefId> & Hashable & ToString {
    public TypeRefId(public let index: Int64) {}

    public operator func ==(other: TypeRefId): Bool {
        index == other.index
    }

    public operator func !=(other: TypeRefId): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        hasher.write(index)
        hasher.finish()
    }

    public func toString(): String {
        "TypeRefId(index: ${index})"
    }
}

/**
 * A segment of a path in a type, `C<T>` of `a.C<T>`: its name and its type arguments.
 */
@DerivePython
public struct TypeSegment <: Equatable<TypeSegment> {
    public TypeSegment(public let name: String, public let args: Array<TypeRefId>) {}

    public operator func ==(other: TypeSegment): Bool {
        name == other.name && args == other.args
    }

    public operator func !=(other: TypeSegment): Bool {
        !(this == other)
    }
}

/**
 * A type as a signature writes it, its names not resolved yet: rust-analyzer's `TypeRef`. What it
 * holds are other types of the same signature; a type in parentheses is the type in them.
 */
@DerivePython
public enum TypeRef <: Equatable<TypeRef> {
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

    public operator func ==(other: TypeRef): Bool {
        match ((this, other)) {
            case (TypeRef.PathRef(left0), TypeRef.PathRef(right0)) => left0 == right0
            case (TypeRef.PrimRef(left0), TypeRef.PrimRef(right0)) => left0 == right0
            case (TypeRef.TupleRef(left0), TypeRef.TupleRef(right0)) => left0 == right0
            case (TypeRef.FuncRef(left0, left1), TypeRef.FuncRef(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (TypeRef.OptionRef(left0), TypeRef.OptionRef(right0)) => left0 == right0
            case (TypeRef.ThisRef, TypeRef.ThisRef) => true
            case (TypeRef.VArrayRef(left0, left1), TypeRef.VArrayRef(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (TypeRef.MissingRef, TypeRef.MissingRef) => true
            case _ => false
        }
    }

    public operator func !=(other: TypeRef): Bool {
        !(this == other)
    }
}

/**
 * A type and its bounds, `T <: A & B` of a `where`.
 */
@DerivePython
public struct TypeBound <: Equatable<TypeBound> {
    public TypeBound(public let ty: TypeRefId, public let bounds: Array<TypeRefId>) {}

    public operator func ==(other: TypeBound): Bool {
        ty == other.ty && bounds == other.bounds
    }

    public operator func !=(other: TypeBound): Bool {
        !(this == other)
    }
}

/**
 * The types a declaration's signature writes, nothing of its body: rust-analyzer's signatures, a
 * query of each declaration apart from the item tree (D48), so that an edit to a type runs again
 * what read this declaration's, not the package's names.
 */
@DerivePython
public struct Signature <: Equatable<Signature> {
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
         * The name each of its parameters is passed by, `None` for one passed by place (`value!`
         * is `value`); as many as `params`, or none if none is named.
         */
        public let paramNames!: Array<?String> = [],
        /**
         * Whether each of its parameters has a default value; as many as `paramNames`.
         */
        public let paramDefaults!: Array<Bool> = [],
        /**
         * Whether, a `foreign` function's, it takes any number of arguments more after its
         * parameters: its `...`, none of `params`.
         */
        public let isCVariadic!: Bool = false,
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
        let list =
            { ids: Array<TypeRefId> => String.join(ids.map { one => text(one) }, delimiter: ", ") }
        match (this[id]) {
            case PathRef(segments) =>
                String
                    .join(
                        segments
                            .map {
                                segment =>
                                if (segment.args.isEmpty()) {
                                    segment.name
                                } else {
                                    "${segment.name}<${list(segment.args)}>"
                                }
                            },
                        delimiter: "."
                    )
            case PrimRef(name) => name
            case TupleRef(elements) => "(${list(elements)})"
            case FuncRef(params, ret) => "(${list(params)}) -> ${text(ret)}"
            case OptionRef(inner) => "?${text(inner)}"
            case ThisRef => "This"
            case VArrayRef(element, size) => "VArray<${text(element)}, $${size ?? "_"}>"
            case MissingRef => "_"
        }
    }

    public operator func ==(other: Signature): Bool {
        generics == other.generics && types == other.types && params == other.params &&
            paramNames == other.paramNames &&
            paramDefaults == other.paramDefaults &&
            isCVariadic == other.isCVariadic &&
            ty == other.ty &&
            supers == other.supers &&
            bounds == other.bounds
    }

    public operator func !=(other: Signature): Bool {
        !(this == other)
    }
}

/**
 * Where each type of a signature is written: the node of each, by its id, `None` for a missing
 * one. It changes with every edit that moves the declaration, which the signature does not.
 */
@DerivePython
public struct SignatureSourceMap <: Equatable<SignatureSourceMap> {
    @PyIgnore
    public let ptrs: Array<?SyntaxNodePtr<SyntaxKind>>

    @PyIgnore
    public init(ptrs: Array<?SyntaxNodePtr<SyntaxKind>>) {
        this.ptrs = ptrs
    }

    /**
     * UTF-8 ranges by TypeRefId.index, in the declaration's source or expansion text.
     * Missing type references have no range; generic syntax pointers stay inside loupe.
     */
    public prop ranges: Array<?TextRange> {
        get() {
            ptrs.map { ptr => ptr.map { one => one.range } }
        }
    }

    /**
     * The first type reference written at exactly this range, or None.
     */
    public func typeAtRange(range: TextRange): ?TypeRefId {
        for (i in 0..ptrs.size where ptrs[i].map { ptr => ptr.range } == Some(range)) {
            return TypeRefId(i)
        }
        None
    }

    /**
     * The type whose node `ptr` points to.
     */
    @PyIgnore
    public func typeAt(ptr: SyntaxNodePtr<SyntaxKind>): ?TypeRefId {
        for (i in 0..ptrs.size where ptrs[i] == ptr) {
            return TypeRefId(i)
        }
        None
    }

    public operator func ==(other: SignatureSourceMap): Bool {
        ptrs == other.ptrs
    }

    public operator func !=(other: SignatureSourceMap): Bool {
        !(this == other)
    }
}

/**
 * A declaration's signature, and where its types are written.
 */
@DerivePython
public struct LoweredSignature <: Equatable<LoweredSignature> {
    public LoweredSignature(
        public let signature: Signature,
        public let sourceMap: SignatureSourceMap
    ) {}

    public operator func ==(other: LoweredSignature): Bool {
        signature == other.signature && sourceMap == other.sourceMap
    }

    public operator func !=(other: LoweredSignature): Bool {
        !(this == other)
    }
}

/**
 * The `LoweredSignature` of `def`: of its node in a source file or an expansion; an empty one for a declaration of a
 * package compiled already, whose types its `.cjo` has resolved, or for an item no longer there.
 */
@CalcaTracked
public func signatureWithSourceMap(db: AnalysisDatabase, def: DefId): LoweredSignature {
    if (let Some((root, ids)) <- syntaxOf(db, def.file(db))) {
        if (let Some(decl) <- ids.node(def.item(db), root).flatMap { node => Decl.cast(node) }) {
            let active =
                match (def.file(db)) {
                    case Source(file) => ActiveFilter.of(db, file)
                    case _ => ALL_ACTIVE
                }
            return lowerSignature(decl, active: active)
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
 * The signature of `decl`, the parameters `active` leaves out of the build left out.
 */
func lowerSignature(decl: Decl, active!: ActiveFilter = ALL_ACTIVE): LoweredSignature {
    let lowering = SignatureLowering(active: active)
    let generics =
        match (AnyHasTypeParams.cast(decl.syntax).flatMap { it => it.typeParamList() }) {
            case Some(list) =>
                list.typeParams() |> map { param: TypeParam => param.name()?.text() ?? "" } |>
                    collectArray
            case None => Array<String>()
        }
    var params = Array<TypeRefId>()
    var ty: ?TypeRefId = None
    var supers = Array<TypeRefId>()
    match (decl) {
        case Decl.AsFuncDecl(it) =>
            (params, ty) =
                (
                    lowering.params(it.paramLists()),
                    lowering.retType(it.retType().flatMap { ret => ret.ty() })
                )
        case Decl.AsMainDecl(it) =>
            (params, ty) =
                (
                    lowering.params(it.paramLists()),
                    lowering.retType(it.retType().flatMap { ret => ret.ty() })
                )
        case Decl.AsMacroDecl(it) =>
            (params, ty) =
                (
                    lowering.params(it.paramLists()),
                    lowering.retType(it.retType().flatMap { ret => ret.ty() })
                )
        case Decl.AsInitDecl(it) => params = lowering.params(it.paramLists())
        case Decl.AsPrimaryInitDecl(it) => params = lowering.params(it.paramLists())
        case Decl.AsClassDecl(it) => supers = lowering.bounds(it.typeBoundList())
        case Decl.AsInterfaceDecl(it) => supers = lowering.bounds(it.typeBoundList())
        case Decl.AsStructDecl(it) => supers = lowering.bounds(it.typeBoundList())
        case Decl.AsEnumDecl(it) => supers = lowering.bounds(it.typeBoundList())
        case Decl.AsExtendDecl(it) =>
            (ty, supers) = (lowering.lower(it.ty()), lowering.bounds(it.typeBoundList()))
        case Decl.AsTypeAliasDecl(it) => ty = lowering.lower(it.ty())
        case Decl.AsVarDecl(it) => ty = lowering.retType(it.ty())
        case Decl.AsPropDecl(it) => ty = lowering.lower(it.ty())
        case Decl.AsEnumCtor(it) =>
            params = it.types() |> map { one => lowering.lower(one) } |> collectArray
        case _ => ()
    }
    let bounds =
        match (AnyHasWhereClause.cast(decl.syntax).flatMap { it => it.whereClause() }) {
            case Some(clause) =>
                clause.genericConstraints() |>
                    map {
                        constraint: GenericConstraint =>
                        TypeBound(
                            lowering.lower(constraint.ty()),
                            lowering.bounds(constraint.typeBoundList())
                        )
                    } |>
                    collectArray
            case None => Array<TypeBound>()
        }
    LoweredSignature(
        Signature(
            generics: generics,
            types: lowering.types.toArray(),
            params: params,
            paramNames: lowering.names,
            paramDefaults: lowering.defaults,
            isCVariadic: lowering.isCVariadic,
            ty: ty,
            supers: supers,
            bounds: bounds
        ),
        SignatureSourceMap(lowering.ptrs.toArray())
    )
}

/**
 * The types of one signature as they are lowered, and their nodes.
 */
class SignatureLowering {
    SignatureLowering(let active!: ActiveFilter = ALL_ACTIVE) {}

    let types = ArrayList<TypeRef>()
    let ptrs = ArrayList<?SyntaxNodePtr<SyntaxKind>>()
    // of the parameters `params` lowered, the name of each passed by name
    var names = Array<?String>()
    // and whether each has a default value, as many
    var defaults = Array<Bool>()
    // and whether the last is a `foreign` function's `...`, no parameter of a type
    var isCVariadic = false

    func params(lists: Iterator<ParamList>): Array<TypeRefId> {
        let ids = ArrayList<TypeRefId>()
        let found = ArrayList<?String>()
        let withDefault = ArrayList<Bool>()
        for (list in lists) {
            for (param in list.writtenParams() where active.isActive(param.syntax)) {
                if (param.dotDotDotToken().isSome()) {
                    isCVariadic = true
                    continue
                }
                withDefault.add(param.eqToken().isSome())
                ids.add(lower(param.ty()))
                found.add(if (param.bangToken().isSome()) { param.name()?.text() } else { None })
            }
        }
        if (found.iterator().any { one => one.isSome() }) {
            names = found.toArray()
            defaults = withDefault.toArray()
        }
        ids.toArray()
    }

    /**
     * A type that may be left out, a return type or a variable's: `None` then.
     */
    func retType(ty: ?Type): ?TypeRefId {
        ty.map { one => lower(one) }
    }

    func bounds(list: ?TypeBoundList): Array<TypeRefId> {
        let types = list?.types() ?? return []
        types |> map { one => lower(one) } |> collectArray
    }

    func lower(ty: ?Type): TypeRefId {
        match (ty) {
            case Some(one) => lowerType(one)
            case None => add(TypeRef.MissingRef, None)
        }
    }

    private func lowerType(ty: Type): TypeRefId {
        let lowered =
            match (ty) {
                case Type.AsPathType(it) =>
                    TypeRef
                        .PathRef(
                            it.pathSegments() |>
                                map {
                                    segment: PathSegment =>
                                    let args =
                                        match (segment.typeArgList()) {
                                            case Some(list) =>
                                                list.types() |> map { arg: Type => lower(arg) } |>
                                                    collectArray
                                            case None => Array<TypeRefId>()
                                        }
                                    TypeSegment(segment.nameRef()?.text() ?? "", args)
                                } |>
                                collectArray
                        )
                case Type.AsPrimType(it) => TypeRef.PrimRef(it.keyword()?.text() ?? "")
                case Type.AsTupleType(it) => TypeRef.TupleRef(elements(it.syntax, None))
                case Type.AsParenType(it) =>
                    return lower(it.ty() ?? it.namedType().flatMap { named => named.ty() })
                case Type.AsFuncType(it) =>
                    TypeRef
                        .FuncRef(
                            elements(it.syntax, it.arrowToken()?.textRange.start),
                            lower(it.ret())
                        )
                case Type.AsOptionType(it) => TypeRef.OptionRef(lower(it.ty()))
                case Type.AsThisType(_) => TypeRef.ThisRef
                case Type.AsVArrayType(it) =>
                    TypeRef.VArrayRef(lower(it.ty()), it.intLitToken()?.text())
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

    /**
     * The type named `name`, a path of one segment, written where no node is a type: a macro's `[…]`.
     */
    func named(name: String): TypeRefId {
        add(TypeRef.PathRef([TypeSegment(name, [])]), None)
    }

    private func add(ty: TypeRef, ptr: ?SyntaxNodePtr<SyntaxKind>): TypeRefId {
        types.add(ty)
        ptrs.add(ptr)
        TypeRefId(types.size - 1)
    }
}
