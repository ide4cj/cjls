package loupe

import std.collection.{ArrayList, enumerate, filter, first, map}
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{AnyHasName, TypeParam, TypeParamList}
import ginkgo.{SyntaxNodePtr, TextRange}
import py_interop.*
import py_interop.internal_macros.DerivePython
import rope.{Encoding, LineColumn, Rope}
import loupe.db.AnalysisDatabase
import loupe.hir.{
    BodyOrigin,
    BodySource,
    DefId,
    ExprId,
    ItemFile,
    LocalFunc,
    LocalId,
    MacroCallId,
    PatId,
    Ty,
    TypeRefId,
    TypeTarget,
    bodyWithSourceMap,
    canonicalDef,
    declaredTyOf,
    expandedDeclOf,
    inferBody,
    packageOfFile,
    scopeFileOf,
    signatureWithSourceMap,
    sourceDefOf,
    sourceRangeOf,
    syntaxOf,
    writtenTypeOf
}
import loupe.vfs.FileId

/**
 * An identity within one database revision. Body indices carry their declaration owner;
 * signature and body types occupy different arenas. Do not reuse after edits/reloads or
 * in another database. Keep SemanticObject when composing queries: it retains the snapshot.
 * Local definitions are normalized to LocalIdentity, including when reached through resolution.
 * Explicit initializers retain their own declaration identity independently of navigation.
 */
@DerivePython
@PyDoc["An identity within one database revision. Body indices carry their declaration owner; signature and body types occupy different arenas. Do not reuse after edits/reloads or in another database. Keep SemanticObject when composing queries: it retains the snapshot. Local definitions are normalized to LocalIdentity, including when reached through resolution. Explicit initializers retain their own declaration identity independently of navigation."]
public enum SemanticIdentity <: Equatable<SemanticIdentity> {
    | NamedIdentity(Definition)
    | ExpressionIdentity(DefId, ExprId)
    | PatternIdentity(DefId, PatId)
    | LocalIdentity(DefId, LocalId)
    | SignatureTypeIdentity(DefId, TypeRefId)
    | BodyTypeIdentity(DefId, TypeRefId)

    public operator func ==(other: SemanticIdentity): Bool {
        match ((this, other)) {
            case (SemanticIdentity.NamedIdentity(left0), SemanticIdentity.NamedIdentity(right0)) =>
                left0 == right0
            case (
                    SemanticIdentity.ExpressionIdentity(left0, left1),
                    SemanticIdentity.ExpressionIdentity(right0, right1)
                ) => left0 == right0 && left1 == right1
            case (
                    SemanticIdentity.PatternIdentity(left0, left1),
                    SemanticIdentity.PatternIdentity(right0, right1)
                ) => left0 == right0 && left1 == right1
            case (
                    SemanticIdentity.LocalIdentity(left0, left1),
                    SemanticIdentity.LocalIdentity(right0, right1)
                ) => left0 == right0 && left1 == right1
            case (
                    SemanticIdentity.SignatureTypeIdentity(left0, left1),
                    SemanticIdentity.SignatureTypeIdentity(right0, right1)
                ) => left0 == right0 && left1 == right1
            case (
                    SemanticIdentity.BodyTypeIdentity(left0, left1),
                    SemanticIdentity.BodyTypeIdentity(right0, right1)
                ) => left0 == right0 && left1 == right1
            case _ => false
        }
    }

    public operator func !=(other: SemanticIdentity): Bool {
        !(this == other)
    }
}

/**
 * Source text may be physical workspace/dependency text, a checked attachment, or macro output.
 */
@DerivePython
@PyDoc["Source text may be physical workspace/dependency text, a checked attachment, or macro output."]
public enum SemanticSourceKind <: Equatable<SemanticSourceKind> {
    | PhysicalSource
    | AttachedSource
    | ExpansionSource

    public operator func ==(other: SemanticSourceKind): Bool {
        match ((this, other)) {
            case (SemanticSourceKind.PhysicalSource, SemanticSourceKind.PhysicalSource) => true
            case (SemanticSourceKind.AttachedSource, SemanticSourceKind.AttachedSource) => true
            case (SemanticSourceKind.ExpansionSource, SemanticSourceKind.ExpansionSource) => true
            case _ => false
        }
    }

