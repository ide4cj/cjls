package cjmcp

import std.collection.ArrayList
import std.fs.Path
import cjformat.{FormatOptions, TextEdit}
import ginkgo.TextRange
import loupe.{
    BuiltinDoc,
    CallDeclaration,
    CallHierarchyEntry,
    CompletionItem,
    CompletionResult,
    DirectCalls,
    ExpandedFile,
    ExpandedMacro,
    FileSymbol,
    Fold,
    FoundSymbol,
    HierarchyCalls,
    HighlightedRange,
    HoverItem,
    HoverResult,
    MacroCallAt,
    NavigationTarget,
    Reference as AnalysisReference,
    RelatedHighlight,
    SemanticAnalysis,
    builtinAnnotationDoc as nativeBuiltinAnnotationDoc,
    builtinMacroDoc as nativeBuiltinMacroDoc,
    builtinTypeDoc as nativeBuiltinTypeDoc,
    callDeclaration as nativeCallDeclaration,
    completionDetails as nativeCompletionDetails,
    completionsAt,
    definitionInExpansion as nativeDefinitionInExpansion,
    directCalls as nativeDirectCalls,
    expandFile,
    expandedMacro,
    extendSelection,
    fileSymbols as nativeFileSymbols,
    findReferences,
    foldingRanges,
    formatting as nativeFormatting,
    highlight,
    highlightRelated,
    hoverInExpansion as nativeHoverInExpansion,
    implementationsAt,
    incomingCalls as nativeIncomingCalls,
    macroCallAt,
    outgoingCalls as nativeOutgoingCalls,
    prepareCallHierarchy as nativePrepareCallHierarchy,
    rangeFormatting as nativeRangeFormatting,
    trackedCallRoots as nativeTrackedCallRoots,
    typeDefinitionAt,
    typeDefinitionInExpansion as nativeTypeDefinitionInExpansion,
    workspaceSymbols
}
import loupe.db.SourceFile
import loupe.hir.{
    Body,
    BodyMacroCall,
    DefId,
    ExprId,
    ExprScopes,
    ExtendedType,
    FieldResolution,
    InferenceResult,
    Item,
    ItemFile,
    ItemId,
    LoweredBody,
    MacroCallId,
    MemberTarget,
    Receiver,
    Signature,
    SignatureTypes,
    Ty,
    TyKind,
    TypeScope,
    WhenDiagnostics,
    allMembers as nativeAllMembers,
    body as nativeBody,
    bodyMacroCalls,
    bodyWithSourceMap,
    declaredTyOf,
    exprScopes,
    headTysOf,
    inferBody,
    isUnknown,
    itemOf,
    itemTreeOf,
    membersNamed,
    parentOf,
    receiverOf,
    receiverTyOf,
    resolveField,
    signature as nativeSignature,
    signatureTypes as nativeSignatureTypes,
    signatureWithSourceMap as nativeSignatureWithSourceMap,
    substitute,
    supertypes as nativeSupertypes,
    typeScopeOf,
    whenDiagnostics as nativeWhenDiagnostics
}
import loupe.vfs.{FileId, VfsPath}
@When[os == "Linux"]
import py_interop.*
@When[os == "Linux"]
import py_interop.internal_macros.DerivePython

/**
 * A revision-bound analysis handle; querying it after a workspace update reports ContentModified.
 */
@When[os == "Linux"]
@DerivePython
class AnalysisRevision {
    private let owner: WorkspaceState

    @PyIgnore
    init(owner: WorkspaceState) {
        this.owner = owner
        revision = owner.revision
    }

    public let revision: Int64

    private prop state: WorkspaceState {
        get() {
            if (owner.revision != revision) {
                throw IllegalStateException(
                    "ContentModified: analysis revision ${revision} is stale; acquire workspace.analysis() again"
                )
            }
            owner
        }
    }

    /**
     * Snapshot views of this checked revision, cancelled by later input changes.
     * @throws IllegalStateException - if this handle belongs to an older workspace revision.
     */
    public func semantic(): SemanticAnalysis {
        SemanticAnalysis(state.db)
    }

