package loupe

import std.collection.{ArrayList, HashSet}
import std.deriving.Derive
import cjsyntax.CjSyntaxNode
import cjsyntax.ast.isIdent
import py_interop.*
import py_interop.internal_macros.DerivePython
import loupe.hir.{
    CallResolution,
    CallResolutionOutcome,
    DefId,
    ExprId,
    ImportError,
    InferenceDiagnostic,
    ItemFile,
    MacroCallId,
    PackageRef,
    PathResolution,
    Todo,
    TypeTarget,
    UnknownReason,
    Visibility,
    bodyWithSourceMap,
    importPathTo,
    inferBody,
    isTestOf,
    packageOfFile,
    resolveImport,
    scopeFileOf,
    signatureTypes,
    sourceDefOf,
    syntaxOf
}

/**
 * Resolution completeness, independent of whether navigation source is available.
 * MissingResolutionReason states that inference retained no more precise failure explanation.
 */
@DerivePython
public enum SemanticResolutionStatus <: Equatable<SemanticResolutionStatus> {
    | ResolvedMeaning
    | AmbiguousMeaning
    | UnresolvedMeaning
    | UnavailableMeaning

    public operator func ==(other: SemanticResolutionStatus): Bool {
        match ((this, other)) {
            case (
                    SemanticResolutionStatus.ResolvedMeaning,
                    SemanticResolutionStatus.ResolvedMeaning
                ) => true
            case (
                    SemanticResolutionStatus.AmbiguousMeaning,
                    SemanticResolutionStatus.AmbiguousMeaning
                ) => true
            case (
                    SemanticResolutionStatus.UnresolvedMeaning,
                    SemanticResolutionStatus.UnresolvedMeaning
                ) => true
            case (
                    SemanticResolutionStatus.UnavailableMeaning,
                    SemanticResolutionStatus.UnavailableMeaning
                ) => true
            case _ => false
        }
    }

    public operator func !=(other: SemanticResolutionStatus): Bool {
        !(this == other)
    }
}

/**
 * Preserved analysis gaps, or an explicit absence of a retained failure explanation.
 */
@DerivePython
public enum SemanticResolutionReason {
    | MissingResolutionReason
    | MissingResolutionData
    | UnavailableBodySource
    | MissingResolutionInput(UnknownReason)
    | UnsupportedResolution(Todo)
    | ImportResolutionFailure(ImportError)
}

/**
 * A final instantiated generic parameter, identified by its real declaration or local binder.
 */
@DerivePython
public struct SemanticGenericBinding {
    SemanticGenericBinding(
        public let parameter: SemanticObject,
        public let valueType: SemanticType
    ) {}
}

/**
 * An inference diagnostic and its owner-qualified anchor in the originating snapshot.
 */
@DerivePython
public struct SemanticResolutionDiagnostic {
    SemanticResolutionDiagnostic(
        public let anchor: SemanticObject,
        public let diagnostic: InferenceDiagnostic
    ) {}
}

/**
 * Retained call evidence. A resolved function value has no declaration target; local named
 * functions keep their body-qualified local identity. Initializers and named types stay separate.
 */
@DerivePython
public class SemanticCallResolution {
    @PyIgnore
    let analysis: SemanticAnalysis
    @PyIgnore
    let owner: DefId
    @PyIgnore
    let raw: CallResolution
    public let isSetter: Bool

    @PyIgnore
    init(analysis: SemanticAnalysis, owner: DefId, raw: CallResolution, isSetter!: Bool = false) {
        this.analysis = analysis
        this.owner = owner
        this.raw = raw
        this.isSetter = isSetter
    }

    public prop callee: SemanticObject {
        get() {
            analysis.db.unwindIfCancelled()
            analysis.object(ExpressionIdentity(owner, raw.expr))
        }
    }