    public operator func !=(other: SemanticSourceKind): Bool {
        !(this == other)
    }
}

/**
 * Exact syntax, synthetic HIR and unavailable source are distinct, including for binaries.
 */
@DerivePython
@PyDoc["Exact syntax, synthetic HIR and unavailable source are distinct, including for binaries."]
public enum SemanticOrigin {
    | SourceOrigin(SemanticLocation)
    | SyntheticOrigin
    | UnavailableOrigin
}

/**
 * Analysis pinned to db's current revision, used from one thread at a time. All object,
 * location, type and text operations use this snapshot and throw CancelledException after
 * an input write or request cancellation. No operation reopens disk. Copied text, coordinates
 * and identities describe only the originating revision.
 */
@DerivePython
@PyDoc["Analysis pinned to db's current revision, used from one thread at a time. All object, location, type and text operations use this snapshot and throw CancelledException after an input write or request cancellation. No operation reopens disk. Copied text, coordinates and identities describe only the originating revision."]
public class SemanticAnalysis {
    @PyIgnore
    let db: AnalysisDatabase

    @PyIgnore
    public init(db: AnalysisDatabase) {
        this.db = db.snapshot()
    }

    /**
     * UTF-8 byte offset in the editor's preferred context; none for an unavailable file.
     */
    @PyDoc["UTF-8 byte offset in the editor's preferred context; none for an unavailable file."]
    public func at(fileId: FileId, offset: Int64): ?SemanticOccurrence {
        db.unwindIfCancelled()
        let file = db.sourceFile(fileId) ?? return None
        inFile(ItemFile.Source(file), offset)
    }

    /**
     * Preserves explicit source context/expansion. At a boundary prefers right name, left name,
     * right operator, left operator; otherwise the right token (last token at EOF). Selects the
     * nearest mapped ancestor of each HIR category, before desugaring. Out-of-range offsets
     * return none. File identities must belong to this database and revision. Source macro arguments
     * do not descend into expansions (#370).
     */
    @PyDoc["Preserves explicit source context/expansion. At a boundary prefers right name, left name, right operator, left operator; otherwise the right token (last token at EOF). Selects the nearest mapped ancestor of each HIR category, before desugaring. Out-of-range offsets return none. File identities must belong to this database and revision. Source macro arguments do not descend into expansions (#370)."]
    public func inFile(file: ItemFile, offset: Int64): ?SemanticOccurrence {
        db.unwindIfCancelled()
        let (root, _) = syntaxOf(db, file) ?? return None
        if (offset < 0 || offset > root.textRange.end) {
            return None
        }
        let token =
            tokenAt(root, offset, includeInit: true) ?? anyTokenAt(root, offset) ?? return None
        let item = itemAround(db, file, token.parent)
        let expansion =
            match (file) {
                case Expansion(call) => Some(call)
                case _ => None<MacroCallId>
            }
        let owner: ?DefId =
            item ?? expansion.flatMap { call => bodyOfExpressionExpansion(db, call) }
        let origin = if (item.isNone()) { expansion } else { None<MacroCallId> }
        let definitions = semanticDefinitions(db, file, token, owner, expansion: origin)
        SemanticOccurrence(
            this,
            location(file, token.textRange, token.textRange),
            owner.map { id => object(NamedIdentity(Definition.DeclDef(id))) },
            definitions.map { defs => defs.map { def => object(NamedIdentity(def)) } },
            objectsAt(owner, token, expansion: origin)
        )
    }