    @PyDoc["Return declaration IDs for a loaded source path in this revision."]
    public func declarations(path: String): Array<DefId> {
        let file =
            state
                .db
                .sourceFile(resolve(path))
                .getOrThrow { IllegalArgumentException("file has no source analysis: ${path}") }
        let result = ArrayList<DefId>()
        collect(ItemFile.Source(file), itemTreeOf(state.db, ItemFile.Source(file)).items, result)
        result.toArray()
    }

    @PyDoc["Return the item-tree declaration associated with def."]
    public func item(def: DefId): ?Item {
        itemOf(state.db, def)
    }
    @PyDoc["Return the type-name scope of a declaration."]
    public func typeScope(def: DefId): ?TypeScope {
        typeScopeOf(state.db, def)
    }
    @PyDoc["Return conditional-compilation diagnostics for a loaded path."]
    public func whenDiagnostics(path: String): WhenDiagnostics {
        nativeWhenDiagnostics(
            state.db,
            state
                .db
                .sourceFile(resolve(path))
                .getOrThrow { IllegalArgumentException("file has no source analysis: ${path}") }
        )
    }
    @PyDoc["Return macro calls discovered inside the declaration body."]
    public func bodyMacros(path: String): Array<BodyMacroCall> {
        bodyMacroCalls(
            state.db,
            state
                .db
                .sourceFile(resolve(path))
                .getOrThrow { IllegalArgumentException("file has no source analysis: ${path}") }
        )
    }
    @PyDoc["Return the lowered written signature of a declaration."]
    public func signature(def: DefId): Signature {
        nativeSignature(state.db, def)
    }
    @PyDoc["Return the written signature together with its source mapping."]
    public func signatureWithSourceMap(def: DefId): PythonLoweredSignature {
        PythonLoweredSignature(nativeSignatureWithSourceMap(state.db, def))
    }
    @PyDoc["Return resolved signature types, generic bounds and signature type errors."]
    public func signatureTypes(def: DefId): SignatureTypes {
        nativeSignatureTypes(state.db, def)
    }
    @PyDoc["Return the lowered body of a declaration."]
    public func body(def: DefId): Body {
        nativeBody(state.db, def)
    }
    @PyDoc["Return the lowered body with mappings between HIR IDs and source syntax."]
    public func loweredBody(def: DefId): LoweredBody {
        bodyWithSourceMap(state.db, def)
    }
    @PyDoc["Return lexical scopes and body expression/type scope mappings."]
    public func scopes(def: DefId): ExprScopes {
        exprScopes(state.db, def)
    }
    @PyDoc["Build displayed expanded text with the supplied header and source-origin mappings."]
    public func expandedFile(path: String, header: String): ?ExpandedFile {
        expandFile(state.db, resolve(path), header)
    }
    @PyDoc["Return declarations eligible as roots for immediate tracked call evidence in path."]
    public func trackedCallRoots(path: String): Array<DefId> {
        nativeTrackedCallRoots(state.db, resolve(path))
    }
    @PyDoc["Return immediate call evidence and explicit gaps for a declaration; this is not a transitive call graph."]
    public func directCalls(def: DefId): DirectCalls {
        nativeDirectCalls(state.db, def)
    }
    @PyDoc["Return declaration metadata for a call-evidence target."]
    public func callDeclaration(def: DefId): CallDeclaration {
        nativeCallDeclaration(state.db, def)
    }
    @PyDoc["Return body inference results, including types, resolutions and diagnostics."]
    public func infer(def: DefId): InferenceResult {
        inferBody(state.db, def)
    }
    @PyDoc["Return the declared type associated with a declaration."]
    public func declaredType(def: DefId): Ty {
        declaredTyOf(state.db, def)
    }
    @PyDoc["Inspect the native TyKind of a type from this revision."]
    public func typeKind(ty: Ty): TyKind {
        ty.kind(state.db)
    }
    @PyDoc["Format a type from this revision for display."]
    public func typeText(ty: Ty): String {
        ty.text(state.db)
    }
    @PyDoc["Whether the type represents an unknown analysis result."]
    public func isTypeUnknown(ty: Ty): Bool {
        isUnknown(state.db, ty)
    }
    @PyDoc["Intern a native TyKind in this revision and return its Ty handle."]
    public func internType(kind: TyKind): Ty {
        Ty(state.db, kind)
    }
    @PyDoc["Substitute owner generic parameters with args in ty."]
    public func substituteType(ty: Ty, owner: DefId, args: Array<Ty>): Ty {
        substitute(state.db, ty, owner, args)
    }
    @PyDoc["Return the head types considered by native type lookup."]
    public func headTypes(ty: Ty): Array<Ty> {
        headTysOf(state.db, ty)
    }
    @PyDoc["Return member targets named name on the declaration."]
    public func members(def: DefId, name: String): Array<MemberTarget> {
        membersNamed(state.db, def, name)
    }
    @PyDoc["Return all member targets considered by native member lookup."]
    public func allMembers(def: DefId): Array<MemberTarget> {
        nativeAllMembers(state.db, def)
    }
    @PyDoc["Return the declaration supertypes as native ExtendedType values."]
    public func supertypes(def: DefId): Array<ExtendedType> {
        nativeSupertypes(state.db, def)
    }
    @PyDoc["Resolve a field-access expression in the declaration body."]
    public func field(def: DefId, expr: ExprId): FieldResolution {
        resolveField(state.db, def, expr)
    }
    @PyDoc["Return native receiver evidence for a body expression."]
    public func receiver(def: DefId, expr: ExprId): Receiver {
        receiverOf(state.db, def, expr)
    }
    @PyDoc["Return the type of a resolved receiver, or None when unavailable."]
    public func receiverType(def: DefId, expr: ExprId): ?Ty {
        receiverTyOf(state.db, def, expr)
    }
    @PyDoc["Resolve a loaded path to its native FileId; relative paths use the selected root."]
    public func fileId(path: String): FileId {
        resolve(path)
    }
    @PyDoc["Return the physical FileId associated with a contextual SourceFile."]
    public func sourceFileId(file: SourceFile): FileId {
        file.fileId(state.db)
    }
    @PyDoc["Return text from this revision. Raises RuntimeError if a loaded file has no text."]
    public func text(path: String): String {
        state
            .vfs
            .fileContents(resolve(path))
            .getOrThrow { IllegalStateException("loaded file has no contents") }
            .toString()
    }
    @PyDoc["Return the enclosing declaration, or None for a top-level declaration."]
    public func parent(def: DefId): ?DefId {
        parentOf(state.db, def)
    }
    @PyDoc["Return the source, binary or expansion ItemFile containing def."]
    public func definitionFile(def: DefId): ItemFile {
        def.file(state.db)
    }
    @PyDoc["Return the item-tree ID associated with def."]
    public func definitionItem(def: DefId): ItemId {
        def.item(state.db)
    }
    @PyDoc["Return the path associated with a physical FileId."]
    public func path(file: FileId): String {
        state.vfs.paths.path(file).toString()
    }