    public prop status: SemanticResolutionStatus {
        get() {
            analysis.db.unwindIfCancelled()
            if (
                raw.outcome != CallResolutionOutcome.Resolved &&
                    let Some(ty) <- inferBody(analysis.db, owner)[raw.expr]
            ) {
                match (ty.kind(analysis.db)) {
                    case UnknownTy(_) | TodoTy(_) =>
                        return SemanticResolutionStatus.UnavailableMeaning
                    case _ => ()
                }
            }
            match (raw.outcome) {
                case Resolved => ResolvedMeaning
                case Ambiguous => AmbiguousMeaning
                case Unresolved => UnresolvedMeaning
            }
        }
    }

    public func callable(): ?SemanticObject {
        analysis.db.unwindIfCancelled()
        if (let Some(local) <- raw.local) {
            return analysis.object(LocalIdentity(owner, local))
        }
        raw.decl.map { def => analysis.object(NamedIdentity(Definition.DeclDef(def))) }
    }

    public func initializer(): ?SemanticObject {
        analysis.db.unwindIfCancelled()
        inferBody(analysis.db, owner)
            .initializerOf(raw.expr)
            .map { def => analysis.object(NamedIdentity(Definition.DeclDef(def))) }
    }

    public func signature(): ?SemanticType {
        analysis.db.unwindIfCancelled()
        raw.signature.map { ty => SemanticType(analysis, ty) }
    }

    /**
     * Parameter indices in written argument order, including variadic and trailing-lambda arguments.
     */
    public func argumentParameters(): ?Array<Int64> {
        analysis.db.unwindIfCancelled()
        Some(raw.params)
    }

    public func bindings(): Array<SemanticGenericBinding> {
        analysis.db.unwindIfCancelled()
        raw
            .bindings
            .map {
                binding =>
                let target =
                    match (binding.owner) {
                        case Declaration(def) => TypeTarget.GenericOf(def, binding.index)
                        case LocalFunction(def, local) =>
                            TypeTarget.LocalGenericOf(def, local, binding.index)
                    }
                SemanticGenericBinding(
                    analysis.object(NamedIdentity(Definition.TypeParamDef(target))),
                    SemanticType(analysis, binding.ty)
                )
            }
    }
}

/**
 * One source occurrence's retained name, member, import or type-segment meaning and call evidence.
 * Status describes identity selection; a resolved declaration may still have an incomplete type.
 * Path identities and diagnostic payloads belong to occurrence's snapshot, like SemanticIdentity.
 */
@DerivePython
public class SemanticResolution {
    SemanticResolution(
        public let occurrence: SemanticOccurrence,
        public let status: SemanticResolutionStatus,
        public let reason: ?SemanticResolutionReason,
        public let call: ?SemanticCallResolution,
        public let setterCall: ?SemanticCallResolution,
        public let diagnostics: Array<SemanticResolutionDiagnostic>,
        public let path: ?PathResolution
    ) {}
}

/**
 * A declaration's retained body results and whether its source was available to analysis.
 * Empty records alone never establish that an unavailable binary body has no references or calls.
 */
@DerivePython
public class SemanticBodyResolutions {
    SemanticBodyResolutions(
        public let owner: SemanticObject,
        public let status: SemanticResolutionStatus,
        public let reason: ?SemanticResolutionReason,
        public let occurrences: Array<SemanticResolution>,
        public let calls: Array<SemanticCallResolution>
    ) {}
}