    private func objectsAt(
        owner: ?DefId,
        token: CjSyntaxToken,
        expansion!: ?MacroCallId
    ): Array<SemanticObject> {
        let objects = ArrayList<SemanticObject>()
        let def = owner ?? return []
        let bodyMap = bodyWithSourceMap(db, def).sourceMap
        let signatureMap = signatureWithSourceMap(db, def).sourceMap
        let declaration = itemNodeOf(db, def)
        var hasExpr = false
        var hasPat = false
        var hasLocal = false
        var hasType = false
        for (node in token.parent.ancestors()) {
            let ptr = SyntaxNodePtr(node)
            let source = BodySource(ptr, expansion: expansion)
            if (!hasLocal && let Some(id) <- bodyMap.localAtSource(source)) {
                objects.add(object(LocalIdentity(def, id)))
                hasLocal = true
            }
            if (!hasExpr && let Some(id) <- bodyMap.exprAtSource(source)) {
                objects.add(object(ExpressionIdentity(def, id)))
                hasExpr = true
            }
            if (!hasPat && let Some(id) <- bodyMap.patAtSource(source)) {
                objects.add(object(PatternIdentity(def, id)))
                hasPat = true
            }
            if (!hasType) {
                if (expansion.isNone() && let Some(id) <- signatureMap.typeAt(ptr)) {
                    objects.add(object(SignatureTypeIdentity(def, id)))
                    hasType = true
                } else if (let Some(id) <- bodyMap.typeAtSource(source)) {
                    objects.add(object(BodyTypeIdentity(def, id)))
                    hasType = true
                }
            }
            if (declaration.map { it => it == node } ?? false) {
                break
            }
        }
        objects.toArray()
    }

    @PyIgnore
    func object(identity: SemanticIdentity): SemanticObject {
        let canonical =
            match (identity) {
                case NamedIdentity(LocalDef(owner, id)) => LocalIdentity(owner, id)
                case _ => identity
            }
        SemanticObject(this, canonical)
    }

    @PyIgnore
    func location(file: ItemFile, full: TextRange, focus: TextRange): SemanticLocation {
        SemanticLocation(this, file, full, focus)
    }

    @PyIgnore
    func text(file: ItemFile): ?Rope {
        db.unwindIfCancelled()
        match (file) {
            case Source(source) => source.text(db)
            case Expansion(call) => expandedMacro(db, call).map { output => Rope(output.text) }
            case _ => None
        }
    }
}

/**
 * Occurrence and targets are distinct. Definitions preserves zero/one/many meanings: none is
 * unavailable/inapplicable classification, an empty array a known empty result. Objects contains
 * the nearest mapped node of each HIR category. Written type references retain their own identity.
 */
@DerivePython
@PyDoc["Occurrence and targets are distinct. Definitions preserves zero/one/many meanings: none is unavailable/inapplicable classification, an empty array a known empty result. Objects contains the nearest mapped node of each HIR category. Written type references retain their own identity."]
public class SemanticOccurrence {
    @PyIgnore
    let analysis: SemanticAnalysis
    public let location: SemanticLocation
    public let owner: ?SemanticObject
    public let definitions: ?Array<SemanticObject>
    public let objects: Array<SemanticObject>

    @PyIgnore
    init(
        analysis: SemanticAnalysis,
        location: SemanticLocation,
        owner: ?SemanticObject,
        definitions: ?Array<SemanticObject>,
        objects: Array<SemanticObject>
    ) {
        this.analysis = analysis
        this.location = location
        this.owner = owner
        this.definitions = definitions
        this.objects = objects
    }
}

/**
 * A semantic object bound to its originating snapshot, independently of navigation targets.
 */
@DerivePython
@PyDoc["A semantic object bound to its originating snapshot, independently of navigation targets."]
public class SemanticObject {
    @PyIgnore
    let analysis: SemanticAnalysis
    public let identity: SemanticIdentity

    @PyIgnore
    init(analysis: SemanticAnalysis, identity: SemanticIdentity) {
        this.analysis = analysis
        this.identity = identity
    }

    /**
     * Exact syntax origins. A package can have several headers; binary source must pass the
     * existing identity check. Generated syntax stays in its expansion, never an approximate head.
     */
    @PyDoc["Exact syntax origins. A package can have several headers; binary source must pass the existing identity check. Generated syntax stays in its expansion, never an approximate head."]
    public func origins(): Array<SemanticOrigin> {
        let db = analysis.db
        db.unwindIfCancelled()
        match (identity) {
            case NamedIdentity(definition) => namedOrigins(definition)
            case SignatureTypeIdentity(owner, id) =>
                let ptr =
                    signatureWithSourceMap(db, owner)
                        .sourceMap
                        .ptrs
                        .get(id.index)
                        .flatMap { it => it } ??
                        return [UnavailableOrigin]
                [SourceOrigin(analysis.location(owner.file(db), ptr.range, ptr.range))]
            case _ => bodyOrigins()
        }
    }

