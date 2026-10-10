package loupe.hir

import std.collection.*
import std.convert.Parsable
import std.deriving.*
import calca.*
import calca.macros.*
import cjo.{CjoException, DeclInfo, FullId, openCjo, SemaTy, SemaTyInfo, TypeKind}
import cjo.Decl as CjoDecl
import cjo.Package as CjoPackage
import loupe.db.{AnalysisDatabase, BinaryPackageFile}

/**
 * A type and its bounds, `T <: A & B` of a `where`, as types.
 */
@Derive[Equatable]
public struct TyBound {
    public TyBound(public let ty: Ty, public let bounds: Array<Ty>) {}
}

/**
 * Why a type of a signature is an error, as cjc says it.
 */
@Derive[Equatable]
public enum TyErrorKind {
    /**
     * A path whose name is no type of the scope (N89), an alias's own in its type (N93).
     */
    | UndeclaredType(String)
    /**
     * A path whose name is no type, but a function, a variable or a package of the scope (N94).
     */
    | NotAType(String)
    /**
     * A generic type written with no type arguments (N90).
     */
    | NeedsTypeArgs
    /**
     * As many type arguments as the type has no parameters (N91).
     */
    | WrongTypeArgCount
    /**
     * `This` where it is not the return type of an instance function of a class (N88); `here` if
     * it is of a static one.
     */
    | ThisNotAllowed(Bool)
    /**
     * An alias that expands to itself, by the names around the cycle (N92).
     */
    | TypeCycle(Array<String>)
}

/**
 * A type of a signature that is an error: the type, by its id in the signature, and why.
 */
@Derive[Equatable]
public struct TyError {
    public TyError(public let at: TypeRefId, public let kind: TyErrorKind) {}

    public func message(): String {
        match (kind) {
            case UndeclaredType(name) => "undeclared type name '${name}'"
            case NotAType(name) => "'${name}' is not a type"
            case NeedsTypeArgs => "generic type should be used with type argument"
            case WrongTypeArgCount => "type argument's number does not match type parameter's number"
            case ThisNotAllowed(here) where here => "'This' type is not allowed here"
            case ThisNotAllowed(_) => "'This' type is not allowed"
            case TypeCycle(names) => "type cycle detected: '${String.join(names, delimiter: "->")}'"
        }
    }
}

/**
 * A declaration's signature as types (D54): what `Signature` writes, each `TypeRef` lowered to a
 * `Ty`, or what a `.cjo` resolved. One query of each declaration, as `signature` is.
 */
@Derive[Equatable]
public struct SignatureTypes {
    public SignatureTypes(
        /**
         * Its type parameters by name, in order: a `ParamTy` of it is by its place among them.
         */
        public let generics!: Array<String> = [],
        /**
         * Those of its parameters, of every list in order; an enum constructor's.
         */
        public let params!: Array<Ty> = [],
        /**
         * The name each of its parameters is passed by, `None` for one passed by place; as many as
         * `params`, or none if none is named.
         */
        public let paramNames!: Array<?String> = [],
        /**
         * What a declaration is a value or a type of: a function's return type, a variable's or
         * property's type, the type an `extend` extends, what an alias expands to; a type's own,
         * its parameters its arguments (`C<T>`); a constructor's, an `init`'s or an enum
         * constructor's, its type's. `None` where it is not written: inference's.
         */
        public let ty!: ?Ty = None,
        /**
         * The types after `<:`: a type's supertypes, an `extend`'s interfaces; a class's superclass
         * first, `Object` if it names none, as cjc adds it.
         */
        public let supers!: Array<Ty> = [],
        /**
         * Its `where`, as written: not the bounds cjc adds to an `extend` of a generic type.
         */
        public let bounds!: Array<TyBound> = [],
        /**
         * The types of its source that are errors; none of a `.cjo`, which cjc checked.
         */
        public let errors!: Array<TyError> = []
    ) {}