@DerivePython
extend SemanticOccurrence {
    /**
     * Uses the same classification and selected identities as navigation, with explicit non-success.
     * No rejection trace is synthesized when inference did not retain one.
     */
    public func resolution(): SemanticResolution {
        analysis.db.unwindIfCancelled()
        var call: ?SemanticCallResolution = None
        var setterCall: ?SemanticCallResolution = None
        let diagnostics = ArrayList<SemanticResolutionDiagnostic>()
        var status =
            match (definitions) {
                case Some(targets) where targets.size == 1 =>
                    SemanticResolutionStatus.ResolvedMeaning
                case Some(targets) where targets.size > 1 =>
                    SemanticResolutionStatus.AmbiguousMeaning
                case Some(_) => SemanticResolutionStatus.UnresolvedMeaning
                case None => SemanticResolutionStatus.UnavailableMeaning
            }
        var reason: ?SemanticResolutionReason =
            match (status) {
                case ResolvedMeaning | AmbiguousMeaning => None
                case UnresolvedMeaning => SemanticResolutionReason.MissingResolutionReason
                case UnavailableMeaning => SemanticResolutionReason.MissingResolutionData
            }
        for (object in objects) {
            if (let ExpressionIdentity(owner, expr) <- object.identity) {
                let inferred = inferBody(analysis.db, owner)
                setterCall =
                    inferred
                        .setterCallOf(expr)
                        .map { raw => SemanticCallResolution(analysis, owner, raw, isSetter: true) }
                if (let Some(raw) <- inferred.callOf(expr)) {
                    let selected = SemanticCallResolution(analysis, owner, raw)
                    call = selected
                    status = selected.status
                    reason =
                        if (status == SemanticResolutionStatus.UnresolvedMeaning) {
                            Some(SemanticResolutionReason.MissingResolutionReason)
                        } else {
                            None
                        }
                }
                for (diagnostic in inferred.diagnostics) {
                    let anchor = diagnosticExpression(diagnostic)
                    if (isCallDiagnostic(analysis, owner, expr, anchor)) {
                        diagnostics.add(
                            SemanticResolutionDiagnostic(
                                analysis.object(ExpressionIdentity(owner, anchor)),
                                diagnostic
                            )
                        )
                    }
                }
            }
        }
        let path = retainedPath()
        if (let Some(error) <- importFailure()) {
            reason = SemanticResolutionReason.ImportResolutionFailure(error)
        }
        if (status != SemanticResolutionStatus.ResolvedMeaning) {
            for (object in objects) {
                if (let Some(ty) <- object.semanticType()) {
                    match (ty.kind()) {
                        case UnavailableType(why) =>
                            status = SemanticResolutionStatus.UnavailableMeaning
                            reason = SemanticResolutionReason.MissingResolutionInput(why)
                        case UnsupportedType(why) =>
                            status = SemanticResolutionStatus.UnavailableMeaning
                            reason = SemanticResolutionReason.UnsupportedResolution(why)
                        case _ => ()
                    }
                }
            }
        }
        SemanticResolution(this, status, reason, call, setterCall, diagnostics.toArray(), path)
    }

    private func retainedPath(): ?PathResolution {
        let (root, _) = syntaxOf(analysis.db, location.file) ?? return None
        let token = tokenAt(root, location.focusRange.start, includeInit: true) ?? return None
        let (_, segment) = typeAt(token) ?? return None
        for (object in objects) {
            match (object.identity) {
                case SignatureTypeIdentity(owner, id) =>
                    return signatureTypes(analysis.db, owner)
                        .pathOf(id)
                        .flatMap { segments => segments.get(segment) }
                case BodyTypeIdentity(owner, id) =>
                    return inferBody(analysis.db, owner)
                        .typePathOf(id)
                        .flatMap { segments => segments.get(segment) }
                case _ => ()
            }
        }
        None
    }

    private func importFailure(): ?ImportError {
        let (root, _) = syntaxOf(analysis.db, location.file) ?? return None
        let token = tokenAt(root, location.focusRange.start, includeInit: true) ?? return None
        let (path, isLeaf) = importPathTo(token.parent) ?? return None
        if (!isLeaf) {
            return None
        }
        let file = scopeFileOf(analysis.db, location.file) ?? return None
        let pkg = packageOfFile(analysis.db, file) ?? return None
        match (
            resolveImport(
                analysis.db,
                PackageRef.Source(pkg),
                path,
                Visibility.Private,
                ofTests: isTestOf(analysis.db, pkg, file)
            )
        ) {
            case Unresolved(error) => error
            case _ => None
        }
    }
}