    private func namedOrigins(definition: Definition): Array<SemanticOrigin> {
        let db = analysis.db
        match (definition) {
            case LocalDef(owner, id) => return analysis.object(LocalIdentity(owner, id)).origins()
            case MemberParamDef(owner, id) =>
                return analysis.object(LocalIdentity(owner, id)).origins()
            case TypeParamDef(target) =>
                match (target) {
                    case GenericOf(_, _) | LocalGenericOf(_, _, _) => return genericOrigins(target)
                    case _ => ()
                }
            case DeclDef(id) =>
                if (let Some(node) <- itemNodeOf(db, id)) {
                    return [
                        SourceOrigin(
                            analysis.location(id.file(db), node.textRange, declarationFocus(node))
                        )
                    ]
                }
            case _ => ()
        }
        let locations =
            targetsOfDefinition(db, definition, intoExpansions: true)
                .filterMap {
                    target =>
                    let file =
                        target.expansion.map { call => ItemFile.Expansion(call) } ??
                            db
                                .sourceFile(target.fileId)
                                .map { source => ItemFile.Source(source) } ??
                                return None<SemanticOrigin>
                    Some(
                        SemanticOrigin.SourceOrigin(
                            analysis.location(file, target.fullRange, target.focusRange)
                        )
                    )
                }
        if (locations.isEmpty()) { [UnavailableOrigin] } else { locations }
    }

    private func genericOrigins(target: TypeTarget): Array<SemanticOrigin> {
        let db = analysis.db
        match (target) {
            case GenericOf(owner, index) =>
                let source = sourceDefOf(db, owner) ?? owner
                let node = itemNodeOf(db, source) ?? return [UnavailableOrigin]
                let (full, focus) = genericRanges(node, index) ?? return [UnavailableOrigin]
                [SourceOrigin(analysis.location(source.file(db), full, focus))]
            case LocalGenericOf(owner, localFunc, index) =>
                let lowered = bodyWithSourceMap(db, owner)
                let local = lowered.body.funcs.get(localFunc)?.local ?? return [UnavailableOrigin]
                let source =
                    lowered
                        .sourceMap
                        .locals
                        .get(local.index)
                        .flatMap { origin => origin.written } ??
                        return [UnavailableOrigin]
                let name = source.node(db, owner.file(db)) ?? return [UnavailableOrigin]
                let (full, focus) =
                    genericRanges(name.parent ?? return [UnavailableOrigin], index) ??
                        return [UnavailableOrigin]
                [SourceOrigin(analysis.location(source.inFile(owner.file(db)), full, focus))]
            case _ => [UnavailableOrigin]
        }
    }

    private func bodyOrigins(): Array<SemanticOrigin> {
        let db = analysis.db
        let (owner, origin) =
            match (identity) {
                case ExpressionIdentity(owner, id) =>
                    (owner, bodyWithSourceMap(db, owner).sourceMap.exprs.get(id.index))
                case PatternIdentity(owner, id) =>
                    (owner, bodyWithSourceMap(db, owner).sourceMap.pats.get(id.index))
                case LocalIdentity(owner, id) =>
                    (owner, bodyWithSourceMap(db, owner).sourceMap.locals.get(id.index))
                case BodyTypeIdentity(owner, id) =>
                    (owner, bodyWithSourceMap(db, owner).sourceMap.types.get(id.index))
                case _ => return [UnavailableOrigin]
            }
        match (origin) {
            case Some(WrittenSource(source)) =>
                [
                    SourceOrigin(
                        analysis.location(
                            source.inFile(owner.file(db)),
                            source.ptr.range,
                            source.ptr.range
                        )
                    )
                ]
            case Some(SyntheticSource) => [SyntheticOrigin]
            case None => [UnavailableOrigin]
        }
    }