    /**
     * The signature as a declaration of `kind` reads, for a test or a hover: `<T>(T, Int64) ->
     * Array<T>`, `C<T> <: I<T> where T <: J`, `= (Int64, Int64)`; `_` for a type not written.
     */
    public func text(db: AnalysisDatabase, kind: ItemKind): String {
        let list = {tys: Array<Ty>, delimiter: String => String.join(tys.map {one => one.text(db)}, delimiter: delimiter)}
        let generic = if (generics.isEmpty()) {
            ""
        } else {
            "<${String.join(generics, delimiter: ", ")}>"
        }
        let declared = ty.map {one => one.text(db)} ?? "_"
        let inherited = if (supers.isEmpty()) {
            ""
        } else {
            " <: ${list(supers, " & ")}"
        }
        let head = match (kind) {
            case Func | Main | Macro | Init | PrimaryInit | Finalizer => "${generic}(${list(params, ", ")}) -> ${declared}"
            case EnumCtor where params.isEmpty() => declared
            case EnumCtor => "(${list(params, ", ")}) -> ${declared}"
            case Class | Interface | Struct | Enum | BuiltIn => declared + inherited
            case Extend => "${generic} ${declared}${inherited}".trimAscii()
            case TypeAlias => "${generic} = ${declared}".trimAscii()
            case _ => declared
        }
        if (bounds.isEmpty()) {
            head
        } else {
            head + " where " + String.join(bounds.map {bound => "${bound.ty.text(db)} <: ${list(bound.bounds, " & ")}"},
                delimiter: ", ")
        }
    }
}

/**
 * The `SignatureTypes` of `def`: of its node in a source file, lowered from its `Signature` in its
 * `TypeScope`; of its declaration in a `.cjo`, from the types cjc resolved; an empty one for an
 * item no longer there. Only an alias reads another's, and one on a cycle reads none of the cycle,
 * so a cycle here is a bug of the search for them (A14).
 */
@CalcaTracked[cycleResult: signatureTypesOnCycle]
public func signatureTypes(db: AnalysisDatabase, def: DefId): SignatureTypes {
    match (def.file(db)) {
        case Source(_) | Expansion(_) => SourceTyLowering(db, def).lower()
        case Binary(pkg, index) => lowerBinarySignature(db, def, pkg, BinaryItem(index, def.item(db)))
    }
}

/**
 * The `SignatureTypes` of an alias calca finds on a cycle the search for them missed: its type an
 * error (N92).
 */
func signatureTypesOnCycle(db: AnalysisDatabase, def: DefId): SignatureTypes {
    let sig = signature(db, def)
    let cycle = aliasCycleOf(db, def) ?? [def, def]
    let errors = match (sig.ty) {
        case Some(at) => [TyError(at, TyErrorKind.TypeCycle(cycle.map {id => aliasName(db, id)}))]
        case None => Array<TyError>()
    }
    SignatureTypes(generics: sig.generics, ty: Ty(db, ErrorTy), errors: errors)
}

/**
 * The aliases from `def` around back to it, `def` first and last (`X->Y->X`), found as cjc finds
 * them: depth first, in the order of the types of each alias, a path's arguments before it; `None`
 * if none leads back, `def` on no cycle.
 */
func aliasCycleOf(db: AnalysisDatabase, def: DefId): ?Array<DefId> {
    aliasPath(db, def, def, HashSet<DefId>([def]))
}

/**
 * A path of aliases from `from` to `to`, each named by the type of the one before, through none of
 * `visited`; `from` first, `to` last.
 */
func aliasPath(db: AnalysisDatabase, from: DefId, to: DefId, visited: HashSet<DefId>): ?Array<DefId> {
    for (next in aliasesNamedBy(db, from)) {
        if (next == to) {
            return [from, to]
        }
        if (!visited.contains(next)) {
            visited.add(next)
            if (let Some(rest) <- aliasPath(db, next, to, visited)) {
                return [from].concat(rest)
            }
        }
    }
    None
}

func aliasName(db: AnalysisDatabase, def: DefId): String {
    declItemOf(db, def).flatMap {item => item.names.get(0)} ?? ""
}

/**
 * The aliases the type of the alias `def` names, in the order its types are written, but itself,
 * which it does not see (N93); none of a `.cjo`'s, which name no source's.
 */