@DerivePython
extend SemanticObject {
    /**
     * Body records with explicit source availability. Checked binary attachments use their
     * source body while declaration, generic and callable targets retain canonical identities.
     */
    public func bodyResolutions(): SemanticBodyResolutions {
        analysis.db.unwindIfCancelled()
        let source = bodyOwner()
        let available =
            source
                .map {
                    owner =>
                    if (itemNodeOf(analysis.db, owner).isNone()) {
                        return false
                    }
                    let body = bodyWithSourceMap(analysis.db, owner).body
                    body.value.isSome() || !body.accessors.isEmpty()
                } ??
                false
        SemanticBodyResolutions(
            this,
            if (available) {
                SemanticResolutionStatus.ResolvedMeaning
            } else {
                SemanticResolutionStatus.UnavailableMeaning
            },
            if (available) { None } else { Some(SemanticResolutionReason.UnavailableBodySource) },
            resolutions(),
            calls()
        )
    }

    private func bodyOwner(): ?DefId {
        match (identity) {
            case NamedIdentity(DeclDef(def)) => sourceDefOf(analysis.db, def) ?? def
            case _ => None
        }
    }

    /**
     * Retained calls, including synthetic operators and function values. Use bodyResolutions()
     * to distinguish unavailable bodies from bodies with no calls.
     */
    public func calls(): Array<SemanticCallResolution> {
        analysis.db.unwindIfCancelled()
        let owner = bodyOwner() ?? return []
        let inferred = inferBody(analysis.db, owner)
        inferred
            .calls
            .map { raw => SemanticCallResolution(analysis, owner, raw) }
            .concat(
                inferred
                    .setterCalls
                    .map { raw => SemanticCallResolution(analysis, owner, raw, isSetter: true) }
            )
    }

    /**
     * Written name and operator occurrences belonging to this declaration, in source order per
     * source context. Signature segments and body expansions are included; source-less bodies
     * have no written occurrences.
     */
    public func resolutions(): Array<SemanticResolution> {
        analysis.db.unwindIfCancelled()
        let owner = bodyOwner() ?? return []
        let node = itemNodeOf(analysis.db, owner) ?? return []
        let contexts = ArrayList<(ItemFile, CjSyntaxNode)>([(owner.file(analysis.db), node)])
        let seen = HashSet<MacroCallId>()
        let map = bodyWithSourceMap(analysis.db, owner).sourceMap
        for (origin in map.exprs.concat(map.pats).concat(map.locals).concat(map.types)) {
            if (
                let Some(call) <- origin.written.flatMap { source => source.expansion } &&
                    seen.add(call)
            ) {
                let file = ItemFile.Expansion(call)
                if (let Some((root, _)) <- syntaxOf(analysis.db, file)) {
                    contexts.add((file, root))
                }
            }
        }
        let found = ArrayList<SemanticResolution>()
        for ((file, root) in contexts) {
            for (element in root.descendantsWithTokens()) {
                if (let Some(token) <- element.asToken() && (isIdent(token) || isOperator(token))) {
                    let occurrence = analysis.inFile(file, token.textRange.start) ?? continue
                    if (
                        occurrence
                            .owner
                            .map {
                                object =>
                                object.identity ==
                                    SemanticIdentity.NamedIdentity(Definition.DeclDef(owner))
                            } ??
                            false
                    ) {
                        found.add(occurrence.resolution())
                    }
                }
            }
        }
        found.toArray()
    }
}

/**
 * The HIR anchor already retained with an inference diagnostic.
 */
private func diagnosticExpression(diagnostic: InferenceDiagnostic): ExprId {
    match (diagnostic) {
        case TypeMismatch(expr, _, _) => expr
        case VArraySizeMismatch(expr, _, _) => expr
        case ArgCount(expr, _, _) => expr
        case ArgName(expr, _, _) => expr
        case InvalidBinaryOperator(expr, _, _) => expr
        case CustomAnnotationPlace(expr) => expr
    }
}

/**
 * Keeps diagnostics at the retained application or its arguments connected to the callee.
 */
private func isCallDiagnostic(
    analysis: SemanticAnalysis,
    owner: DefId,
    callee: ExprId,
    anchor: ExprId
): Bool {
    if (anchor == callee) {
        return true
    }
    let body = bodyWithSourceMap(analysis.db, owner).body
    for (i in 0..body.exprs.size) {
        match (body.exprs[i]) {
            case CallExpr(target, args) where target == callee =>
                if (anchor == ExprId(i) || args.any { arg => arg.expr == anchor }) {
                    return true
                }
            case _ => ()
        }
    }
    false
}