    /**
     * Inferred/resolved type bound to this object's snapshot, retaining structured unknown/error
     * reasons; none when inapplicable. Child types and definitions use the same context.
     */
    @PyDoc["Inferred/resolved type bound to this object's snapshot, retaining structured unknown/error reasons; none when inapplicable. Child types and definitions use the same context."]
    public func semanticType(): ?SemanticType {
        resolvedType().map { ty => SemanticType(analysis, ty) }
    }

    private func resolvedType(): ?Ty {
        let db = analysis.db
        db.unwindIfCancelled()
        match (identity) {
            case ExpressionIdentity(owner, id) => inferBody(db, owner)[id]
            case PatternIdentity(owner, id) => inferBody(db, owner)[id]
            case LocalIdentity(owner, id) => inferBody(db, owner)[id]
            case SignatureTypeIdentity(owner, id) => writtenTypeOf(db, owner, id)
            case BodyTypeIdentity(owner, id) => writtenTypeOf(db, owner, id, inBody: true)
            case NamedIdentity(DeclDef(id)) => declaredTyOf(db, id)
            case NamedIdentity(LocalDef(owner, id)) => inferBody(db, owner)[id]
            case NamedIdentity(MemberParamDef(owner, id)) => inferBody(db, owner)[id]
            case _ => None
        }
    }

    /**
     * Type display from this object's revision; none when it has no type.
     */
    @PyDoc["Type display from this object's revision; none when it has no type."]
    public func typeDisplay(): ?String {
        semanticType().map { ty => ty.display() }
    }
}

/**
 * Contextual source/expansion location bound to the snapshot. Ranges are end-exclusive UTF-8
 * bytes. Expansion text and attached source retain their distinct ItemFile identity.
 */
@DerivePython
@PyDoc["Contextual source/expansion location bound to the snapshot. Ranges are end-exclusive UTF-8 bytes. Expansion text and attached source retain their distinct ItemFile identity."]
public class SemanticLocation {
    @PyIgnore
    let analysis: SemanticAnalysis
    public let file: ItemFile
    public let fullRange: TextRange
    public let focusRange: TextRange

    @PyIgnore
    init(analysis: SemanticAnalysis, file: ItemFile, fullRange: TextRange, focusRange: TextRange) {
        this.analysis = analysis
        this.file = file
        this.fullRange = fullRange
        this.focusRange = focusRange
    }

    /**
     * Distinguishes attached source from physical source and generated expansion text.
     */
    @PyDoc["Distinguishes attached source from physical source and generated expansion text."]
    public func kind(): SemanticSourceKind {
        let db = analysis.db
        db.unwindIfCancelled()
        match (file) {
            case Expansion(_) => ExpansionSource
            case Source(source) =>
                if (packageOfFile(db, source).flatMap { pkg => pkg.binary(db) }.isSome()) {
                    AttachedSource
                } else {
                    PhysicalSource
                }
            case _ =>
                throw IllegalStateException("a source location requires source or expansion text")
        }
    }

    /**
     * Immutable file/expansion text copied from this revision.
     * @throws CancelledException - if inputs changed or analysis was cancelled.
     */
    @PyDoc["Immutable file/expansion text copied from this revision. @throws CancelledException - if inputs changed or analysis was cancelled."]
    public func sourceText(): ?String {
        text()?.toString()
    }

    /**
     * Zero-based line and UTF-8 byte column of the focus start.
     * @throws CancelledException - if inputs changed or analysis was cancelled.
     */
    @PyDoc["Zero-based line and UTF-8 byte column of the focus start. @throws CancelledException - if inputs changed or analysis was cancelled."]
    public func coordinates(): ?(Int64, Int64) {
        position().map { value => (value.line, value.column) }
    }

    /**
     * Immutable file/expansion text for this revision.
     * @throws CancelledException - if inputs changed or analysis was cancelled.
     */
    @PyIgnore
    public func text(): ?Rope {
        analysis.text(file)
    }

    /**
     * Exact focus text (or full syntax with full: true), read from the same snapshot.
     */
    @PyDoc["Exact focus text (or full syntax with full: true), read from the same snapshot."]
    public func excerpt(full!: Bool = false): ?String {
        let text = this.text() ?? return None
        let range = if (full) { fullRange } else { focusRange }
        text.slice(range.start..range.end).toString()
    }