func aliasesNamedBy(db: AnalysisDatabase, def: DefId): Array<DefId> {
    let sig = signature(db, def)
    let scope = typeScopeOf(db, def) ?? return []
    let found = ArrayList<DefId>()
    for (ty in sig.types) {
        if (let PathRef(segments) <- ty) {
            let resolved = resolveTypePath(db, scope, segments.map {segment => segment.name})
            if (let Some(Resolved(TypeOf(id))) <- resolved.get(resolved.size - 1) && id != def &&
                id.item(db).kind == ItemKind.TypeAlias) {
                found.add(id)
            }
        }
    }
    found.toArray()
}

/**
 * The type parameters of `def` by name, read without lowering its types: a source declaration's
 * from its `Signature`, a `.cjo`'s from its declaration, as a path naming it counts its arguments
 * against them (N90, N91) and a type of a cycle of supertypes (`class A <: I<B>`, `class B <:
 * I<A>`) needs no other's types.
 */
public func genericsOf(db: AnalysisDatabase, def: DefId): Array<String> {
    match (def.file(db)) {
        case Source(_) | Expansion(_) => signature(db, def).generics
        case Binary(pkg, index) => binaryGenericsOf(db, pkg, BinaryItem(index, def.item(db)))
    }
}

/**
 * The type parameters of the declaration `item` of the `.cjo` of `pkg` by name; none for a
 * declaration it does not have, or bytes that break where they are read.
 */
@CalcaTracked
func binaryGenericsOf(db: AnalysisDatabase, pkg: BinaryPackageFile, item: BinaryItem): Array<String> {
    let index = binaryExports(db, pkg).declIndex(item) ?? return []
    let bytes = pkg.bytes(db)
    try {
        let cjo = openCjo(bytes)
        genericDeclsOf(cjo.allDecls[index]).map {param => cjo.allDecls[Int64(param) - 1].identifier ?? ""}
    } catch (_: CjoException) {
        []
    } catch (_: IndexOutOfBoundsException) {
        []
    }
}

/**
 * The item of `def`, a member of a type or an `extend` as well as a declaration of a file.
 */
public func declItemOf(db: AnalysisDatabase, def: DefId): ?Item {
    if (let Some(item) <- itemOf(db, def)) {
        return item
    }
    let parent = parentOf(db, def) ?? return None
    let id = def.item(db)
    let owner = itemOf(db, parent) ?? return None
    owner.members.iterator().filter {member => member.id == id}.next()
}

/**
 * The self type of `def`, a type: itself, its type parameters its arguments (`C<T>`).
 */
func selfTyOf(db: AnalysisDatabase, def: DefId): Ty {
    let count = genericsOf(db, def).size
    Ty(db, DeclTy(def, Array(count) {i => Ty(db, ParamTy(def, i))}))
}

/**
 * One source declaration's signature as it is lowered, or the types its body writes: its types, by
 * id, and the errors found.
 */
class SourceTyLowering {
    private let sig: Signature
    private let types: Array<TypeRef>
    /**
     * Whether `types` are the body's: a path there may name a type parameter of a local function
     * (N68), and `This` is not its declaration's return type.
     */
    private let inBody: Bool
    private let scope: ?TypeScope
    private let parent: ?DefId
    /**
     * The cycle of aliases of an alias on one (N92): its type an error, and no alias of the cycle
     * expanded in it.
     */
    private let cycle: ?Array<DefId>
    private let errors = ArrayList<TyError>()

    SourceTyLowering(private let db: AnalysisDatabase, private let def: DefId) {
        sig = signature(db, def)
        types = sig.types
        inBody = false
        scope = typeScopeOf(db, def)
        parent = scope?.generics.get(1)?.owner
        cycle = if (def.item(db).kind == ItemKind.TypeAlias) {
            aliasCycleOf(db, def)
        } else {
            None
        }
    }

    /**
     * The lowering of the types `body`, the body of `def`, writes.
     */
    init(db: AnalysisDatabase, def: DefId, body: Body) {
        this.db = db
        this.def = def
        sig = signature(db, def)
        types = body.types
        inBody = true
        scope = typeScopeOf(db, def)
        parent = scope?.generics.get(1)?.owner
        cycle = None
    }