    /**
     * Written ranges by expression index; None marks synthetic expressions.
     */
    public func expressionRanges(def: DefId): Array<?TextRange> {
        bodyWithSourceMap(state.db, def)
            .sourceMap
            .exprs
            .map {
                origin =>
                origin
                    .written
                    .filter { source => source.expansion.isNone() }
                    .map { source => source.ptr.range }
            }
    }

    @PyDoc["Optional written declaration ranges indexed by LocalId; None for bindings without a written non-expansion source."]
    public func localRanges(def: DefId): Array<?TextRange> {
        bodyWithSourceMap(state.db, def)
            .sourceMap
            .locals
            .map {
                origin =>
                origin
                    .written
                    .filter { source => source.expansion.isNone() }
                    .map { source => source.ptr.range }
            }
    }

    @PyDoc["Return completion candidates at a UTF-8 byte offset in a loaded path."]
    public func completions(path: String, offset: Int64): ?CompletionResult {
        completionsAt(state.db, position(path, offset), offset)
    }
    @PyDoc["Resolve deferred completion details for a completion candidate."]
    public func completionDetails(
        path: String,
        offset: Int64,
        item: CompletionItem
    ): Array<HoverItem> {
        nativeCompletionDetails(state.db, position(path, offset), offset, item)
    }
    @PyDoc["Return reference sites at a UTF-8 byte offset, retaining each site's declaration marker."]
    public func references(path: String, offset: Int64): Array<AnalysisReference> {
        findReferences(state.db, position(path, offset), offset)
    }
    @PyDoc["Return type-definition targets at a UTF-8 byte offset."]
    public func typeDefinition(path: String, offset: Int64): Array<NavigationTarget> {
        typeDefinitionAt(state.db, position(path, offset), offset)
    }
    @PyDoc["Return implementation targets at a UTF-8 byte offset."]
    public func implementations(path: String, offset: Int64): Array<NavigationTarget> {
        implementationsAt(state.db, position(path, offset), offset)
    }
    @PyDoc["Return related-symbol highlights at a UTF-8 byte offset."]
    public func related(path: String, offset: Int64): Array<RelatedHighlight> {
        highlightRelated(state.db, position(path, offset), offset)
    }
    @PyDoc["Return semantic highlighting ranges for a loaded path."]
    public func highlights(path: String): Array<HighlightedRange> {
        highlight(state.db, resolve(path))
    }
    @PyDoc["Return foldable source ranges for a loaded path."]
    public func folding(path: String): Array<Fold> {
        foldingRanges(state.db, resolve(path))
    }
    @PyDoc["Return enclosing selection ranges at a UTF-8 byte offset."]
    public func selection(path: String, offset: Int64): Array<TextRange> {
        extendSelection(state.db, position(path, offset), offset)
    }
    @PyDoc["Search workspace symbols by query, returning at most limit matches; a full limit may omit matches."]
    public func symbols(query: String, limit: Int64): Array<FoundSymbol> {
        workspaceSymbols(state.db, state.files.map { p => resolve(p.toString()) }, query, limit)
    }
    @PyDoc["Return declaration symbols and their UTF-8 source ranges for a loaded path."]
    public func fileSymbols(path: String): Array<FileSymbol> {
        nativeFileSymbols(
            state.db,
            state
                .db
                .sourceFile(resolve(path))
                .getOrThrow { IllegalArgumentException("file has no source analysis: ${path}") }
        )
    }
    @PyDoc["Return documentation for a built-in type name, or None when unknown."]
    public func builtinTypeDoc(name: String): ?BuiltinDoc {
        let _ = state
        nativeBuiltinTypeDoc(name)
    }
    @PyDoc["Return documentation for a built-in annotation name, or None when unknown."]
    public func builtinAnnotationDoc(name: String): ?BuiltinDoc {
        let _ = state
        nativeBuiltinAnnotationDoc(name)
    }
    @PyDoc["Return documentation for a built-in macro name, or None when unknown."]
    public func builtinMacroDoc(name: String): ?BuiltinDoc {
        let _ = state
        nativeBuiltinMacroDoc(name)
    }
    @PyDoc["Return the package header for a new path, or None outside loaded packages."]
    public func newFilePackageLine(path: String): ?String {
        state.packageLine(absolutePath(path))
    }
    // Explicit overloads keep the defaults available through py_interop's exact argument matching.
    @PyDoc["Return UTF-8 TextEdits without applying them; None means syntax errors, [] means already formatted. Options default to library defaults."]
    public func formatting(path: String): ?Array<TextEdit> {
        nativeFormatting(state.db, resolve(path))
    }
    @PyDoc["Return UTF-8 TextEdits without applying them; None means syntax errors, [] means already formatted. Options default to library defaults."]
    public func formatting(path: String, options!: FormatOptions): ?Array<TextEdit> {
        nativeFormatting(state.db, resolve(path), options: options)
    }
    @PyDoc["Return formatting edits for the enclosing syntax node of a UTF-8 range. None means syntax errors. Options default to library defaults."]
    public func rangeFormatting(path: String, range: TextRange): ?Array<TextEdit> {
        rangeFormatting(path, range, options: FormatOptions())
    }
    @PyDoc["Return formatting edits for the enclosing syntax node of a UTF-8 range. None means syntax errors. Options default to library defaults."]
    public func rangeFormatting(
        path: String,
        range: TextRange,
        options!: FormatOptions
    ): ?Array<TextEdit> {
        let file = position(path, range.start)
        position(path, range.end)
        nativeRangeFormatting(state.db, file, range, options: options)
    }
    @PyDoc["Return callable hierarchy entries at a UTF-8 byte offset."]
    public func prepareCallHierarchy(path: String, offset: Int64): Array<CallHierarchyEntry> {
        nativePrepareCallHierarchy(state.db, position(path, offset), offset)
    }
    @PyDoc["Return direct caller groups and their call-site ranges."]
    public func incomingCalls(entry: CallHierarchyEntry): Array<HierarchyCalls> {
        nativeIncomingCalls(state.db, entry)
    }
    @PyDoc["Return direct callee groups and their call-site ranges."]
    public func outgoingCalls(entry: CallHierarchyEntry): Array<HierarchyCalls> {
        nativeOutgoingCalls(state.db, entry)
    }
    @PyDoc["Find the macro call at a UTF-8 byte offset, or None when absent."]
    public func macroCall(path: String, offset: Int64): ?MacroCallAt {
        macroCallAt(state.db, position(path, offset), offset)
    }
    @PyDoc["Return a macro expansion and its source mapping when available."]
    public func expansion(call: MacroCallId): ?ExpandedMacro {
        expandedMacro(state.db, call)
    }
    @PyDoc["Return hover information at a UTF-8 offset in expansion text."]
    public func hoverInExpansion(call: MacroCallId, offset: Int64): ?HoverResult {
        expansionPosition(call, offset)
        nativeHoverInExpansion(state.db, call, offset)
    }
    @PyDoc["Return definition targets at a UTF-8 offset in expansion text."]
    public func definitionInExpansion(call: MacroCallId, offset: Int64): Array<NavigationTarget> {
        expansionPosition(call, offset)
        nativeDefinitionInExpansion(state.db, call, offset)
    }
    @PyDoc["Return type-definition targets at a UTF-8 offset in expansion text."]
    public func typeDefinitionInExpansion(
        call: MacroCallId,
        offset: Int64
    ): Array<NavigationTarget> {
        expansionPosition(call, offset)
        nativeTypeDefinitionInExpansion(state.db, call, offset)
    }