    /**
     * Zero-based line/UTF-8 byte column at the focus start. Adapters convert using text().
     */
    @PyIgnore
    public func position(): ?LineColumn {
        text().map { source => source.positionOf(focusRange.start, Encoding.Utf8) }
    }

    /**
     * Compact zero-based line:UTF-8-byte-column.
     */
    @PyDoc["Compact zero-based line:UTF-8-byte-column."]
    public func compact(): ?String {
        position().map { at => at.toString() }
    }

    /**
     * Physical/attached source or an exact copied expansion span; none for generated text.
     */
    @PyDoc["Physical/attached source or an exact copied expansion span; none for generated text."]
    public func source(): ?SemanticLocation {
        let db = analysis.db
        db.unwindIfCancelled()
        match (file) {
            case Source(_) => this
            case Expansion(call) =>
                let range = sourceRangeOf(db, call, focusRange) ?? return None
                analysis.location(ItemFile.Source(call.file(db)), range, range)
            case _ => None
        }
    }
}

/**
 * Falls back to a non-name token, preferring the right token at a boundary.
 */
func anyTokenAt(root: CjSyntaxNode, offset: Int64): ?CjSyntaxToken {
    match (root.tokenAtOffset(offset)) {
        case Single(token) => token
        case Between(_, right) => right
        case _ => None
    }
}

/**
 * Shared identity classification; constructor navigation and highlighting policies stay outside it.
 */
func semanticDefinitions(
    db: AnalysisDatabase,
    file: ItemFile,
    token: CjSyntaxToken,
    owner: ?DefId,
    expansion!: ?MacroCallId
): ?Array<Definition> {
    if (
        let Some(def) <- owner &&
            (
                isDeclaredName(db, def, token) ||
                    (token.kind == SyntaxKind.InitKw && token.parent.kind == SyntaxKind.InitDecl)
            )
    ) {
        return [Definition.DeclDef(canonicalDef(db, expandedDeclOf(db, def) ?? def))]
    }
    if (let Some(param) <- TypeParam.cast(token.parent.parent ?? token.parent)) {
        if (let Some(target) <- typeParamTargetIn(db, file, param, owner, expansion: expansion)) {
            return [Definition.TypeParamDef(target)]
        }
    }
    let scope = scopeFileOf(db, file) ?? return None
    classifyName(db, scope, owner, token, expansion: expansion)
}

/**
 * The type parameter `param` of `file` declares, as its uses name it: of the item it is of, or of a function a body
 * declares (N68).
 */
func typeParamTargetIn(
    db: AnalysisDatabase,
    file: ItemFile,
    param: TypeParam,
    owner: ?DefId,
    expansion!: ?MacroCallId
): ?TypeTarget {
    let (_, ids) = syntaxOf(db, file) ?? return None
    let list = param.syntax.parent.flatMap { node => TypeParamList.cast(node) } ?? return None
    let decl = list.syntax.parent ?? return None
    let index =
        (
            list.typeParams() |> enumerate |>
                filter { pair: (Int64, TypeParam) => pair[1] == param } |>
                map { pair: (Int64, TypeParam) => pair[0] } |>
                first
        ) ??
            return None
    if (let Some(item) <- ids.idOf(SyntaxNodePtr(decl))) {
        return TypeTarget.GenericOf(canonicalDef(db, DefId(db, file, item)), index)
    }
    let name = AnyHasName.cast(decl).flatMap { it => it.name() } ?? return None
    // A statement expansion has no item of its own; its locals belong to the containing body.
    let def = owner ?? return None
    let lowered = bodyWithSourceMap(db, def)
    let ptr = SyntaxNodePtr(name.syntax)
    let localFunc =
        (
            lowered.body.funcs |> enumerate |>
                filter {
                    pair: (Int64, LocalFunc) =>
                    lowered.sourceMap.locals.get(pair[1].local.index) ==
                        Some(WrittenSource(BodySource(ptr, expansion: expansion)))
                } |>
                map { pair: (Int64, LocalFunc) => pair[0] } |>
                first
        ) ??
            return None
    TypeTarget.LocalGenericOf(def, localFunc, index)
}