    /**
     * The type `id` of the body.
     */
    func lowerType(id: TypeRefId): Ty {
        lowerAt(id)
    }

    func lower(): SignatureTypes {
        let kind = def.item(db).kind
        let params = sig.params.map {id => lowerAt(id)}
        let ty = match (kind) {
            case Class | Interface | Struct | Enum => selfTyOf(db, def)
            case Init | PrimaryInit | EnumCtor => match (parent) {
                case Some(one) => selfTyOf(db, one)
                case None => Ty(db, ErrorTy)
            }
            case _ => sig.ty.map {id => lowerAt(id)}
        }
        let written = sig.supers.map {id => lowerAt(id)}
        let supers = if (kind == ItemKind.Class) {
            withSuperclass(written)
        } else {
            written
        }
        let bounds = sig.bounds.map {bound => TyBound(lowerAt(bound.ty), bound.bounds.map {id => lowerAt(id)})}
        if (let Some(names) <- cycle && let Some(at) <- sig.ty) {
            errors.add(TyError(at, TyErrorKind.TypeCycle(names.map {id => aliasName(db, id)})))
            return SignatureTypes(generics: sig.generics, ty: Ty(db, ErrorTy), errors: errors.toArray())
        }
        SignatureTypes(generics: sig.generics, params: params, paramNames: sig.paramNames, ty: ty, supers: supers,
            bounds: bounds, errors: errors.toArray())
    }

    /**
     * The supertypes of a class, `supers`, `std.core`'s `Object` first if none of them is a class
     * (N79): cjc adds it, and a `.cjo` keeps it.
     */
    private func withSuperclass(supers: Array<Ty>): Array<Ty> {
        let named = supers.iterator().any {
            one => match (one.kind(db)) {
                case DeclTy(id, _) => id.item(db).kind == ItemKind.Class
                case _ => false
            }
        }
        let object = scope.flatMap {one => langItem(db, PackageRef.Source(one.pkg), LangItem.ObjectClass)}
        match (object) {
            case Some(id) where !named && id != def => [Ty(db, DeclTy(id, []))].concat(supers)
            case _ => supers
        }
    }

    /**
     * The type `id` of the signature, or of the body.
     */
    private func lowerAt(id: TypeRefId): Ty {
        let kind = match (types[id.index]) {
            case PrimRef(name) where name.isEmpty() => ErrorTy
            case PrimRef(name) => PrimTy(name)
            case TupleRef(elements) => TupleTy(elements.map {one => lowerAt(one)})
            case FuncRef(params, ret) => FuncTy(params.map {one => lowerAt(one)}, lowerAt(ret), false)
            case OptionRef(inner) =>
                let element = lowerAt(inner)
                match (optionDecl()) {
                    case Some(option) => DeclTy(option, [element])
                    case None => TodoTy(Todo.NoStd)
                }
            case ThisRef => thisAt(id)
            case VArrayRef(element, size) =>
                let lowered = lowerAt(element)
                match (size.flatMap {text: String => Int64.tryParse(text)}) {
                    case Some(n) => VArrayTy(lowered, n)
                    case None => ErrorTy
                }
            case PathRef(segments) => return lowerPath(id, segments)
            case MissingRef => ErrorTy
        }
        Ty(db, kind)
    }

    /**
     * `This` at `id`: allowed as the whole return type of an instance function of a class (N88).
     */
    private func thisAt(id: TypeRefId): TyKind {
        let owner = parent.filter {one => one.item(db).kind == ItemKind.Class}
        let isMethod = def.item(db).kind == ItemKind.Func && owner.isSome()
        let isStatic = owner.flatMap {one => itemOf(db, one)}.flatMap {
            item => item.members.iterator().filter {member => member.id == def.item(db)}.next()
        }.map {member => member.has(Modifier.Static)} ?? false
        if (!inBody && isMethod && !isStatic && sig.ty == Some(id)) {
            return ThisTy
        }
        errors.add(TyError(id, TyErrorKind.ThisNotAllowed(isMethod && isStatic)))
        ErrorTy
    }