    private func expansionPosition(call: MacroCallId, offset: Int64): Unit {
        let text =
            expandedMacro(state.db, call)
                .getOrThrow { IllegalArgumentException("macro expansion is unavailable") }
                .text
        checkOffset(text.toArray(), offset)
    }

    private func collect(file: ItemFile, items: Array<Item>, result: ArrayList<DefId>): Unit {
        for (item in items) {
            result.add(DefId(state.db, file, item.id))
            collect(file, item.members, result)
        }
    }
    private func resolve(path: String): FileId {
        let absolute = absolutePath(path)
        state.vfs.fileId(absolute) ??
            throw IllegalArgumentException("file is not loaded: ${absolute}")
    }
    private func absolutePath(path: String): VfsPath {
        if (Path(path).isAbsolute()) { VfsPath.file(path) } else { state.root.join(path) }
    }
    private func position(path: String, offset: Int64): FileId {
        let file = resolve(path)
        let text = state
            .vfs
            .fileContents(file)
            .getOrThrow { IllegalStateException("loaded file has no contents") }
            .toString()
            .toArray()
        checkOffset(text, offset)
        file
    }
    private func checkOffset(text: Array<Byte>, offset: Int64): Unit {
        if (
            offset < 0 || offset > text.size ||
                (offset < text.size && (text[offset] & 0xC0) == 0x80)
        ) {
            throw IllegalArgumentException("offset must be a UTF-8 byte boundary within the text")
        }
    }
}