    /**
     * The type the path `segments` at `id` names, its last segment's arguments lowered: what
     * `resolveTypePath` resolves it to, an alias expanded.
     */
    private func lowerPath(id: TypeRefId, segments: Array<TypeSegment>): Ty {
        let last = segments.get(segments.size - 1) ?? return Ty(db, ErrorTy)
        let args = last.args.map {arg => lowerAt(arg)}
        let typeScope = scope ?? return Ty(db, ErrorTy)
        let names = segments.map {segment => segment.name}
        let resolved = if (inBody) {
            resolveBodyTypePath(db, def, id, names)
        } else {
            resolveTypePath(db, typeScope, names)
        }
        match (resolved.get(resolved.size - 1)) {
            // an alias does not see its own name in its type (N93)
            case Some(Resolved(TypeOf(target))) where target == def && target.item(db).kind == ItemKind.TypeAlias =>
                errors.add(TyError(id, TyErrorKind.UndeclaredType(last.name)))
                Ty(db, ErrorTy)
            case Some(Resolved(TypeOf(target))) => applied(id, target, args)
            case Some(Resolved(GenericOf(owner, index))) =>
                if (!args.isEmpty()) {
                    errors.add(TyError(id, TyErrorKind.WrongTypeArgCount))
                }
                Ty(db, ParamTy(owner, index))
            case Some(UnresolvedPath) =>
                unresolved(id, typeScope, segments, resolved)
                Ty(db, ErrorTy)
            // a local function's type parameter: no `Ty` yet (8c)
            case Some(Resolved(LocalGenericOf(_, _, _))) => Ty(db, TodoTy(Todo.LocalGeneric))
            // a type ambiguous, packages conflicting: errors of names
            case _ => Ty(db, ErrorTy)
        }
    }

    /**
     * An error for each segment of the path `segments` at `id` that `resolved` leaves unresolved, up
     * to one ambiguous: a name of nothing (N89), of something but a type (N94), or one after a type
     * or a type parameter (N95).
     */
    private func unresolved(id: TypeRefId, typeScope: TypeScope, segments: Array<TypeSegment>,
        resolved: Array<PathResolution>): Unit {
        for (i in 0..resolved.size) {
            let name = segments[i].name
            match (resolved[i]) {
                case UnresolvedPath =>
                    let named = match (resolved.get(i - 1)) {
                        case None => isValueNamed(typeScope, name)
                        case Some(Resolved(QualifierOf(pkg))) => isExportNamed(typeScope, pkg, name)
                        case _ => false
                    }
                    errors.add(TyError(id, if (named) {
                        TyErrorKind.NotAType(name)
                    } else {
                        TyErrorKind.UndeclaredType(name)
                    }))
                case Resolved(_) => ()
                case _ => return
            }
        }
    }

    /**
     * Whether `name` is a function, a variable or a package of `typeScope`; cjc counts a
     * constructor as nothing (N94).
     */
    private func isValueNamed(typeScope: TypeScope, name: String): Bool {
        match (lookUp(db, typeScope.pkg, typeScope.file, name, Namespace.Values)) {
            case Found(_) | FoundPackage(_) | Ambiguous(_) => true
            case _ => false
        }
    }

    /**
     * Whether `pkg` exports something named `name` that `typeScope`'s package sees.
     */
    private func isExportNamed(typeScope: TypeScope, pkg: PackageRef, name: String): Bool {
        let relation = relationOf(typeScope.pkg.name(db), nameOf(db, pkg))
        !visibleOf(packageExports(db, pkg).names.get(name) ?? [], relation, Visibility.Private).isEmpty()
    }

    /**
     * The declaration `target` applied to `args`, as many as its type parameters (N90, N91): an
     * alias expanded, but one of the cycle `def` is on; `CFunc<F>` a C function type, its one
     * argument counted first (N96).
     */
    private func applied(id: TypeRefId, target: DefId, args: Array<Ty>): Ty {
        let isCFunc = target.item(db).kind == ItemKind.BuiltIn && isNamed(db, target, "CFunc")
        let count = genericsOf(db, target).size
        let fitted = if (args.size == count) {
            args
        } else {
            errors.add(TyError(id, if (args.isEmpty() && !isCFunc) {
                TyErrorKind.NeedsTypeArgs
            } else {
                TyErrorKind.WrongTypeArgCount
            }))
            Array(count) {i => args.get(i) ?? Ty(db, ErrorTy)}
        }
        match (target.item(db).kind) {
            case TypeAlias where cycle.isSome() && aliasPath(db, target, def, HashSet<DefId>([target])).isSome() =>
                Ty(db, ErrorTy)
            case TypeAlias =>
                let aliased = signatureTypes(db, target).ty ?? Ty(db, ErrorTy)
                substitute(db, aliased, target, fitted)
            case BuiltIn where isCFunc => match (fitted.get(0).map {one => one.kind(db)}) {
                case Some(FuncTy(params, ret, _)) => Ty(db, FuncTy(params, ret, true))
                case _ => Ty(db, ErrorTy)
            }
            case _ => Ty(db, DeclTy(target, fitted))
        }
    }

    private func optionDecl(): ?DefId {
        let pkg = scope?.pkg ?? return None
        langItem(db, PackageRef.Source(pkg), LangItem.OptionEnum)
    }
}

/**
 * The `SignatureTypes` of the declaration `item` of the `.cjo` of `pkg`, `def`, from the types cjc
 * resolved; an empty one for a declaration it does not have, or bytes that break where they are
 * read.
 */
func lowerBinarySignature(db: AnalysisDatabase, def: DefId, pkg: BinaryPackageFile, item: BinaryItem): SignatureTypes {
    let index = binaryExports(db, pkg).declIndex(item) ?? return SignatureTypes()
    let parent = parentOf(db, def)
    let parentIndex = parent.flatMap {
        one => binaryExports(db, pkg).declIndex(BinaryItem(item.file, one.item(db)))
    }
    let bytes = pkg.bytes(db)
    // what the bytes throw alone: a calca call under it unwinds through (A21)
    try {
        BinaryTyLowering(index, parent, parentIndex, db, pkg, openCjo(bytes), def).lower()
    } catch (_: CjoException) {
        SignatureTypes()
    } catch (_: IndexOutOfBoundsException) {
        SignatureTypes()
    }
}

/**
 * The most dimensions a `RawArray` of a `.cjo` is read with, far more than a type writes: more
 * are a broken file's.
 */
let maxRawArrayDims = 64

/**
 * One declaration of a `.cjo` as types: cjc's `SemaTy`s, each by its place among `allTypes` from 1,
 * lowered to `Ty`s.
 */
class BinaryTyLowering {
    private let decl: CjoDecl
    private let imports: Array<String>
    /**
     * The `GenericParamDecl`s of the declaration, then of its parent, by their places among
     * `allDecls` from 1, with whose they are.
     */
    private let owners: Array<(DefId, Array<UInt32>)>
    /**
     * The types being lowered, each inside the one before.
     */
    private let lowering = HashSet<UInt32>()

    BinaryTyLowering(index: Int64, parent: ?DefId, parentIndex: ?Int64, private let db: AnalysisDatabase,
        private let pkg: BinaryPackageFile, private let cjo: CjoPackage, private let def: DefId) {
        decl = cjo.allDecls[index]
        imports = cjo.imports.toArray()
        let all = ArrayList<(DefId, Array<UInt32>)>([(def, genericDeclsOf(decl))])
        if (let Some(owner) <- parent && let Some(at) <- parentIndex) {
            all.add((owner, genericDeclsOf(cjo.allDecls[at])))
        }
        owners = all.toArray()
    }

    func lower(): SignatureTypes {
        let generics = genericDeclsOf(decl).map {param => cjo.allDecls[Int64(param) - 1].identifier ?? ""}
        // those cjc adds to an `extend` of a generic type, its type's bounds, are no source's
        let written = (decl.generic?.constraints.toArray() ?? []).filter {constraint => !constraint.isImplicitlyIntroduced}
        let bounds = written.map {
            constraint => TyBound(lowerAt(constraint.`type`), constraint.uppers.toArray().map {upper => lowerAt(upper)})
        }
        let supers = match (decl.info) {
            case Some(DeclInfo.AsClassInfo(it)) => it.inheritedTypes.toArray()
            case Some(DeclInfo.AsInterfaceInfo(it)) => it.inheritedTypes.toArray()
            case Some(DeclInfo.AsStructInfo(it)) => it.inheritedTypes.toArray()
            case Some(DeclInfo.AsEnumInfo(it)) => it.inheritedTypes.toArray()
            case Some(DeclInfo.AsExtendInfo(it)) => it.inheritedTypes.toArray()
            case _ => Array<UInt32>()
        }.map {ty => lowerAt(ty)}
        let declared = match (decl.info) {
            case Some(DeclInfo.AsAliasInfo(it)) => it.aliasedTy
            case _ => decl.`type`
        }
        // a function's type is a function's: its parameters and its return type
        let (params, ty) = match (semaTyOf(declared)) {
            case Some(semaTy) where semaTy.kind == TypeKind.Func && isCallable(def.item(db).kind) =>
                let ret = match (semaTy.info) {
                    case Some(SemaTyInfo.AsFuncTyInfo(info)) => lowerAt(info.retType)
                    case _ => Ty(db, TodoTy(Todo.BinaryType))
                }
                (semaTy.typeArgs.toArray().map {arg => lowerAt(arg)}, ret)
            case _ => (Array<Ty>(), lowerAt(declared))
        }
        SignatureTypes(generics: generics, params: params, paramNames: paramNames(), ty: ty, supers: supers,
            bounds: bounds)
    }

    /**
     * Of a function's parameters, the name of each passed by name; none if none is.
     */
    private func paramNames(): Array<?String> {
        let lists = match (decl.info) {
            case Some(DeclInfo.AsFuncInfo(it)) => (it.funcBody ?? return []).paramLists.toArray()
            case _ => return []
        }
        let names = ArrayList<?String>()
        for (list in lists) {
            for (param in list.params) {
                let one = cjo.allDecls[Int64(param) - 1]
                names.add(match (one.info) {
                    case Some(DeclInfo.AsParamInfo(it)) where it.isNamedParam => one.identifier
                    case _ => None
                })
            }
        }
        if (names.iterator().any {one => one.isSome()}) {
            names.toArray()
        } else {
            []
        }
    }

    /**
     * The type at `index` among `allTypes`, from 1.
     */
    private func lowerAt(index: UInt32): Ty {
        // a type inside itself is a broken file's (D38)
        if (!lowering.add(index)) {
            return Ty(db, TodoTy(Todo.BinaryType))
        }
        try {
            lowerSemaTy(index)
        } finally {
            lowering.remove(index)
        }
    }

    private func lowerSemaTy(index: UInt32): Ty {
        let semaTy = semaTyOf(index) ?? return Ty(db, TodoTy(Todo.BinaryType))
        let args = semaTy.typeArgs.toArray().map {arg => lowerAt(arg)}
        let kind = match (semaTy.kind) {
            case TypeKind.Tuple => TupleTy(args)
            case TypeKind.Func => match (semaTy.info) {
                case Some(SemaTyInfo.AsFuncTyInfo(info)) => FuncTy(args, lowerAt(info.retType), info.isC)
                case _ => TodoTy(Todo.BinaryType)
            }
            case TypeKind.Enum | TypeKind.Struct | TypeKind.Class | TypeKind.Interface => match (semaTy.info) {
                case Some(SemaTyInfo.AsCompositeTyInfo(info)) where info.isThisTy => ThisTy
                case _ => declTyOf(binaryTypeRef(cjo, imports, index), args)
            }
            case TypeKind.CPointer | TypeKind.CString => declTyOf(binaryTypeRef(cjo, imports, index), args)
            case TypeKind.Array => return rawArrayOf(args, dimsOf(semaTy.info))
            case TypeKind.`VArray` => match (args.get(0)) {
                case Some(element) => VArrayTy(element, dimsOf(semaTy.info))
                case None => TodoTy(Todo.BinaryType)
            }
            case TypeKind.Generic => match (semaTy.info) {
                case Some(SemaTyInfo.AsGenericTyInfo(info)) => paramOf(info.declPtr)
                case _ => TodoTy(Todo.BinaryType)
            }
            // an alias, which cjc keeps in the types it writes: `Array<Byte>`
            case TypeKind.Type => return aliasOf(binaryTypeRef(cjo, imports, index), args)
            // `Unit` to `Bool`: the types of the language
            case kind where kind.value >= 1 && kind.value <= 17 => PrimTy(kind.toString())
            // an invalid one, one a newer format added
            case _ => TodoTy(Todo.BinaryType)
        }
        Ty(db, kind)
    }

    private func semaTyOf(index: UInt32): ?SemaTy {
        let types = cjo.allTypes
        if (index == 0 || Int64(index) > types.size) {
            None
        } else {
            types[Int64(index) - 1]
        }
    }

    private func declTyOf(ref: ?BinaryTypeRef, args: Array<Ty>): TyKind {
        match (ref.flatMap {one => resolveBinaryType(db, pkg, one)}) {
            case Some(DeclType(id)) => DeclTy(id, args)
            case _ => TodoTy(Todo.BinaryType)
        }
    }

    /**
     * The alias `ref` names applied to `args`, expanded as a source's is.
     */
    private func aliasOf(ref: ?BinaryTypeRef, args: Array<Ty>): Ty {
        match (ref.flatMap {one => resolveBinaryType(db, pkg, one)}) {
            case Some(DeclType(id)) where id.item(db).kind == ItemKind.TypeAlias =>
                substitute(db, signatureTypes(db, id).ty ?? Ty(db, TodoTy(Todo.BinaryType)), id, args)
            case _ => Ty(db, TodoTy(Todo.BinaryType))
        }
    }

    /**
     * `RawArray<T>` of `dims` dimensions, one inside another: `RawArray<RawArray<T>>` of 2; an
     * error for more than `maxRawArrayDims`, a broken file's (D38).
     */
    private func rawArrayOf(args: Array<Ty>, dims: Int64): Ty {
        if (dims > maxRawArrayDims) {
            return Ty(db, TodoTy(Todo.BinaryType))
        }
        let element = args.get(0) ?? return Ty(db, TodoTy(Todo.BinaryType))
        let rawArray = match (resolveBinaryType(db, pkg, BinaryTypeRef.BuiltInRef("RawArray"))) {
            case Some(DeclType(id)) => id
            case _ => return Ty(db, TodoTy(Todo.BinaryType))
        }
        var ty = element
        for (_ in 0..max(dims, 1)) {
            ty = Ty(db, DeclTy(rawArray, [ty]))
        }
        ty
    }

    /**
     * The type parameter `ptr` points to, of the declaration or of its parent.
     */
    private func paramOf(ptr: ?FullId): TyKind {
        let at = ptr ?? return TodoTy(Todo.BinaryType)
        if (at.pkgId != -2) {
            return TodoTy(Todo.BinaryType)
        }
        for ((owner, params) in owners) {
            for (i in 0..params.size where params[i] == at.index) {
                return ParamTy(owner, i)
            }
        }
        TodoTy(Todo.BinaryType)
    }
}

/**
 * Whether the item of `def` is named `name`.
 */
func isNamed(db: AnalysisDatabase, def: DefId, name: String): Bool {
    declItemOf(db, def).map {item => item.names.contains(name)} ?? false
}

/**
 * Whether a declaration of `kind` is called, its type a function's whose parameters and return
 * type are its own.
 */
func isCallable(kind: ItemKind): Bool {
    match (kind) {
        case Func | Main | Macro | Init | PrimaryInit | Finalizer | EnumCtor => true
        case _ => false
    }
}

/**
 * The `GenericParamDecl`s of `decl`, by their places among `allDecls` from 1.
 */
func genericDeclsOf(decl: CjoDecl): Array<UInt32> {
    decl.generic?.typeParameters.toArray() ?? []
}

/**
 * The dimensions of a `RawArray`, the size of a `VArray`.
 */
func dimsOf(info: ?SemaTyInfo): Int64 {
    match (info) {
        case Some(SemaTyInfo.AsArrayTyInfo(it)) => it.dimsOrSize
        case _ => 0
    }
}
